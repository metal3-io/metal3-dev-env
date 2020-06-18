#!/bin/bash

[[ ":$PATH:" != *":/usr/local/go/bin:"* ]] && PATH="$PATH:/usr/local/go/bin"

eval "$(go env)"
export GOPATH

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
USER="$(whoami)"
export USER=${USER}

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
# Hostname format
NODE_HOSTNAME_FORMAT=${NODE_HOSTNAME_FORMAT:-"node-%d"}


if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  export POD_NAME="--pod ironic-pod"
  export POD_NAME_INFRA="--pod infra-pod"
else
  export POD_NAME=""
  export POD_NAME_INFRA=""
fi

export SSH_KEY=${SSH_KEY:-"${HOME}/.ssh/id_rsa"}
export SSH_PUB_KEY=${SSH_PUB_KEY:-"${SSH_KEY}.pub"}
# Generate user ssh key
if [ ! -f "${SSH_KEY}" ]; then
  mkdir -p "$(dirname "$SSH_KEY")"
  ssh-keygen -f "${SSH_KEY}" -P ""
fi

FILESYSTEM=${FILESYSTEM:="/"}

# Environment variables
# M3PATH : Path to clone the metal3 dev env repo
# BMOPATH : Path to clone the baremetal operator repo
# CAPM3PATH: Path to clone the CAPI operator repo
#
# BMOREPO : Baremetal operator repository URL
# BMOBRANCH : Baremetal operator repository branch to checkout
# CAPM3REPO : CAPI operator repository URL
# CAPM3BRANCH : CAPI repository branch to checkout
# FORCE_REPO_UPDATE : discard existing directories
#
# BMO_RUN_LOCAL : run the baremetal operator locally (not in Kubernetes cluster)
# CAPM3_RUN_LOCAL : run the CAPI operator locally

function get_latest_release() {
    # shellcheck disable=SC2005
    echo "$(curl -sL "${1}"  | jq -r '.tag_name')"
}

# CAPI version
export CAPI_VERSION=${CAPI_VERSION:-"v1alpha3"}
CAPI_VERSION_LIST="v1alpha3 v1alpha4"
if ! echo "${CAPI_VERSION_LIST}" | grep -wq "${CAPI_VERSION}"; then
  echo "Invalid CAPI version : ${CAPI_VERSION}. Not in : ${CAPI_VERSION_LIST}"
  exit 1
fi

M3PATH="${M3PATH:-${GOPATH}/src/github.com/metal3-io}"
BMOPATH="${BMOPATH:-${M3PATH}/baremetal-operator}"
# shellcheck disable=SC2034
RUN_LOCAL_IRONIC_SCRIPT="${BMOPATH}/tools/run_local_ironic.sh"
CAPM3PATH="${CAPM3PATH:-${M3PATH}/cluster-api-provider-metal3}"

CAPI_BASE_URL="${CAPI_BASE_URL:-kubernetes-sigs/cluster-api}"
CAPM3_BASE_URL="${CAPM3_BASE_URL:-metal3-io/cluster-api-provider-metal3}"

CAPIREPO="${CAPIREPO:-https://github.com/${CAPI_BASE_URL}}"
CAPM3REPO="${CAPM3REPO:-https://github.com/${CAPM3_BASE_URL}}"

CAPIPATH="${CAPIPATH:-${M3PATH}/cluster-api}"
CAPM3RELEASEPATH="${CAPM3RELEASEPATH:-https://api.github.com/repos/${CAPM3_BASE_URL}/releases/latest}"
export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}")}"
if [ "${CAPI_VERSION}" == "v1alpha4" ]; then
  CAPM3BRANCH="${CAPM3BRANCH:-master}"
else
  CAPM3BRANCH="${CAPM3BRANCH:-release-0.3}"
fi
CAPIBRANCH="${CAPIBRANCH:-master}"

BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
BMOBRANCH="${BMOBRANCH:-master}"
FORCE_REPO_UPDATE="${FORCE_REPO_UPDATE:-false}"

BMO_RUN_LOCAL="${BMO_RUN_LOCAL:-false}"
CAPM3_RUN_LOCAL="${CAPM3_RUN_LOCAL:-false}"

WORKING_DIR=${WORKING_DIR:-"/opt/metal3-dev-env"}
NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}
NAMESPACE=${NAMESPACE:-"metal3"}

export NUM_NODES=${NUM_NODES:-"2"}
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}

# Docker registry for local images
export DOCKER_REGISTRY_IMAGE=${DOCKER_REGISTRY_IMAGE:-"docker.io/registry:latest"}

