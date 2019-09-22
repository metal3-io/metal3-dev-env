#!/usr/bin/env bash

set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
     # Adding an IP address in the libvirt definition for this network results in
     # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
     # the IP address here
     sudo brctl addbr provisioning
     # sudo ifconfig provisioning 172.22.0.1 netmask 255.255.255.0 up
     # Use ip command. ifconfig commands are deprecated now.
     sudo ip addr add dev provisioning 172.22.0.1/24
     sudo ip link set provisioning up

     # Need to pass the provision interface for bare metal
     if [ "$PRO_IF" ]; then
       sudo brctl addif provisioning "$PRO_IF"
     fi
 fi

 if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
     # Create the baremetal bridge
     if ! [[  $(ip a show baremetal) ]]; then
       sudo brctl addbr baremetal
       # sudo ifconfig baremetal 192.168.111.1 netmask 255.255.255.0 up
       # Use ip command. ifconfig commands are deprecated now.
       sudo ip addr add dev baremetal 192.168.111.1/24
       sudo ip link set baremetal up
     fi

     # Add the internal interface to it if requests, this may also be the interface providing
     # external access so we need to make sure we maintain dhcp config if its available
     if [ "$INT_IF" ]; then
       sudo brctl addif "$INT_IF"
     fi
 fi

 # restart the libvirt network so it applies an ip to the bridge
 if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
     sudo virsh net-destroy baremetal
     sudo virsh net-start baremetal
     if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
         sudo ip link set "$INT_IF" up
     fi
 fi
