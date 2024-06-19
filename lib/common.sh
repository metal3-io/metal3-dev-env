#!/bin/bash

[[ ! "${PATH}" =~ .*(:|^)(/usr/local/go/bin)(:|$).* ]] && export PATH="$PATH:/usr/local/go/bin"


USER="$(whoami)"
export USER
# Verify that passwordless sudo is configured correctly
if [[ "$USER" != "root" ]]; then
    if ! sudo -nl | grep -q '(ALL) NOPASSWD: ALL';then
        echo "ERROR: metal3-dev-env requires passwordless sudo configuration!"
        exit 1
    fi
fi

eval "$(go env)"
export GOPATH="${GOPATH:-/home/$(whoami)/go}"

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Get variables from the config file
if [[ -z "${CONFIG:-}" ]]; then
    # See if there's a config_$USER.sh in the SCRIPTDIR
    if [ ! -f "${SCRIPTDIR}/config_${USER}.sh" ]; then
        cp "${SCRIPTDIR}/config_example.sh" "${SCRIPTDIR}/config_${USER}.sh"
        echo "Automatically created config_${USER}.sh with default contents."
    fi
    CONFIG="${SCRIPTDIR}/config_${USER}.sh"
fi
# shellcheck disable=SC1090
source "${CONFIG}"

# CI config file for passing variables between make and make test
# used in 02 script and in run.sh
export CI_CONFIG_FILE="${TMP_DIR:-/tmp}/config_ci.sh"

# Set variables
export MARIADB_HOST="mariaDB"
export MARIADB_HOST_IP="127.0.0.1"
# Additional DNS
ADDN_DNS="${ADDN_DNS:-}"
# External interface for routing traffic through the host
EXT_IF="${EXT_IF:-}"
# Provisioning interface
PRO_IF="${PRO_IF:-}"
# Does libvirt manage the external bridge (including DNS and DHCP)
MANAGE_EXT_BRIDGE="${MANAGE_EXT_BRIDGE:-y}"
# Only manage bridges if is set
MANAGE_PRO_BRIDGE="${MANAGE_PRO_BRIDGE:-y}"
MANAGE_INT_BRIDGE="${MANAGE_INT_BRIDGE:-y}"
# Internal interface, to bridge virbr0
INT_IF="${INT_IF:-}"
# Root disk to deploy coreOS - use /dev/sda on BM
ROOT_DISK_NAME="${ROOT_DISK_NAME-'/dev/sda'}"
# Hostname format
NODE_HOSTNAME_FORMAT="${NODE_HOSTNAME_FORMAT:-'node-%d'}"
# Check OS type and version
# shellcheck disable=SC1091
source /etc/os-release
export DISTRO="${ID}${VERSION_ID%.*}"
export OS="${ID}"
export OS_VERSION_ID="${VERSION_ID}"
export SUPPORTED_DISTROS=(centos9 rhel9 ubuntu20 ubuntu22)

if [[ ! "${SUPPORTED_DISTROS[*]}" =~ ${DISTRO} ]]; then
  echo "Supported OS distros for the host are: CentOS Stream 9 or RHEL9 or Ubuntu20.04 or Ubuntu 22.04"
  exit 1
fi

# Container runtime
if [[ "${OS}" = "ubuntu" ]]; then
  export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-"docker"}
else
  export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-"podman"}
fi
# Pod names
if [[ "${CONTAINER_RUNTIME}" = "podman" ]]; then
  export POD_NAME="--pod ironic-pod"
  export POD_NAME_INFRA="--pod infra-pod"
else
  export POD_NAME=""
  export POD_NAME_INFRA=""
fi

export SSH_KEY=${SSH_KEY:-"${HOME}/.ssh/id_rsa"}
export SSH_PUB_KEY=${SSH_PUB_KEY:-"${SSH_KEY}.pub"}
# Generate user ssh key
if [[ ! -f "${SSH_KEY}" ]]; then
  mkdir -p "$(dirname "$SSH_KEY")"
  ssh-keygen -f "${SSH_KEY}" -P ""
