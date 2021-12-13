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
export MARIADB_HOST="mariaDB"
export MARIADB_HOST_IP="127.0.0.1"
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
# Root disk to deploy coreOS - use /dev/sda on BM
ROOT_DISK_NAME=${ROOT_DISK_NAME-"/dev/sda"}
# Hostname format
NODE_HOSTNAME_FORMAT=${NODE_HOSTNAME_FORMAT:-"node-%d"}
# Check OS type and version
# shellcheck disable=SC1091
source /etc/os-release
export DISTRO="${ID}${VERSION_ID%.*}"
export OS="${ID}"
export OS_VERSION_ID=$VERSION_ID
export SUPPORTED_DISTROS=(centos8 rhel8 ubuntu18 ubuntu20)

if [[ ! "${SUPPORTED_DISTROS[*]}" =~ $DISTRO ]]; then
   echo "Supported OS distros for the host are: CentOS Stream 8 or RHEL8 or Ubuntu20.04"
   exit 1
fi

# Container runtime
if [[ "${OS}" == ubuntu ]]; then
  export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-"docker"}
else
  export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-"podman"}
fi
# Pod names
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
# M3PATH : Path to clone the Metal3 Development Environment repository
# BMOPATH : Path to clone the Bare Metal Operator repository
# CAPM3PATH : Path to clone the Cluster API Provider Metal3 repository
#
# BMOREPO : Baremetal Operator repository URL
# BMOBRANCH : Baremetal Operator repository branch to checkout
# CAPM3REPO : Cluster API Provider Metal3 repository URL
# CAPM3BRANCH : Cluster API Provider Metal3 repository branch to checkout
# FORCE_REPO_UPDATE : discard existing directories
#
# BMO_RUN_LOCAL : run the Baremetal Operator locally (not in Kubernetes cluster)
# CAPM3_RUN_LOCAL : run the Cluster API Provider Metal3 locally

CAPM3_VERSION_LIST="v1alpha4 v1alpha5 v1beta1"
export CAPM3_VERSION="${CAPM3_VERSION:-"v1beta1"}"

if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
  export CAPI_VERSION="v1alpha3"
elif [ "${CAPM3_VERSION}" == "v1alpha5" ]; then
  export CAPI_VERSION="v1alpha4"
elif [ "${CAPM3_VERSION}" == "v1beta1" ]; then
  export CAPI_VERSION="v1beta1"
else
  echo "Invalid CAPM3 version : ${CAPM3_VERSION}. Not in : ${CAPM3_VERSION_LIST}"
  exit 1
fi

export M3PATH="${M3PATH:-${GOPATH}/src/github.com/metal3-io}"
export BMOPATH="${BMOPATH:-${M3PATH}/baremetal-operator}"
# shellcheck disable=SC2034
export RUN_LOCAL_IRONIC_SCRIPT="${BMOPATH}/tools/run_local_ironic.sh"

export CAPM3PATH="${CAPM3PATH:-${M3PATH}/cluster-api-provider-metal3}"
export CAPM3_BASE_URL="${CAPM3_BASE_URL:-metal3-io/cluster-api-provider-metal3}"
export CAPM3REPO="${CAPM3REPO:-https://github.com/${CAPM3_BASE_URL}}"

export IPAMPATH="${IPAMPATH:-${M3PATH}/ip-address-manager}"
export IPAM_BASE_URL="${IPAM_BASE_URL:-metal3-io/ip-address-manager}"
export IPAMREPO="${IPAMREPO:-https://github.com/${IPAM_BASE_URL}}"

if [ "${CAPI_VERSION}" == "v1alpha3" ]; then
  IPAMBRANCH="${IPAMBRANCH:-release-0.0}"
elif [ "${CAPI_VERSION}" == "v1alpha4" ]; then
  IPAMBRANCH="${IPAMBRANCH:-release-0.1}"
else
  IPAMBRANCH="${IPAMBRANCH:-main}"
fi

IPA_DOWNLOAD_ENABLED="${IPA_DOWNLOAD_ENABLED:-true}"

CAPI_BASE_URL="${CAPI_BASE_URL:-kubernetes-sigs/cluster-api}"

if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
  CAPM3BRANCH="${CAPM3BRANCH:-release-0.4}"
