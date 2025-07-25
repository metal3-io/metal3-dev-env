#!/bin/bash

#
# Get the nth address from an IPv4 or IPv6 Network
#
# Inputs:
#    - Which variable to write the result into
#    - Network CIDR (e.g. 172.22.0.0/24)
#    - Which address (e.g. first, second, etc)

function network_address() {
  resultvar=$1
  network=$2
  record=$3

  result=$(python -c "import ipaddress; import itertools; print(next(itertools.islice(ipaddress.ip_network(u\"$network\").hosts(), $record - 1, None)))")
  eval "$resultvar"="$result"
  export "${resultvar?}"
}

# Get the prefix length from a network in CIDR notation.
# Usage: prefixlen <variable to write to> <network>
function prefixlen() {
  resultvar=$1
  network=$2

  result=$(python -c "import ipaddress; print(ipaddress.ip_network(u\"$network\").prefixlen)")
  eval "$resultvar"="$result"
  export "${resultvar?}"
}

# Option to enable or disable fully NATed network topology
export ENABLE_NATED_PROVISIONING_NETWORK="${ENABLE_NATED_PROVISIONING_NETWORK:-false}"

# Provisioning Interface
export BARE_METAL_PROVISIONER_INTERFACE="${BARE_METAL_PROVISIONER_INTERFACE:-ironicendpoint}"

# POD CIDR
export POD_CIDR=${POD_CIDR:-"192.168.0.0/18"}

# Enables single-stack IPv6
BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY=${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY:-false}

if [[ "${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY}" == "true" ]]; then
  # IPV6 only works with UEFI boot mode
  export BOOT_MODE=UEFI
  export BARE_METAL_PROVISIONER_NETWORK="${BARE_METAL_PROVISIONER_NETWORK:-fd2e:6f44:5dd8:b856::/64}"
else
  export BARE_METAL_PROVISIONER_NETWORK="${BARE_METAL_PROVISIONER_NETWORK:-172.22.0.0/24}"
fi

if [[ "${BOOT_MODE}" == "legacy" ]]; then
  export LIBVIRT_FIRMWARE="bios"
  export LIBVIRT_SECURE_BOOT="false"
elif [[ "${BOOT_MODE}" == "UEFI" ]]; then
  export LIBVIRT_FIRMWARE="uefi"
  export LIBVIRT_SECURE_BOOT="false"
elif [[ "${BOOT_MODE}" == "UEFISecureBoot" ]]; then
  export LIBVIRT_FIRMWARE="uefi"
  export LIBVIRT_SECURE_BOOT="true"
fi

# shellcheck disable=SC2155
prefixlen BARE_METAL_PROVISIONER_CIDR "$BARE_METAL_PROVISIONER_NETWORK"
export BARE_METAL_PROVISIONER_CIDR
export BARE_METAL_PROVISIONER_NETMASK=${BARE_METAL_PROVISIONER_NETMASK:-$(python -c "import ipaddress; print(ipaddress.ip_network(u\"$BARE_METAL_PROVISIONER_NETWORK\").netmask)")}

network_address BARE_METAL_PROVISIONER_IP "${BARE_METAL_PROVISIONER_NETWORK}" 1
network_address CLUSTER_BARE_METAL_PROVISIONER_IP "${BARE_METAL_PROVISIONER_NETWORK}" 2

export BARE_METAL_PROVISIONER_IP
export CLUSTER_BARE_METAL_PROVISIONER_IP
# These are inherited into ironic deployment in BMO, so we need to have duplicates
export PROVISIONING_IP=${BARE_METAL_PROVISIONER_IP}
export CLUSTER_PROVISIONING_IP=${CLUSTER_BARE_METAL_PROVISIONER_IP}

# shellcheck disable=SC2153
if [[ "$BARE_METAL_PROVISIONER_IP" = *":"* ]]; then
  export BARE_METAL_PROVISIONER_URL_HOST="[${BARE_METAL_PROVISIONER_IP}]"
  export CLUSTER_BARE_METAL_PROVISIONER_HOST="[${CLUSTER_BARE_METAL_PROVISIONER_IP}]"
else
  export BARE_METAL_PROVISIONER_URL_HOST="${BARE_METAL_PROVISIONER_IP}"
  export CLUSTER_BARE_METAL_PROVISIONER_HOST="${CLUSTER_BARE_METAL_PROVISIONER_IP}"
fi

# Calculate DHCP range
network_address CLUSTER_DHCP_RANGE_START "$BARE_METAL_PROVISIONER_NETWORK" 10
network_address CLUSTER_DHCP_RANGE_END "$BARE_METAL_PROVISIONER_NETWORK" 100
# The nex range is for IPAM to know what is the pool that porovisioned noodes
# can get IP's from
network_address IPAM_PROVISIONING_POOL_RANGE_START "$BARE_METAL_PROVISIONER_NETWORK" 100
network_address IPAM_PROVISIONING_POOL_RANGE_END "$BARE_METAL_PROVISIONER_NETWORK" 200

