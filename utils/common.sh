#!/bin/bash

eval "$(go env)"

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
USER=`whoami`

# Get variables from the config file
if [ -z "${CONFIG:-}" ]; then
    # See if there's a config_$USER.sh in the SCRIPTDIR
    if [ -f ${SCRIPTDIR}/../config_${USER}.sh ]; then
        echo "Using CONFIG ${SCRIPTDIR}/../config_${USER}.sh"
        CONFIG="${SCRIPTDIR}/../config_${USER}.sh"
    else
        echo "Please run with a configuration environment set."
        echo "eg CONFIG=config_example.sh ./01_all_in_one.sh"
        exit 1
    fi
fi
source $CONFIG

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

FILESYSTEM=${FILESYSTEM:="/"}

WORKING_DIR=${WORKING_DIR:-"/opt/metal3-dev-env"}
NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}

export NUM_MASTERS=${NUM_MASTERS:-"3"}
export NUM_WORKERS=${NUM_WORKERS:-"1"}
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}

# Ironic vars
export IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metal3-io/ironic"}
export IRONIC_INSPECTOR_IMAGE=${IRONIC_INSPECTOR_IMAGE:-"quay.io/metal3-io/ironic-inspector"}
export IRONIC_DATA_DIR="$WORKING_DIR/ironic"

# Verify requisites/permissions
# Connect to system libvirt
export LIBVIRT_DEFAULT_URI=qemu:///system
if [ "$USER" != "root" -a "${XDG_RUNTIME_DIR:-}" == "/run/user/0" ] ; then
    echo "Please use a non-root user, WITH a login shell (e.g. su - USER)"
    exit 1
fi

# Check if sudo privileges without password
if ! sudo -n uptime &> /dev/null ; then
  echo "sudo without password is required"
  exit 1
fi

# Check OS
if [[ ! $(awk -F= '/^ID=/ { print $2 }' /etc/os-release | tr -d '"') =~ ^(centos|rhel)$ ]]; then
  echo "Unsupported OS"
  exit 1
fi

# Check CentOS version
if [[ $(awk -F= '/^VERSION_ID=/ { print $2 }' /etc/os-release | tr -d '"' | cut -f1 -d'.') -ne 7 ]]; then
  echo "Required CentOS 7 or RHEL 7"
  exit 1
fi

# Check d_type support
FSTYPE=$(df ${FILESYSTEM} --output=fstype | grep -v Type)

case ${FSTYPE} in
  'ext4'|'btrfs')
  ;;
  'xfs')
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