# VBMC and Redfish images
export VBMC_IMAGE=${VBMC_IMAGE:-"quay.io/metal3-io/vbmc"}
export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}

# Ironic vars
export IPA_DOWNLOADER_IMAGE=${IPA_DOWNLOADER_IMAGE:-"quay.io/metal3-io/ironic-ipa-downloader"}
export IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metal3-io/ironic"}
export IRONIC_CLIENT_IMAGE=${IRONIC_CLIENT_IMAGE:-"quay.io/metal3-io/ironic-client"}
export IRONIC_INSPECTOR_IMAGE=${IRONIC_INSPECTOR_IMAGE:-"quay.io/metal3-io/ironic-inspector"}
export IRONIC_DATA_DIR="$WORKING_DIR/ironic"
export IRONIC_IMAGE_DIR="$IRONIC_DATA_DIR/html/images"

# Baremetal operator image
export BAREMETAL_OPERATOR_IMAGE=${BAREMETAL_OPERATOR_IMAGE:-"quay.io/metal3-io/baremetal-operator"}

# Config for OpenStack CLI
export OPENSTACK_CONFIG=$HOME/.config/openstack/clouds.yaml

# CAPM3 controller image
if [ "${CAPI_VERSION}" == "v1alpha3" ]; then
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"quay.io/metal3-io/cluster-api-provider-metal3:release-0.3"}
else
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"quay.io/metal3-io/cluster-api-provider-metal3:master"}
fi

#default hosts memory
export DEFAULT_HOSTS_MEMORY=${DEFAULT_HOSTS_MEMORY:-8192}

# Cluster.
export CLUSTER_NAME=${CLUSTER_NAME:-"test1"}
export CLUSTER_APIENDPOINT_IP=${CLUSTER_APIENDPOINT_IP:-"192.168.111.249"}
export KUBERNETES_VERSION=${KUBERNETES_VERSION:-"v1.18.0"}
export KUBERNETES_BINARIES_VERSION="${KUBERNETES_BINARIES_VERSION:-${KUBERNETES_VERSION}}"
export KUBERNETES_BINARIES_CONFIG_VERSION=${KUBERNETES_BINARIES_CONFIG_VERSION:-"v0.2.7"}

if [ "${CONTAINER_RUNTIME}" == "docker" ]; then
  export EPHEMERAL_CLUSTER=${EPHEMERAL_CLUSTER:-"kind"}
else
  echo "Management cluster forced to be minikube when container runtime is not docker"
  export EPHEMERAL_CLUSTER="minikube"
fi
#Kustomize version
export KUSTOMIZE_VERSION=${KUSTOMIZE_VERSION:-"v3.6.1"}

#Kind version
export KIND_VERSION=${KIND_VERSION:-"v0.8.1"}

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

# Check OS type and version
OS=$(awk -F= '/^ID=/ { print $2 }' /etc/os-release | tr -d '"')
export OS
OS_VERSION=$(awk -F= '/^VERSION_ID=/ { print $2 }' /etc/os-release | tr -d '"' | cut -f1 -d'.')
export OS_VERSION
if [[ $OS == centos ]]; then
  if [[ ${OS_VERSION} != 7 && ${OS_VERSION} != 8 ]]; then
    echo "Required CentOS 7/8 or RHEL 8 or Ubuntu 18.04"
    exit 1
  fi
elif [[ $OS == rhel ]]; then
  if [[ ${OS_VERSION} -ne 8 ]]; then
    echo "Required CentOS 7/8 or RHEL 8 or Ubuntu 18.04"
    exit 1
  fi
elif [[ $OS == ubuntu ]]; then
  if [[ ${OS_VERSION} -ne 18 ]]; then
    echo "Required CentOS 7/8 or RHEL 8 or Ubuntu 18.04"
    exit 1
  fi
else
  echo "Unsupported OS: $OS"
  exit 1
fi

# Use firewalld on CentOS/RHEL, iptables everywhere else
export USE_FIREWALLD=False
if [[ ($OS == "rhel" || $OS = "centos") && ${OS_VERSION} == 8 ]]
then
  export USE_FIREWALLD=True
fi

# Check d_type support
FSTYPE=$(df "${FILESYSTEM}" --output=fstype | tail -n 1)

case ${FSTYPE} in
  'ext4'|'btrfs')
  ;;
  'xfs')
    # shellcheck disable=SC2143
    if [[ $(xfs_info "${FILESYSTEM}" | grep -q "ftype=1") ]]; then
      echo "XFS filesystem must have ftype set to 1"
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
      sudo su -l -c "minikube start --insecure-registry ${REGISTRY}" "$USER"
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