elif [ "${CAPM3_VERSION}" == "v1alpha5" ]; then
  CAPM3BRANCH="${CAPM3BRANCH:-release-0.5}"
else
  CAPM3BRANCH="${CAPM3BRANCH:-main}"
fi

BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
BMOBRANCH="${BMOBRANCH:-master}"
FORCE_REPO_UPDATE="${FORCE_REPO_UPDATE:-true}"
BMOCOMMIT="${BMOCOMMIT:-HEAD}"

BMO_RUN_LOCAL="${BMO_RUN_LOCAL:-false}"
CAPM3_RUN_LOCAL="${CAPM3_RUN_LOCAL:-false}"

WORKING_DIR=${WORKING_DIR:-"/opt/metal3-dev-env"}
NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}

# Metal3
export NAMESPACE=${NAMESPACE:-"metal3"}
export NUM_NODES=${NUM_NODES:-"2"}
export NUM_OF_MASTER_REPLICAS="${NUM_OF_MASTER_REPLICAS:-"1"}"
export NUM_OF_WORKER_REPLICAS="${NUM_OF_WORKER_REPLICAS:-"1"}"
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}
export VM_EXTRADISKS_FILE_SYSTEM=${VM_EXTRADISKS_FILE_SYSTEM:-"ext4"}
export VM_EXTRADISKS_MOUNT_DIR=${VM_EXTRADISKS_MOUNT_DIR:-"/mnt/disk2"}
export NODE_DRAIN_TIMEOUT=${NODE_DRAIN_TIMEOUT:-"0s"}
export MAX_SURGE_VALUE="${MAX_SURGE_VALUE:-"1"}"

# Docker registry for local images
export DOCKER_REGISTRY_IMAGE=${DOCKER_REGISTRY_IMAGE:-"registry:2.7.1"}

# Registry to pull metal3 container images from
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"quay.io"}

