#!/usr/bin/env bash

set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh

if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
     # Adding an IP address in the libvirt definition for this network results in
     # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
     # the IP address here.
     # Create a veth iterface peer.
     sudo ip link add ironicendpoint type veth peer name ironic-peer
     # Create provisioning bridge, if the user allowed bridged provisioning network.
     if [[ "${ENABLE_NATED_PROVISIONING_NETWORK:-false}" = "false" ]]; then
         sudo brctl addbr provisioning
     fi
     # sudo ifconfig provisioning 172.22.0.1 netmask 255.255.255.0 up
     # Use ip command. ifconfig commands are deprecated now.
     sudo ip link set provisioning up
     if [[ "${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY}" = "true" ]]; then
        sudo ip -6 addr add "${BARE_METAL_PROVISIONER_IP}"/"${BARE_METAL_PROVISIONER_CIDR}" dev ironicendpoint
      else
        sudo ip addr add dev ironicendpoint "${BARE_METAL_PROVISIONER_IP}"/"${BARE_METAL_PROVISIONER_CIDR}"
     fi
     sudo brctl addif provisioning ironic-peer
     sudo ip link set ironicendpoint up
     sudo ip link set ironic-peer up

     # Need to pass the provision interface for bare metal
     if [ "$PRO_IF" ]; then
       sudo brctl addif provisioning "$PRO_IF"
     fi
 fi

 if [ "${MANAGE_INT_BRIDGE}" == "y" ]; then
     # Create the external bridge
     if ! [[  $(ip a show external) ]]; then
       sudo brctl addbr external
       # sudo ifconfig external 192.168.111.1 netmask 255.255.255.0 up
       # Use ip command. ifconfig commands are deprecated now.
       if [[ -n "${EXTERNAL_SUBNET_V4_HOST}" ]]; then
         sudo ip addr add dev external "${EXTERNAL_SUBNET_V4_HOST}/${EXTERNAL_SUBNET_V4_PREFIX}"
       fi
       if [[ -n "${EXTERNAL_SUBNET_V6_HOST}" ]]; then
         sudo ip addr add dev external "${EXTERNAL_SUBNET_V6_HOST}/${EXTERNAL_SUBNET_V6_PREFIX}"
       fi
       sudo ip link set external up
     fi

     # Add the internal interface to it if requests, this may also be the interface providing
     # external access so we need to make sure we maintain dhcp config if its available
     if [ "${INT_IF}" ]; then
       sudo brctl addif "${INT_IF}"
     fi
 fi

 # restart the libvirt network so it applies an ip to the bridge
 if [ "${MANAGE_EXT_BRIDGE}" == "y" ] ; then
     sudo virsh net-destroy external
     sudo virsh net-start external
     if [ "${INT_IF}" ]; then #Need to bring UP the NIC after destroying the libvirt network
         sudo ifup "${INT_IF}"
     fi
 fi