fi
SSH_PUB_KEY_CONTENT="$(cat "${SSH_PUB_KEY}")"
export SSH_PUB_KEY_CONTENT

FILESYSTEM="${FILESYSTEM:=/}"

# Reusable repository cloning function
clone_repo() {
  local REPO_URL="$1"
  local REPO_BRANCH="$2"
  local REPO_PATH="$3"
  local REPO_COMMIT="${4:-HEAD}"

  if [[ -d "${REPO_PATH}" ]] && [[ "${FORCE_REPO_UPDATE}" = "true" ]]; then
    rm -rf "${REPO_PATH}"
  fi
  if [[ ! -d "${REPO_PATH}" ]]; then
    pushd "${M3PATH}" || exit
    if [[ "${REPO_COMMIT}" = "HEAD" ]]; then
        git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" \
            "${REPO_PATH}"
    else
        git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${REPO_PATH}"
        pushd "${REPO_PATH}" || exit
        git checkout "${REPO_COMMIT}"
        popd || exit
    fi
    popd || exit
  fi
}

# Configure common environment variables
CAPM3_VERSION_LIST="v1beta1"
export CAPM3_VERSION="${CAPM3_VERSION:-"v1beta1"}"

if [[ "${CAPM3_VERSION}" == "v1beta1" ]]; then
  export CAPI_VERSION="v1beta1"
else
  echo "Invalid CAPM3 version : ${CAPM3_VERSION}. Not in : ${CAPM3_VERSION_LIST}"
  exit 1
fi

# shellcheck disable=SC2034
# USE_LOCAL_IPA and IPA_DOWNLOAD_ENABLED also have effect on BMO repo
export IPA_BASEURI="${IPA_BASEURI:-https://tarballs.opendev.org/openstack/ironic-python-agent/dib}"
export IPA_BRANCH="${IPA_BRANCH:-master}"
export IPA_FLAVOR="${IPA_FLAVOR:-centos9}"
export USE_LOCAL_IPA="${USE_LOCAL_IPA:-false}"
export LOCAL_IPA_PATH="${LOCAL_IPA_PATH:-/tmp/dib}"
if [[ "${USE_LOCAL_IPA}" == "true" ]]; then
    export IPA_DOWNLOAD_ENABLED="false"
fi
export IPA_DOWNLOAD_ENABLED="${IPA_DOWNLOAD_ENABLED:-true}"
export FORCE_REPO_UPDATE="${FORCE_REPO_UPDATE:-true}"

export M3PATH="${M3PATH:-${GOPATH}/src/github.com/metal3-io}"
export BMOPATH="${BMOPATH:-${M3PATH}/baremetal-operator}"
export BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
export BMO_BASE_URL="${BMO_BASE_URL:-metal3-io/baremetal-operator}"

export RUN_LOCAL_IRONIC_SCRIPT="${BMOPATH}/tools/run_local_ironic.sh"

export CAPM3PATH="${CAPM3PATH:-${M3PATH}/cluster-api-provider-metal3}"
export CAPM3_BASE_URL="${CAPM3_BASE_URL:-metal3-io/cluster-api-provider-metal3}"
export CAPM3REPO="${CAPM3REPO:-https://github.com/${CAPM3_BASE_URL}}"
export CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"

if [[ "${CAPM3RELEASEBRANCH}" == "release-1.5" ]]; then
  export CAPM3BRANCH="${CAPM3BRANCH:-release-1.5}"
  export IPAMBRANCH="${IPAMBRANCH:-release-1.5}"
elif [[ "${CAPM3RELEASEBRANCH}" == "release-1.6" ]]; then
  export CAPM3BRANCH="${CAPM3BRANCH:-release-1.6}"
  export IPAMBRANCH="${IPAMBRANCH:-release-1.6}"
elif [[ "${CAPM3RELEASEBRANCH}" == "release-1.7" ]]; then
  export CAPM3BRANCH="${CAPM3BRANCH:-release-1.7}"
  export IPAMBRANCH="${IPAMBRANCH:-release-1.7}"
else
  export CAPM3BRANCH="${CAPM3BRANCH:-main}"
  export IPAMBRANCH="${IPAMBRANCH:-main}"