export IPAM_PROVISIONING_POOL_RANGE_START
export IPAM_PROVISIONING_POOL_RANGE_END
export CLUSTER_DHCP_RANGE=${CLUSTER_DHCP_RANGE:-"$CLUSTER_DHCP_RANGE_START,$CLUSTER_DHCP_RANGE_END"}

EXTERNAL_SUBNET=${EXTERNAL_SUBNET:-""}
if [[ -n "${EXTERNAL_SUBNET}" ]]; then
    echo "EXTERNAL_SUBNET has been removed in favor of EXTERNAL_SUBNET_V4 and EXTERNAL_SUBNET_V6."
    echo "Please update your configuration to drop the use of EXTERNAL_SUBNET."
    exit 1
fi

export IP_STACK=${IP_STACK:-"v4"}
if [[ "${IP_STACK}" == "v4" ]]; then
    export EXTERNAL_SUBNET_V4="${EXTERNAL_SUBNET_V4:-192.168.111.0/24}"
    export EXTERNAL_SUBNET_V6=""
    export PROVISIONING_SUBNET_V4="${PROVISIONING_SUBNET_V4:-172.23.23.0/24}"
    export PROVISIONING_SUBNET_V6=""
elif [[ "${IP_STACK}" == "v6" ]]; then
    export EXTERNAL_SUBNET_V4=""
    export EXTERNAL_SUBNET_V6="${EXTERNAL_SUBNET_V6:-fd55::/64}"
    export PROVISIONING_SUBNET_V4=""
    export PROVISIONING_SUBNET_V6="${PROVISIONING_SUBNET_V6:-fd56::/64}"
elif [[ "${IP_STACK}" == "v4v6" ]]; then
    export EXTERNAL_SUBNET_V4="${EXTERNAL_SUBNET_V4:-192.168.111.0/24}"
    export EXTERNAL_SUBNET_V6="${EXTERNAL_SUBNET_V6:-fd55::/64}"
    export PROVISIONING_SUBNET_V4="${PROVISIONING_SUBNET_V4:-172.23.23.0/24}"
    export PROVISIONING_SUBNET_V6="${PROVISIONING_SUBNET_V6:-fd56::/64}"
else
    echo "Invalid value of IP_STACK: '${IP_STACK}'"
    exit 1
fi

if [[ -n "${CLUSTER_APIENDPOINT_IP:-}" ]]; then
  # Accept user provided value if set
  export CLUSTER_APIENDPOINT_IP
elif [[ -n "${EXTERNAL_SUBNET_V4}" ]]; then
  network_address CLUSTER_APIENDPOINT_IP "${EXTERNAL_SUBNET_V4}" 249
else
  network_address CLUSTER_APIENDPOINT_IP "${EXTERNAL_SUBNET_V6}" 249
fi

# shellcheck disable=SC2153
if [[ "${CLUSTER_APIENDPOINT_IP}" == *":"* ]]; then
  export CLUSTER_APIENDPOINT_HOST="[${CLUSTER_APIENDPOINT_IP}]"
else
  export CLUSTER_APIENDPOINT_HOST="${CLUSTER_APIENDPOINT_IP}"
fi
export CLUSTER_APIENDPOINT_PORT=${CLUSTER_APIENDPOINT_PORT:-"6443"}

