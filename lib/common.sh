#!/bin/bash

eval "$(go env)"

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
USER="$(whoami)"

# Get variables from the config file
if [ -z "${CONFIG:-}" ]; then
    # See if there's a config_$USER.sh in the SCRIPTDIR
    if [ ! -f "${SCRIPTDIR}/config_${USER}.sh" ]; then
        cp "${SCRIPTDIR}/config_example.sh" "${SCRIPTDIR}/config_${USER}.sh"
        echo "Automatically created config_${USER}.sh with default contents."
    fi
    CONFIG="${SCRIPTDIR}/config_${USER}.sh"
fi
# shellcheck disable=SC1090
source "$CONFIG"

# Set variables
# Additional DNS
ADDN_DNS=${ADDN_DNS:-}
# External interface for routing traffic through the host
EXT_IF=${EXT_IF:-}
# Provisioning interface
PRO_IF=${PRO_IF:-}
# Does libvirt manage the baremetal bridge (including DNS and DHCP)
MANAGE_BR_BRIDGE=${MANAGE_BR_BRIDGE:-y}
# Only manage bridges if is set
MANAGE_PRO_BRIDGE=${MANAGE_PRO_BRIDGE:-y}
MANAGE_INT_BRIDGE=${MANAGE_INT_BRIDGE:-y}
# Internal interface, to bridge virbr0
INT_IF=${INT_IF:-}
#Root disk to deploy coreOS - use /dev/sda on BM
ROOT_DISK_NAME=${ROOT_DISK_NAME-"/dev/sda"}
#Container runtime
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-"podman"}

export EXTERNAL_SUBNET="192.168.111.0/24"

export SSH_PUB_KEY=~/.ssh/id_rsa.pub

FILESYSTEM=${FILESYSTEM:="/"}

WORKING_DIR=${WORKING_DIR:-"/opt/metal3-dev-env"}
NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}

export NUM_MASTERS=${NUM_MASTERS:-"1"}
export NUM_WORKERS=${NUM_WORKERS:-"1"}
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}

# VBMC and Redfish images
export VBMC_IMAGE=${VBMC_IMAGE:-"quay.io/metal3-io/vbmc"}
export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}

# Ironic vars
export IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metal3-io/ironic:master"}
export IRONIC_INSPECTOR_IMAGE=${IRONIC_INSPECTOR_IMAGE:-"quay.io/metal3-io/ironic-inspector"}
export IRONIC_DATA_DIR="$WORKING_DIR/ironic"

# Test and verification related variables
SKIP_RETRIES="${SKIP_RETRIES:-false}"
TEST_TIME_INTERVAL="${TEST_TIME_INTERVAL:-10}"
TEST_MAX_TIME="${TEST_MAX_TIME:-120}"
FAILS=0
RESULT_STR=""

# Verify requisites/permissions
# Connect to system libvirt
export LIBVIRT_DEFAULT_URI=qemu:///system
if [ "$USER" != "root" ] && [ "${XDG_RUNTIME_DIR:-}" == "/run/user/0" ] ; then
    echo "Please use a non-root user, WITH a login shell (e.g. su - USER)"
    exit 1
fi

# Check if sudo privileges without password
if ! sudo -n uptime &> /dev/null ; then
  echo "sudo without password is required"
  exit 1
fi

# Check OS
export OS=$(awk -F= '/^ID=/ { print $2 }' /etc/os-release | tr -d '"')
if [[ ! $OS =~ ^(centos|rhel|ubuntu)$ ]]; then
  echo "Unsupported OS"
  exit 1
fi

# Check CentOS version
os_version=$(awk -F= '/^VERSION_ID=/ { print $2 }' /etc/os-release | tr -d '"' | cut -f1 -d'.')
if [[ ${os_version} -ne 7 ]] && [[ ${os_version} -ne 8 ]] && [[ ${os_version} -ne 18 ]]; then
  echo "Required CentOS 7 or RHEL 7/8 or Ubuntu 18.04"
  exit 1
