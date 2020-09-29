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

# Provisioning Interface
export CLUSTER_PROVISIONING_INTERFACE=${CLUSTER_PROVISIONING_INTERFACE:-"ironicendpoint"}

#POD CIDR
export POD_CIDR=${POD_CIDR:-"192.168.0.0/18"}

# Enables single-stack IPv6
PROVISIONING_IPV6=${PROVISIONING_IPV6:-false}
IPV6_ADDR_PREFIX=${IPV6_ADDR_PREFIX:-"fd2e:6f44:5dd8:b856"}

if [[ "${PROVISIONING_IPV6}" == "true" ]];
then
  export LIBVIRT_FIRMWARE=uefi
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-fd2e:6f44:5dd8:b856::/64}
else
  export LIBVIRT_FIRMWARE=bios
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-172.22.0.0/24}
fi

# shellcheck disable=SC2155
prefixlen PROVISIONING_CIDR "$PROVISIONING_NETWORK"
export PROVISIONING_CIDR
export PROVISIONING_NETMASK=${PROVISIONING_NETMASK:-$(python -c "import ipaddress; print(ipaddress.ip_network(u\"$PROVISIONING_NETWORK\").netmask)")}

network_address PROVISIONING_IP "$PROVISIONING_NETWORK" 1
network_address CLUSTER_PROVISIONING_IP "$PROVISIONING_NETWORK" 2

export PROVISIONING_IP
export CLUSTER_PROVISIONING_IP

# shellcheck disable=SC2153
if [[ "$PROVISIONING_IP" == *":"* ]]; then
  export PROVISIONING_URL_HOST="[$PROVISIONING_IP]"
  export CLUSTER_URL_HOST="[$CLUSTER_PROVISIONING_IP]"
else
  export PROVISIONING_URL_HOST="$PROVISIONING_IP"
  export CLUSTER_URL_HOST="$CLUSTER_PROVISIONING_IP"
fi

# shellcheck disable=SC2153
if [[ "$CLUSTER_APIENDPOINT_IP" == *":"* ]]; then
  export CLUSTER_APIENDPOINT_HOST="[$CLUSTER_APIENDPOINT_IP]"
else
  export CLUSTER_APIENDPOINT_HOST="$CLUSTER_APIENDPOINT_IP"
fi

# Calculate DHCP range
network_address dhcp_range_start "$PROVISIONING_NETWORK" 10
network_address dhcp_range_end "$PROVISIONING_NETWORK" 100
network_address PROVISIONING_POOL_RANGE_START "$PROVISIONING_NETWORK" 100
network_address PROVISIONING_POOL_RANGE_END "$PROVISIONING_NETWORK" 200

export PROVISIONING_POOL_RANGE_START
export PROVISIONING_POOL_RANGE_END
export CLUSTER_DHCP_RANGE=${CLUSTER_DHCP_RANGE:-"$dhcp_range_start,$dhcp_range_end"}

EXTERNAL_SUBNET=${EXTERNAL_SUBNET:-""}
if [[ -n "${EXTERNAL_SUBNET}" ]]; then
    echo "EXTERNAL_SUBNET has been removed in favor of EXTERNAL_SUBNET_V4 and EXTERNAL_NETWORK_V6."
    echo "Please update your configuration to drop the use of EXTERNAL_SUBNET."
    exit 1
fi

export IP_STACK=${IP_STACK:-"v4"}
if [[ "${IP_STACK}" == "v4" ]]; then
    export EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-"192.168.111.0/24"}
    export EXTERNAL_SUBNET_V6=""
elif [[ "${IP_STACK}" == "v6" ]]; then
    export EXTERNAL_SUBNET_V4=""
    export EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-"fd55::/64"}
elif [[ "${IP_STACK}" == "v4v6" ]]; then
    export EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-"192.168.111.0/24"}
    export EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-"fd55::/64"}
else
    echo "Invalid value of IP_STACK: '${IP_STACK}'"
    exit 1
fi

if [[ "${EPHEMERAL_CLUSTER}" == "minikube" ]] && [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
    network_address MINIKUBE_BMNET_V6_IP "${EXTERNAL_SUBNET_V6}" 9
fi


if [[ -n "${EXTERNAL_SUBNET_V4}" ]]; then
  prefixlen EXTERNAL_SUBNET_V4_PREFIX "$EXTERNAL_SUBNET_V4"
  export EXTERNAL_SUBNET_V4_PREFIX
  if [[ -z "${EXTERNAL_SUBNET_V4_HOST:-}" ]]; then
    network_address EXTERNAL_SUBNET_V4_HOST "$EXTERNAL_SUBNET_V4" 1
  fi

  # Calculate DHCP range for baremetal network (20 to 60 is the libvirt dhcp)
  network_address BAREMETALV4_POOL_RANGE_START "$EXTERNAL_SUBNET_V4" 100
  network_address BAREMETALV4_POOL_RANGE_END "$EXTERNAL_SUBNET_V4" 200
  export BAREMETALV4_POOL_RANGE_START
  export BAREMETALV4_POOL_RANGE_END
else
  export EXTERNAL_SUBNET_V4_PREFIX=""
  export EXTERNAL_SUBNET_V4_HOST=""
  export BAREMETALV4_POOL_RANGE_START=""
  export BAREMETALV4_POOL_RANGE_END=""
fi

if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
  prefixlen EXTERNAL_SUBNET_V6_PREFIX "$EXTERNAL_SUBNET_V6"
  export EXTERNAL_SUBNET_V6_PREFIX
  if [[ -z "${EXTERNAL_SUBNET_V6_HOST}" ]]; then
    network_address EXTERNAL_SUBNET_V6_HOST "$EXTERNAL_SUBNET_V6" 1
  fi

  # Calculate DHCP range for baremetal network (20 to 60 is the libvirt dhcp) IPv6
  network_address BAREMETALV6_POOL_RANGE_START "$EXTERNAL_SUBNET_V6" 100
  network_address BAREMETALV6_POOL_RANGE_END "$EXTERNAL_SUBNET_V6" 200
  export BAREMETALV6_POOL_RANGE_START
  export BAREMETALV6_POOL_RANGE_END
else
  export EXTERNAL_SUBNET_V6_HOST=""
  export EXTERNAL_SUBNET_V6_PREFIX=""
  export BAREMETALV6_POOL_RANGE_START=""
  export BAREMETALV6_POOL_RANGE_END=""
fi

export REGISTRY_PORT=${REGISTRY_PORT:-"5000"}

if [[ -n "${EXTERNAL_SUBNET_V4_HOST}" ]]; then
  export REGISTRY=${REGISTRY:-"${EXTERNAL_SUBNET_V4_HOST}:${REGISTRY_PORT}"}
else
  export REGISTRY=${REGISTRY:-"[${EXTERNAL_SUBNET_V6_HOST}]:${REGISTRY_PORT}"}
fi



network_address INITIAL_IRONICBRIDGE_IP "$PROVISIONING_NETWORK" 9

export DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL:-"http://${CLUSTER_URL_HOST}:6180/images/ironic-python-agent.kernel"}
export DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL:-"http://${CLUSTER_URL_HOST}:6180/images/ironic-python-agent.initramfs"}
export IRONIC_URL=${IRONIC_URL:-"http://${CLUSTER_URL_HOST}:6385/v1/"}
export IRONIC_INSPECTOR_URL=${IRONIC_INSPECTOR_URL:-"http://${CLUSTER_URL_HOST}:5050/v1/"}