fi

export IPAMPATH="${IPAMPATH:-${M3PATH}/ip-address-manager}"
export IPAM_BASE_URL="${IPAM_BASE_URL:-metal3-io/ip-address-manager}"
export IPAMREPO="${IPAMREPO:-https://github.com/${IPAM_BASE_URL}}"

export CAPIPATH="${CAPIPATH:-${M3PATH}/cluster-api}"
export CAPI_BASE_URL="${CAPI_BASE_URL:-kubernetes-sigs/cluster-api}"
export CAPIREPO="${CAPIREPO:-https://github.com/${CAPI_BASE_URL}}"

export BMOCOMMIT="${BMOCOMMIT:-HEAD}"
export CAPM3COMMIT="${CAPM3COMMIT:-HEAD}"
export IPAMCOMMIT="${IPAMCOMMIT:-HEAD}"
export CAPICOMMIT="${CAPICOMMIT:-HEAD}"

export IRONIC_IMAGE_PATH="${IRONIC_IMAGE_PATH:-/tmp/ironic-image}"
export IRONIC_IMAGE_REPO="${IRONIC_IMAGE_REPO:-https://github.com/metal3-io/ironic-image.git}"
export IRONIC_IMAGE_BRANCH="${IRONIC_IMAGE_BRANCH:-main}"
export IRONIC_IMAGE_COMMIT="${IRONIC_IMAGE_COMMIT:-HEAD}"

export MARIADB_IMAGE_PATH="${MARIADB_IMAGE_PATH:-/tmp/mariadb-image}"
export MARIADB_IMAGE_REPO="${MARIADB_IMAGE_REPO:-https://github.com/metal3-io/mariadb-image.git}"
export MARIADB_IMAGE_BRANCH="${MARIADB_IMAGE_BRANCH:-main}"
export MARIADB_IMAGE_COMMIT="${MARIADB_IMAGE_COMMIT:-HEAD}"

export BUILD_CAPM3_LOCALLY="${BUILD_CAPM3_LOCALLY:-false}"
export BUILD_IPAM_LOCALLY="${BUILD_IPAM_LOCALLY:-false}"
export BUILD_BMO_LOCALLY="${BUILD_BMO_LOCALLY:-false}"
export BUILD_CAPI_LOCALLY="${BUILD_CAPI_LOCALLY:-false}"
export BUILD_IRONIC_IMAGE_LOCALLY="${BUILD_IRONIC_IMAGE_LOCALLY:-false}"
export BUILD_MARIADB_IMAGE_LOCALLY="${BUILD_MARIADB_IMAGE_LOCALLY:-false}"

# If IRONIC_FROM_SOURCE has a "true" value that
# automatically requires BUILD_IRONIC_IMAGE_LOCALLY to have "true" value too
# but it is not the case the other way around
export IRONIC_FROM_SOURCE="${IRONIC_FROM_SOURCE:-false}"
if [[ $IRONIC_FROM_SOURCE == "true" ]]; then
  export BUILD_IRONIC_IMAGE_LOCALLY="true"
fi

if [[ "${BUILD_CAPM3_LOCALLY}" == "true" ]]; then
  export CAPM3_LOCAL_IMAGE="${CAPM3PATH}"
fi
if [[ "${BUILD_IPAM_LOCALLY}" == "true" ]]; then
  export IPAM_LOCAL_IMAGE="${IPAMPATH}"
fi
if [[ "${BUILD_BMO_LOCALLY}" == "true" ]]; then
  export BARE_METAL_OPERATOR_LOCAL_IMAGE="${BMOPATH}"
fi
if [[ "${BUILD_CAPI_LOCALLY}" == "true" ]]; then
  export CAPI_LOCAL_IMAGE="${CAPIPATH}"
fi
if [[ "${BUILD_IRONIC_IMAGE_LOCALLY}" == "true" ]]; then
  export IRONIC_LOCAL_IMAGE="${IRONIC_LOCAL_IMAGE:-${IRONIC_IMAGE_PATH}}"
fi
if [[ "${BUILD_MARIADB_IMAGE_LOCALLY}" == "true" ]]; then
  export MARIADB_LOCAL_IMAGE="${MARIADB_IMAGE_PATH}"