fi

# Check d_type support
FSTYPE=$(df ${FILESYSTEM} --output=fstype | grep -v Type)

case ${FSTYPE} in
  'ext4'|'btrfs')
  ;;
  'xfs')
    # shellcheck disable=SC2143
    if [[ $(xfs_info ${FILESYSTEM} | grep -q "ftype=1") ]]; then
      echo "Filesystem not supported"
      exit 1
    fi
  ;;
  *)
    echo "Filesystem not supported"
    exit 1
  ;;
esac

if [ ! -d "$WORKING_DIR" ]; then
  echo "Creating Working Dir"
  sudo mkdir "$WORKING_DIR"
  sudo chown "${USER}:${USER}" "$WORKING_DIR"
  chmod 755 "$WORKING_DIR"
fi

function list_nodes() {
    # Includes -machine and -machine-namespace
    # shellcheck disable=SC2002
    cat "$NODES_FILE" | \
        jq '.nodes[] | {
           name,
           driver,
           address:.driver_info.ipmi_address,
           port:.driver_info.ipmi_port,
           user:.driver_info.ipmi_username,
           password:.driver_info.ipmi_password,
           mac: .ports[0].address
           } |
           .name + " " +
           .driver + "://" + .address + (if .port then ":" + .port else "" end)  + " " +
           .user + " " + .password + " " + .mac' \
       | sed 's/"//g'
}

#
# Iterate a command until it runs successfully or exceeds the maximum retries
#
# Inputs:
# - the command to run
#
iterate(){
  local RUNS=0
  local COMMAND="$*"
  local TMP_RET TMP_RET_CODE
  TMP_RET="$(${COMMAND})"
  TMP_RET_CODE="$?"

  until [[ "${TMP_RET_CODE}" == 0 ]] || [[ "${SKIP_RETRIES}" == true ]]
  do
    if [[ "${RUNS}" == "0" ]]; then
      echo "   - Waiting for task completion (up to" \
        "$((TEST_TIME_INTERVAL*TEST_MAX_TIME)) seconds)" \
        " - Command: '${COMMAND}'"
    fi
    RUNS="$((RUNS+1))"
    if [[ "${RUNS}" == "${TEST_MAX_TIME}" ]]; then
      break
    fi
    sleep "${TEST_TIME_INTERVAL}"
    # shellcheck disable=SC2068
    TMP_RET="$(${COMMAND})"
    TMP_RET_CODE="$?"
  done
  FAILS=$((FAILS+TMP_RET_CODE))
  echo "${TMP_RET}"
  return "${TMP_RET_CODE}"
}


#
# Check the return code
#
# Inputs:
# - return code to check
# - message to print
#
process_status(){
  if [[ "${1}" == 0 ]]; then
    echo "OK - ${RESULT_STR}"
    return 0
  else
    echo "FAIL - ${RESULT_STR}"
    FAILS=$((FAILS+1))
    return 1
  fi
}

#
# Compare if the two inputs are the same and log
#
# Inputs:
# - first input to compare
# - second input to compare
#
equals(){
  [[ "${1}" == "${2}" ]]; RET_CODE="$?"
  if ! process_status "$RET_CODE" ; then
    echo "       expected ${2}, got ${1}"
  fi
  return $RET_CODE
}

#
# Compare the substring to the string and log
#
# Inputs:
# - Substring to look for
# - String to look for the substring in
#
is_in(){
  [[ "${2}" == *"${1}"* ]]; RET_CODE="$?"
  if ! process_status "$RET_CODE" ; then
    echo "       expected ${1} to be in ${2}"
  fi
  return $RET_CODE
}


#
# Check if the two inputs differ and log
#
# Inputs:
# - first input to compare
# - second input to compare
#
differs(){
  [[ "${1}" != "${2}" ]]; RET_CODE="$?"
  if ! process_status "$RET_CODE" ; then
    echo "       expected to be different from ${2}, got ${1}"
  fi
  return $RET_CODE
}