# VBMC and Redfish images
export VBMC_IMAGE=${VBMC_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/vbmc"}
export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/sushy-tools"}

# Ironic vars
export IRONIC_TLS_SETUP=${IRONIC_TLS_SETUP:-"true"}
export IRONIC_BASIC_AUTH=${IRONIC_BASIC_AUTH:-"true"}
export IPA_DOWNLOADER_IMAGE=${IPA_DOWNLOADER_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ironic-ipa-downloader"}
export IRONIC_IMAGE=${IRONIC_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ironic"}
export IRONIC_CLIENT_IMAGE=${IRONIC_CLIENT_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ironic-client"}
export IRONIC_DATA_DIR="$WORKING_DIR/ironic"
export IRONIC_IMAGE_DIR="$IRONIC_DATA_DIR/html/images"
export IRONIC_KEEPALIVED_IMAGE=${IRONIC_KEEPALIVED_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/keepalived"}

if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
  export IRONIC_NAMESPACE=${IRONIC_NAMESPACE:-"capm3-system"}
  export NAMEPREFIX=${NAMEPREFIX:-"capm3"}
else
  export IRONIC_NAMESPACE=${IRONIC_NAMESPACE:-"baremetal-operator-system"}
  export NAMEPREFIX=${NAMEPREFIX:-"baremetal-operator"}
fi

# Enable ironic restart feature when the TLS certificate is updated
export RESTART_CONTAINER_CERTIFICATE_UPDATED=${RESTART_CONTAINER_CERTIFICATE_UPDATED:-${IRONIC_TLS_SETUP}}

# Baremetal operator image
export BAREMETAL_OPERATOR_IMAGE=${BAREMETAL_OPERATOR_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/baremetal-operator"}

# Config for OpenStack CLI
export OPENSTACK_CONFIG=$HOME/.config/openstack/clouds.yaml

# CAPM3 and IPAM controller images
if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:release-0.4"}
  export IPAM_IMAGE=${IPAM_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:release-0.0"}
elif [ "${CAPM3_VERSION}" == "v1alpha5" ]; then
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:release-0.5"}
  export IPAM_IMAGE=${IPAM_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:release-0.1"}
else
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:main"}
  export IPAM_IMAGE=${IPAM_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:main"}
fi

# Default hosts memory
export DEFAULT_HOSTS_MEMORY=${DEFAULT_HOSTS_MEMORY:-4096}

# Cluster
export CLUSTER_NAME=${CLUSTER_NAME:-"test1"}
export CLUSTER_APIENDPOINT_IP=${CLUSTER_APIENDPOINT_IP:-"192.168.111.249"}
export KUBERNETES_VERSION=${KUBERNETES_VERSION:-"v1.23.2"}
export KUBERNETES_BINARIES_VERSION="${KUBERNETES_BINARIES_VERSION:-${KUBERNETES_VERSION}}"
export KUBERNETES_BINARIES_CONFIG_VERSION=${KUBERNETES_BINARIES_CONFIG_VERSION:-"v0.2.7"}

# Ephemeral Cluster
if [ "${CONTAINER_RUNTIME}" == "docker" ]; then
  export EPHEMERAL_CLUSTER=${EPHEMERAL_CLUSTER:-"kind"}
else
  echo "Management cluster forced to be minikube when container runtime is not docker"
  export EPHEMERAL_CLUSTER="minikube"
fi

# Kustomize version
export KUSTOMIZE_VERSION=${KUSTOMIZE_VERSION:-"v4.1.3"}

# Kind version (if EPHEMERAL_CLUSTER=kind)
export KIND_VERSION=${KIND_VERSION:-"v0.11.1"}

# Remove this KUBERNETES_VERSION Check once we stop supporting capm3 v1a4
if [ "${KUBERNETES_VERSION}" == "v1.21.2" ]; then
  export KIND_NODE_IMAGE_VERSION="v1.21.2"
  # Minikube version (if EPHEMERAL_CLUSTER=minikube)
  export MINIKUBE_VERSION=${MINIKUBE_VERSION:-"v1.22.0"}
else 
  export KIND_NODE_IMAGE_VERSION=${KIND_NODE_IMAGE_VERSION:-"v1.22.2"}
  # Minikube version (if EPHEMERAL_CLUSTER=minikube)
  export MINIKUBE_VERSION=${MINIKUBE_VERSION:-"v1.23.2"}
fi

# Ansible version
export ANSIBLE_VERSION=${ANSIBLE_VERSION:-"4.9.0"}

# Test and verification related variables
SKIP_RETRIES="${SKIP_RETRIES:-false}"
TEST_TIME_INTERVAL="${TEST_TIME_INTERVAL:-10}"
TEST_MAX_TIME="${TEST_MAX_TIME:-240}"
FAILS=0
RESULT_STR=""

# Avoid printing skipped Ansible tasks
export ANSIBLE_DISPLAY_SKIPPED_HOSTS=no

# Sanity check for number of nodes
if [ "${NUM_NODES}" -lt "$((NUM_OF_MASTER_REPLICAS + NUM_OF_WORKER_REPLICAS))" ]; then
    echo "Failed with incorrect number of nodes"
    echo "NUM_NODES: ${NUM_NODES} < (${NUM_OF_MASTER_REPLICAS} + ${NUM_OF_WORKER_REPLICAS})"
    exit 1
fi

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

# Use firewalld on CentOS/RHEL, iptables everywhere else
export USE_FIREWALLD=False
if [[ $DISTRO == "rhel8" || $DISTRO == "centos8" ]]; then
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

# Create and grant permissions to Working Dir if it doesn't exist
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

# If a given container with tag doesn't exist locally, pull it. 
# Otherwise, do nothing.
# Helps conserve number of API calls to DockerHub to avoid hitting rate limit.
#
# Inputs:
# - Full name of a Docker/podman/crictl image including tag
#
function pull_container_image_if_missing() {
  local IMAGE="$1"
  if [ "${CONTAINER_RUNTIME}" == "docker" ]; then
    if [[ -z $(sudo "${CONTAINER_RUNTIME}" image ls "$IMAGE" | tail -n +2) ]]; then
      sudo "${CONTAINER_RUNTIME}" pull "$IMAGE"
    fi
  else
    if ! sudo "${CONTAINER_RUNTIME}" image exists "$IMAGE"; then  
      sudo "${CONTAINER_RUNTIME}" pull "$IMAGE"
    fi
  fi
}


#
# Kill and remove the infra containers
#
function remove_ironic_containers() {
  #shellcheck disable=SC2015
  for name in ipa-downloader vbmc sushy-tools httpd-infra; do
    sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill $name || true
    sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm $name -f || true
  done
}
