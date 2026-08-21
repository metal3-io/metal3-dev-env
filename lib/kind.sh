#!/bin/bash

#
# Connect the kind cluster node to the provisioning network.
# Required when Ironic is deployed in-cluster (IRONIC_DEPLOY_IN_CLUSTER=true)
# because the Ironic pod uses hostNetwork: true and needs direct access to
# the provisioning bridge to serve DHCP/PXE to the baremetal VMs.
#
connect_kind_to_provisioning_network()
{
    local container_name="kind-control-plane"
    local bridge="provisioning"
    local iface="${BARE_METAL_PROVISIONER_INTERFACE}"
    local ip_with_cidr="${CLUSTER_BARE_METAL_PROVISIONER_IP}/${BARE_METAL_PROVISIONER_CIDR}"

    echo "Connecting kind node to provisioning network"

    # Create a veth pair: one end goes into the provisioning bridge,
    # the other goes into the kind container with the expected interface name.
    sudo ip link add kind-prov-peer type veth peer name kind-prov
    sudo ip link set kind-prov master "${bridge}"
    sudo ip link set kind-prov up

    # Move the peer end into the kind container's network namespace
    local kind_pid
    kind_pid=$(sudo "${CONTAINER_RUNTIME}" inspect -f '{{.State.Pid}}' "${container_name}")
    sudo ip link set kind-prov-peer netns "${kind_pid}"

    # Rename and configure the interface inside the kind container
    # Use the same name as BARE_METAL_PROVISIONER_INTERFACE so Ironic's
    # configmap PROVISIONING_INTERFACE value matches.
    sudo nsenter -t "${kind_pid}" -n ip link set kind-prov-peer name "${iface}"
    sudo nsenter -t "${kind_pid}" -n ip addr add "${ip_with_cidr}" dev "${iface}"
    sudo nsenter -t "${kind_pid}" -n ip link set "${iface}" up

    echo "Kind node connected to provisioning network with ${ip_with_cidr} on ${iface}"
}