if [[ "${EPHEMERAL_CLUSTER}" == "minikube" ]] && [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
    network_address MINIKUBE_BMNET_V6_IP "${EXTERNAL_SUBNET_V6}" 9
fi

if [[ -n "${PROVISIONING_SUBNET_V4}" ]]; then
    network_address PROVISIONING_DHCP_V4_START "${PROVISIONING_SUBNET_V4}" 1
    network_address PROVISIONING_DHCP_V4_END "${PROVISIONING_SUBNET_V4}" 99
fi

if [[ -n "${EXTERNAL_SUBNET_V4}" ]]; then
  prefixlen EXTERNAL_SUBNET_V4_PREFIX "$EXTERNAL_SUBNET_V4"
  export EXTERNAL_SUBNET_V4_PREFIX
  if [[ -z "${EXTERNAL_SUBNET_V4_HOST:-}" ]]; then
    network_address EXTERNAL_SUBNET_V4_HOST "$EXTERNAL_SUBNET_V4" 1
  fi

  # Calculate DHCP range for baremetal network (20 to 60 is the libvirt dhcp)
  network_address EXTERNAL_DHCP_V4_START "$EXTERNAL_SUBNET_V4" 20
  network_address EXTERNAL_DHCP_V4_END "$EXTERNAL_SUBNET_V4" 60
  network_address IPAM_EXTERNALV4_POOL_RANGE_START "$EXTERNAL_SUBNET_V4" 100
  network_address IPAM_EXTERNALV4_POOL_RANGE_END "$EXTERNAL_SUBNET_V4" 200
  export EXTERNAL_DHCP_V4_START
  export EXTERNAL_DHCP_V4_END
  export IPAM_EXTERNALV4_POOL_RANGE_START
  export IPAM_EXTERNALV4_POOL_RANGE_END
else
  export EXTERNAL_SUBNET_V4_PREFIX=""
  export EXTERNAL_SUBNET_V4_HOST=""
  export IPAM_EXTERNALV4_POOL_RANGE_START=""
  export IPAM_EXTERNALV4_POOL_RANGE_END=""
fi

if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
  prefixlen EXTERNAL_SUBNET_V6_PREFIX "$EXTERNAL_SUBNET_V6"
  export EXTERNAL_SUBNET_V6_PREFIX
  if [[ -z "${EXTERNAL_SUBNET_V6_HOST:-}" ]]; then
    network_address EXTERNAL_SUBNET_V6_HOST "$EXTERNAL_SUBNET_V6" 1
  fi

  # Calculate DHCP range for baremetal network (20 to 60 is the libvirt dhcp) IPv6
  network_address EXTERNAL_DHCP_V6_START "$EXTERNAL_SUBNET_V6" 20
  network_address EXTERNAL_DHCP_V6_END "$EXTERNAL_SUBNET_V6" 60
  network_address IPAM_EXTERNALV6_POOL_RANGE_START "$EXTERNAL_SUBNET_V6" 100
  network_address IPAM_EXTERNALV6_POOL_RANGE_END "$EXTERNAL_SUBNET_V6" 200
  export EXTERNAL_DHCP_V6_START
  export EXTERNAL_DHCP_V6_END
  export IPAM_EXTERNALV6_POOL_RANGE_START
  export IPAM_EXTERNALV6_POOL_RANGE_END
else
  export EXTERNAL_SUBNET_V6_HOST=""
  export EXTERNAL_SUBNET_V6_PREFIX=""
  export IPAM_EXTERNALV6_POOL_RANGE_START=""
  export IPAM_EXTERNALV6_POOL_RANGE_END=""
fi

# Ports
export REGISTRY_PORT="${REGISTRY_PORT:-5000}"
export HTTP_PORT="${HTTP_PORT:-6180}"
export IRONIC_INSPECTOR_PORT="${IRONIC_INSPECTOR_PORT:-5050}"
export IRONIC_API_PORT="${IRONIC_API_PORT:-6385}"

if [[ -n "${EXTERNAL_SUBNET_V4_HOST}" ]]; then
  export REGISTRY="${REGISTRY:-${EXTERNAL_SUBNET_V4_HOST}:${REGISTRY_PORT}}"
else
  export REGISTRY="${REGISTRY:-[${EXTERNAL_SUBNET_V6_HOST}]:${REGISTRY_PORT}}"
fi

network_address INITIAL_BARE_METAL_PROVISIONER_BRIDGE_IP "$BARE_METAL_PROVISIONER_NETWORK" 9

export DEPLOY_KERNEL_URL="${DEPLOY_KERNEL_URL:-http://${CLUSTER_BARE_METAL_PROVISIONER_HOST}:${HTTP_PORT}/images/ironic-python-agent.kernel}"
export DEPLOY_RAMDISK_URL="${DEPLOY_RAMDISK_URL:-http://${CLUSTER_BARE_METAL_PROVISIONER_HOST}:${HTTP_PORT}/images/ironic-python-agent.initramfs}"
export DEPLOY_ISO_URL=${DEPLOY_ISO_URL:-}

if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
  export IRONIC_URL="${IRONIC_URL:-https://${CLUSTER_BARE_METAL_PROVISIONER_HOST}:${IRONIC_API_PORT}/v1/}"
  export IRONIC_INSPECTOR_URL="${IRONIC_INSPECTOR_URL:-https://${CLUSTER_BARE_METAL_PROVISIONER_HOST}:${IRONIC_INSPECTOR_PORT}/v1/}"
else
  export IRONIC_URL="${IRONIC_URL:-http://${CLUSTER_BARE_METAL_PROVISIONER_HOST}:${IRONIC_API_PORT}/v1/}"
  export IRONIC_INSPECTOR_URL="${IRONIC_INSPECTOR_URL:-http://${CLUSTER_BARE_METAL_PROVISIONER_HOST}:${IRONIC_INSPECTOR_PORT}/v1/}"
fi
