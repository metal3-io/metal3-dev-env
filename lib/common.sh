#!/bin/bash

[[ ":$PATH:" != *":/usr/local/go/bin:"* ]] && PATH="$PATH:/usr/local/go/bin"

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

if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  export POD_NAME="--pod ironic-pod"
else
  export POD_NAME=""
fi

export EXTERNAL_SUBNET="192.168.111.0/24"

export SSH_PUB_KEY=~/.ssh/id_rsa.pub

FILESYSTEM=${FILESYSTEM:="/"}

WORKING_DIR=${WORKING_DIR:-"/opt/metal3-dev-env"}
NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}

export NUM_MASTERS=${NUM_MASTERS:-"1"}
export NUM_WORKERS=${NUM_WORKERS:-"1"}
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}

# Docker registry for local images
export DOCKER_REGISTRY_IMAGE=${DOCKER_REGISTRY_IMAGE:-"docker.io/registry:latest"}

# VBMC and Redfish images
export VBMC_IMAGE=${VBMC_IMAGE:-"quay.io/metal3-io/vbmc"}
export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}

# Ironic vars
export IPA_DOWNLOADER_IMAGE=${IPA_DOWNLOADER_IMAGE:-"quay.io/metal3-io/ironic-ipa-downloader:master"}
export IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metal3-io/ironic"}
export IRONIC_INSPECTOR_IMAGE=${IRONIC_INSPECTOR_IMAGE:-"quay.io/metal3-io/ironic-inspector"}
export IRONIC_DATA_DIR="$WORKING_DIR/ironic"
export IRONIC_IMAGE_DIR="$IRONIC_DATA_DIR/html/images"

# Baremetal operator image
export BAREMETAL_OPERATOR_IMAGE=${BAREMETAL_OPERATOR_IMAGE:-"quay.io/metal3-io/baremetal-operator:master"}

# Config for OpenStack CLI
export OPENSTACK_CONFIG=$HOME/.config/openstack/clouds.yaml

# v1alpha2 var
export V1ALPHA2_SWITCH=${V1ALPHA2_SWITCH:-"false"}

# Cluster.
export CLUSTER_NAME=${CLUSTER_NAME:-"test1"}
export KUBERNETES_VERSION=${KUBERNETES_VERSION:-"v1.16.0"}

# Image url and checksum
IMAGE_OS=${IMAGE_OS:-Cirros}
if [[ "${IMAGE_OS}" == "Ubuntu" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-bionic-server-cloudimg-amd64.img}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://cloud-images.ubuntu.com/bionic/current}
  export IMAGE_USERNAME=${IMAGE_USERNAME:-ubuntu}
elif [[ "${IMAGE_OS}" == "Centos" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-CentOS-7-x86_64-GenericCloud-1907.qcow2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-http://cloud.centos.org/centos/7/images}
  export IMAGE_USERNAME=${IMAGE_USERNAME:-centos}
else
  export IMAGE_NAME=${IMAGE_NAME:-cirros-0.4.0-x86_64-disk.img}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-http://download.cirros-cloud.net/0.4.0}
  export IMAGE_USERNAME=${IMAGE_USERNAME:-cirros}
fi
export IMAGE_URL=http://172.22.0.1/images/${IMAGE_NAME}
export IMAGE_CHECKSUM=http://172.22.0.1/images/${IMAGE_NAME}.md5sum

#Path to CRs
export V1ALPHA2_CR_PATH=${SCRIPTDIR}/crs/v1alpha2/

#Kustomize version
export KUSTOMIZE_VERSION=${KUSTOMIZE_VERSION:-"v3.2.3"}

# Test and verification related variables
SKIP_RETRIES="${SKIP_RETRIES:-false}"
TEST_TIME_INTERVAL="${TEST_TIME_INTERVAL:-10}"
TEST_MAX_TIME="${TEST_MAX_TIME:-240}"
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
OS=$(awk -F= '/^ID=/ { print $2 }' /etc/os-release | tr -d '"')
export OS
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

# Use firewalld on CentOS/RHEL, iptables everywhere else
export USE_FIREWALLD=False
if [[ ($OS == "rhel" || $OS = "centos") && ${os_version} == 8 ]]
then
  export USE_FIREWALLD=True
fi

# Check d_type support
FSTYPE=$(df "${FILESYSTEM}" --output=fstype | grep -v Type)

case ${FSTYPE} in
  'ext4'|'btrfs')
  ;;
  'xfs')
    # shellcheck disable=SC2143
    if [[ $(xfs_info "${FILESYSTEM}" | grep -q "ftype=1") ]]; then
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
           address:.driver_info.address,
           port:.driver_info.port,
           user:.driver_info.username,
           password:.driver_info.password,
           mac: .ports[0].address
           } |
           .name + " " +
           .address + " " +
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

#
# Create Minikube VM and add correct interfaces
#
function init_minikube() {
    #If the vm exists, it has already been initialized
    if [[ "$(sudo virsh list --all)" != *"minikube"* ]]; then
      sudo su -l -c "minikube start --insecure-registry 192.168.111.1:5000" "$USER"
      # Pre-pull the image to reduce pod initialization time
      for IMAGE_VAR in IRONIC_IMAGE IPA_DOWNLOADER_IMAGE IRONIC_INSPECTOR_IMAGE BAREMETAL_OPERATOR_IMAGE; do
        IMAGE=${!IMAGE_VAR}
        sudo su -l -c "minikube ssh sudo docker pull $IMAGE" "${USER}"
      done
      sudo su -l -c "minikube ssh sudo docker image ls" "${USER}"
      sudo su -l -c "minikube stop" "$USER"
    fi

    MINIKUBE_IFACES="$(sudo virsh domiflist minikube)"

    # The interface doesn't appear in the minikube VM with --live,
    # so just attach it before next boot. As long as the
    # 02_configure_host.sh script does not run, the provisioning network does
    # not exist. Attempting to start Minikube will fail until it is created.
    if ! echo "$MINIKUBE_IFACES" | grep -w provisioning  > /dev/null ; then
      sudo virsh attach-interface --domain minikube \
          --model virtio --source provisioning \
          --type network --config
    fi

    if ! echo "$MINIKUBE_IFACES" | grep -w baremetal  > /dev/null ; then
      sudo virsh attach-interface --domain minikube \
          --model virtio --source baremetal \
          --type network --config
    fi
}