fi

export BMO_RUN_LOCAL="${BMO_RUN_LOCAL:-false}"
export CAPM3_RUN_LOCAL="${CAPM3_RUN_LOCAL:-false}"

export WORKING_DIR="${WORKING_DIR:-/opt/metal3-dev-env}"
export NODES_FILE="${NODES_FILE:-${WORKING_DIR}/ironic_nodes.json}"
export NODES_PLATFORM="${NODES_PLATFORM:-libvirt}"
export ANSIBLE_VENV="${ANSIBLE_VENV:-"${WORKING_DIR}/venv"}"
# shellcheck disable=SC2034
ANSIBLE="${ANSIBLE_VENV}/bin/ansible"

# Metal3
export NAMESPACE="${NAMESPACE:-metal3}"
export NUM_NODES="${NUM_NODES:-2}"
export CONTROL_PLANE_MACHINE_COUNT="${CONTROL_PLANE_MACHINE_COUNT:-1}"
export WORKER_MACHINE_COUNT="${WORKER_MACHINE_COUNT:-1}"
export VM_EXTRADISKS="${VM_EXTRADISKS:-false}"
export VM_EXTRADISKS_FILE_SYSTEM="${VM_EXTRADISKS_FILE_SYSTEM:-ext4}"
export VM_EXTRADISKS_MOUNT_DIR="${VM_EXTRADISKS_MOUNT_DIR:-/mnt/disk2}"
export NODE_DRAIN_TIMEOUT="${NODE_DRAIN_TIMEOUT:-0s}"
export MAX_SURGE_VALUE="${MAX_SURGE_VALUE:-1}"
export IRONIC_TAG="${IRONIC_TAG:-latest}"
export BARE_METAL_OPERATOR_TAG="${BARE_METAL_OPERATOR_TAG:-latest}"
export KEEPALIVED_TAG="${KEEPALIVED_TAG:-latest}"
export MARIADB_TAG="${MARIADB_TAG:-latest}"

# Docker Hub proxy registry (or docker.io if no proxy)
export DOCKER_HUB_PROXY="${DOCKER_HUB_PROXY:-docker.io}"

# Docker registry for local images
export DOCKER_REGISTRY_IMAGE="${DOCKER_REGISTRY_IMAGE:-${DOCKER_HUB_PROXY}/library/registry:2.7.1}"

# Registry to pull metal3 container images from
export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-quay.io}"

# BMC emulator images
export VBMC_IMAGE="${VBMC_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/vbmc}"
export SUSHY_TOOLS_IMAGE="${SUSHY_TOOLS_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/sushy-tools}"

# CAPM3 and IPAM controller images
if [[ "${CAPM3RELEASEBRANCH}" = "release-1.5" ]]; then
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:release-1.5"}
  export IPAM_IMAGE=${IPAM_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:release-1.5"}
  export BARE_METAL_OPERATOR_TAG="v0.4.2"
  export KEEPALIVED_TAG="v0.4.2"
  export IRONIC_TAG="v23.1.0"
  export BMOBRANCH="${BMORELEASEBRANCH:-release-0.4}"
  export BMOCOMMIT="e92d770b2e8d14276c3798e6e803eec91e2e9f3c" # tag v0.4.2
elif [[ "${CAPM3RELEASEBRANCH}" = "release-1.6" ]]; then
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:release-1.6"}
  export IPAM_IMAGE=${IPAM_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:release-1.6"}
  export BARE_METAL_OPERATOR_TAG="v0.5.1"
  export KEEPALIVED_TAG="v0.5.1"
  export IRONIC_TAG="v24.0.0"
  export BMOBRANCH="${BMORELEASEBRANCH:-release-0.5}"
  export BMOCOMMIT="6f7c3ea428212ed8e91545da32b923c5f877029a" # tag v0.5.1
elif [[ "${CAPM3RELEASEBRANCH}" = "release-1.7" ]]; then
  export CAPM3_IMAGE=${CAPM3_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:release-1.7"}
  export IPAM_IMAGE=${IPAM_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:release-1.7"}
  export BARE_METAL_OPERATOR_TAG="v0.6.1"
  export KEEPALIVED_TAG="v0.6.1"
  export IRONIC_TAG="v24.1.1"
  export BMOCOMMIT="eea41f4fbcf73c5aae7e015ad552b137ae507dbb" # tag v0.6.1
  export BMOBRANCH="${BMORELEASEBRANCH:-release-0.6}"
else
  export CAPM3_IMAGE="${CAPM3_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:main}"
  export IPAM_IMAGE="${IPAM_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:main}"
  export BMOBRANCH="${BMORELEASEBRANCH:-main}"
fi

# IPXE support image
export IPXE_BUILDER_IMAGE="${IPXE_BUILDER_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/ipxe-builder}"

# Ironic vars
export IRONIC_TLS_SETUP=${IRONIC_TLS_SETUP:-"true"}
export IRONIC_BASIC_AUTH=${IRONIC_BASIC_AUTH:-"true"}
export IPA_DOWNLOADER_IMAGE=${IPA_DOWNLOADER_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ironic-ipa-downloader"}
export IRONIC_IMAGE=${IRONIC_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ironic:${IRONIC_TAG}"}
export IRONIC_CLIENT_IMAGE=${IRONIC_CLIENT_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ironic-client:main_20240124_4de85c1"}
export IRONIC_DATA_DIR="$WORKING_DIR/ironic"
export IRONIC_IMAGE_DIR="$IRONIC_DATA_DIR/html/images"
export IRONIC_NAMESPACE="${IRONIC_NAMESPACE:-baremetal-operator-system}"
export NAMEPREFIX="${NAMEPREFIX:-baremetal-operator}"

# iPXE vars of ironic-image
export BUILD_IPXE="${BUILD_IPXE:-false}"
export IPXE_ENABLE_TLS="${IPXE_ENABLE_TLS:-false}"
export IPXE_ENABLE_IPV6="${IPXE_ENABLE_IPV6:-false}"
export IPXE_RELEASE_BRANCH="${IPXE_RELEASE_BRANCH:-v1.21.1}"
export IPXE_SOURCE_FORCE_UPDATE="${IPXE_SOURCE_FORCE_UPDATE:-false}"
export IPXE_SOURCE_DIR="${IRONIC_DATA_DIR}/ipxe-source"

export IRONIC_KEEPALIVED_IMAGE="${IRONIC_KEEPALIVED_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/keepalived:${KEEPALIVED_TAG}}"
export MARIADB_IMAGE="${MARIADB_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/mariadb:${MARIADB_TAG}}"

# Enable ironic restart feature when the TLS certificate is updated
export RESTART_CONTAINER_CERTIFICATE_UPDATED="${RESTART_CONTAINER_CERTIFICATE_UPDATED:-${IRONIC_TLS_SETUP}}"

# Baremetal operator image
export BARE_METAL_OPERATOR_IMAGE="${BARE_METAL_OPERATOR_IMAGE:-${CONTAINER_REGISTRY}/metal3-io/baremetal-operator:${BARE_METAL_OPERATOR_TAG}}"

# Config for OpenStack CLI
export OPENSTACK_CONFIG="${HOME}/.config/openstack/clouds.yaml"

# Default hosts memory
export TARGET_NODE_MEMORY="${TARGET_NODE_MEMORY:-4096}"

# Cluster
export CLUSTER_NAME="${CLUSTER_NAME:-test1}"
export KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.30.0}"
export KUBERNETES_BINARIES_VERSION="${KUBERNETES_BINARIES_VERSION:-${KUBERNETES_VERSION}}"
export KUBERNETES_BINARIES_CONFIG_VERSION=${KUBERNETES_BINARIES_CONFIG_VERSION:-"v0.15.1"}

# Ephemeral Cluster
if [[ "${CONTAINER_RUNTIME}" = "docker" ]]; then
  export EPHEMERAL_CLUSTER=${EPHEMERAL_CLUSTER:-"kind"}
else
  export EPHEMERAL_CLUSTER="minikube"
fi

# Kubectl version (do not forget to update KUBECTL_SHA256 when changing KUBERNETES_VERSION!)
export KUBECTL_VERSION="${KUBECTL_VERSION:-${KUBERNETES_BINARIES_VERSION}}"
export KUBECTL_SHA256="${KUBECTL_SHA256:-7c3807c0f5c1b30110a2ff1e55da1d112a6d0096201f1beb81b269f582b5d1c5}"

# Krew version
export KREW_VERSION="${KREW_VERSION:-v0.4.3}"
export KREW_SHA256="${KREW_SHA256:-5df32eaa0e888a2566439c4ccb2ef3a3e6e89522f2f2126030171e2585585e4f}"

# Kustomize version
export KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-v5.4.1}"
export KUSTOMIZE_SHA256="${KUSTOMIZE_SHA256:-3d659a80398658d4fec4ec4ca184b432afa1d86451a60be63ca6e14311fc1c42}"

# Minikube version (if EPHEMERAL_CLUSTER=minikube)
export MINIKUBE_VERSION="${MINIKUBE_VERSION:-v1.33.0}"
export MINIKUBE_SHA256="${MINIKUBE_SHA256:-4bfdc17f0dce678432d5c02c2a681c7a72921cb72aa93ccc00c112070ec5d2bc}"
export MINIKUBE_DRIVER_SHA256="${MINIKUBE_DRIVER_SHA256:-83d3175eac710b1577209ddde5592c9071365bb281c6fc97ce5bd48106fc19ac}"

# Kind, kind node image versions (if EPHEMERAL_CLUSTER=kind)
export KIND_VERSION="${KIND_VERSION:-v0.22.0}"
export KIND_SHA256="${KIND_SHA256:-e4264d7ee07ca642fe52818d7c0ed188b193c214889dd055c929dbcb968d1f62}"

export KIND_NODE_IMAGE_VERSION="${KIND_NODE_IMAGE_VERSION:-v1.29.2}"
export KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-${DOCKER_HUB_PROXY}/kindest/node:${KIND_NODE_IMAGE_VERSION}}"

# Tilt
export TILT_VERSION="${TILT_VERSION:-v0.32.3}"
export TILT_SHA256="${TILT_SHA256:-b30ebbba68d4fd04f8afa11efc439515241dbcc2582eac2ced3e9fad09ce8318}"

# Ansible version
# Older ubuntu version do no support 7.0.0 because of older python versions
# Ansible 7.0.0 or newer requires python 3.10+
# TODO: Ansible pinning
if [[ "${DISTRO}" = "ubuntu22" ]]; then
    export ANSIBLE_VERSION="${ANSIBLE_VERSION:-8.0.0}"
else
    export ANSIBLE_VERSION="${ANSIBLE_VERSION:-6.7.0}"
fi

# Test and verification related variables
SKIP_RETRIES="${SKIP_RETRIES:-false}"
TEST_TIME_INTERVAL="${TEST_TIME_INTERVAL:-10}"
TEST_MAX_TIME="${TEST_MAX_TIME:-240}"
FAILS=0
RESULT_STR=""
BMO_ROLLOUT_WAIT="${BMO_ROLLOUT_WAIT:-5}"

# Avoid printing skipped Ansible tasks
export ANSIBLE_DISPLAY_SKIPPED_HOSTS="no"

# Sanity check for number of nodes
if [[ "${NUM_NODES}" -lt "$((CONTROL_PLANE_MACHINE_COUNT + WORKER_MACHINE_COUNT))" ]]; then
    echo "Failed with incorrect number of nodes"
    echo "NUM_NODES: ${NUM_NODES} < (${CONTROL_PLANE_MACHINE_COUNT} + ${WORKER_MACHINE_COUNT})"
    exit 1
fi

# Set default libvirt_domain_type to kvm
# Accepted values are kvm or qemu
export LIBVIRT_DOMAIN_TYPE="${LIBVIRT_DOMAIN_TYPE:-kvm}"

# Verify requisites/permissions
# Connect to system libvirt
export LIBVIRT_DEFAULT_URI=qemu:///system
if [[ "${USER}" != "root" ]] && [[ "${XDG_RUNTIME_DIR:-}" = "/run/user/0" ]] ; then
    echo "Please use a non-root user, WITH a login shell (e.g. su - USER)"
    exit 1
fi

# Check if sudo privileges without password
if ! sudo -n uptime &> /dev/null ; then
  echo "sudo without password is required"
  exit 1
fi

# Use firewalld on CentOS/RHEL, iptables everywhere else
export USE_FIREWALLD=false
if [[ "${DISTRO}" = "rhel"* ]] || [[ "${DISTRO}" = "centos"* ]]; then
  export USE_FIREWALLD=true
fi

# Check d_type support
FSTYPE="$(df "${FILESYSTEM}" --output=fstype | tail -n 1)"

case "${FSTYPE}" in
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
if [[ ! -d "${WORKING_DIR}" ]]; then
  echo "Creating Working Dir"
  sudo mkdir "${WORKING_DIR}"
  sudo chmod 755 "${WORKING_DIR}"
fi

# Ensure all files in the working directory are owned by the current user
sudo chown -R "${USER}:${USER}" "${WORKING_DIR}"

list_nodes() {
    # Includes -machine and -machine-namespace
    # shellcheck disable=SC2002
    cat "${NODES_FILE}" | \
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

  until [[ "${TMP_RET_CODE}" = 0 ]] || [[ "${SKIP_RETRIES}" = true ]]
  do
    if [[ "${RUNS}" = "0" ]]; then
      echo "   - Waiting for task completion (up to" \
        "$((TEST_TIME_INTERVAL*TEST_MAX_TIME)) seconds)" \
        " - Command: '${COMMAND}'"
    fi
    RUNS="$((RUNS+1))"
    if [[ "${RUNS}" = "${TEST_MAX_TIME}" ]]; then
      break
    fi
    sleep "${TEST_TIME_INTERVAL}"
    # shellcheck disable=SC2068
    TMP_RET="$(${COMMAND})"
    TMP_RET_CODE="$?"
  done
  FAILS="$((FAILS+TMP_RET_CODE))"
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
  if [[ "${1}" = 0 ]]; then
    echo "OK - ${RESULT_STR}"
    return 0
  else
    echo "FAIL - ${RESULT_STR}"
    FAILS="$((FAILS+1))"
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
  [[ "${1}" = "${2}" ]]; RET_CODE="$?"
  if ! process_status "${RET_CODE}" ; then
    echo "       expected ${2}, got ${1}"
  fi
  return ${RET_CODE}
}

#
# Compare the substring to the string and log
#
# Inputs:
# - Substring to look for
# - String to look for the substring in
#
is_in(){
  [[ "${2}" =~ .*(${1}).* ]]; RET_CODE="$?"
  if ! process_status "${RET_CODE}" ; then
    echo "       expected ${1} to be in ${2}"
  fi
  return ${RET_CODE}
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
  if ! process_status "${RET_CODE}" ; then
    echo "       expected to be different from ${2}, got ${1}"
  fi
  return ${RET_CODE}
}

#
# Kill and remove the infra containers
#
remove_ironic_containers() {
  #shellcheck disable=SC2015
  for name in ipa-downloader vbmc sushy-tools httpd-infra ipxe-builder; do
    if sudo "${CONTAINER_RUNTIME}" ps | grep -w -q "${name}$"; then
        sudo "${CONTAINER_RUNTIME}" kill "${name}" || true
    fi
    if sudo "${CONTAINER_RUNTIME}" ps --all | grep -w -q "${name}$"; then
        sudo "${CONTAINER_RUNTIME}" rm "${name}" -f || true
    fi
  done
}

#
# Manage libvirtd services based on OS
#
manage_libvirtd() {
  case ${DISTRO} in
      centos9|rhel9)
          for i in qemu network nodedev nwfilter secret storage interface; do
              sudo systemctl enable --now virt${i}d.socket
              sudo systemctl enable --now virt${i}d-ro.socket
              sudo systemctl enable --now virt${i}d-admin.socket
          done
          ;;
      *)
          sudo systemctl restart libvirtd.service
        ;;
esac
}
