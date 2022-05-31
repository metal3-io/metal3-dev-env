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
     #sudo ip link add ironicendpoint type veth peer name ironic-peer
     sudo nmcli  connection add type veth con-name ironicendpoint ifname ironicendpoint veth.peer ironic-peer 
     sudo nmcli  connection add type veth con-name ironic-peer ifname ironic-peer veth.peer ironicendpoint 

     # Create provisioning bridge.
     #sudo brctl addbr provisioning
     # sudo ifconfig provisioning 172.22.0.1 netmask 255.255.255.0 up
     # Use ip command. ifconfig commands are deprecated now.
     #sudo ip link set provisioning up
     sudo nmcli con add type bridge connection.id provisioning ifname provisioning ipv4.method disabled ipv6.method disabled
     sudo nmcli con up provisioning
     if [[ "${PROVISIONING_IPV6}" == "true" ]]; then
       # sudo ip -6 addr add "$PROVISIONING_IP"/"$PROVISIONING_CIDR" dev ironicendpoint
       sudo nmcli con modify ironicendpoint ipv6.method manual ipv6.addresses "$PROVISIONING_IP"/"$PROVISIONING_CIDR" ipv4.method ignore 
     else
       # sudo ip addr add dev ironicendpoint "$PROVISIONING_IP"/"$PROVISIONING_CIDR"
       sudo nmcli con modify ironicendpoint ipv4.method manual ipv4.addresses "$PROVISIONING_IP"/"$PROVISIONING_CIDR" ipv6.method ignore
     fi
     sudo nmcli con modify ironic-peer master provisioning slave-type bridge 
    #  sudo brctl addif provisioning ironic-peer
    #  sudo ip link set ironicendpoint up
    #  sudo ip link set ironic-peer up
     sudo nmcli con up ironicendpoint
     sudo nmcli con up ironic-peer

     # Need to pass the provision interface for bare metal
     if [ "$PRO_IF" ]; then
         sudo tee -a /etc/NetworkManager/system-connections/"$PRO_IF".nmconnection <<EOF
[connection]
id=$PRO_IF
type=ethernet
interface-name=$PRO_IF
master=provisioning
slave-type=bridge
EOF
         sudo chmod 600 /etc/NetworkManager/system-connections/"$PRO_IF".nmconnection
         sudo nmcli con load /etc/NetworkManager/system-connections/"$PRO_IF".nmconnection
         sudo nmcli con up "$PRO_IF"
     fi
fi

if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
    #  # Create the baremetal bridge
    #  if ! [[  $(ip a show baremetal) ]]; then
    #    sudo brctl addbr baremetal
    #    # sudo ifconfig baremetal 192.168.111.1 netmask 255.255.255.0 up
    #    # Use ip command. ifconfig commands are deprecated now.
    #    if [[ -n "${EXTERNAL_SUBNET_V4_HOST}" ]]; then
    #      sudo ip addr add dev baremetal "${EXTERNAL_SUBNET_V4_HOST}/${EXTERNAL_SUBNET_V4_PREFIX}"
    #    fi
    #    if [[ -n "${EXTERNAL_SUBNET_V6_HOST}" ]]; then
    #      sudo ip addr add dev baremetal "${EXTERNAL_SUBNET_V6_HOST}/${EXTERNAL_SUBNET_V6_PREFIX}"
    #    fi
    #    sudo ip link set baremetal up
    #  fi
    if ! [[  $(ip a show baremetal) ]]; then
      if [[ "${EXTERNAL_SUBNET_V6_HOST}" == "true" ]]; then
          sudo tee /etc/NetworkManager/system-connections/baremetal.nmconnection <<EOF
[connection]
id=baremetal
type=bridge
interface-name=baremetal
autoconnect=true

[bridge]
stp=false

[ipv4]
method=disabled

[ipv6]
addr-gen-mode=eui64
address1=${EXTERNAL_SUBNET_V6_HOST}/${EXTERNAL_SUBNET_V6_PREFIX}
method=manual
EOF       
      fi
      if [[ "${EXTERNAL_SUBNET_V4_HOST}" == "true" ]]; then
          sudo tee /etc/NetworkManager/system-connections/baremetal.nmconnection <<EOF
[connection]
id=baremetal
type=bridge
interface-name=baremetal
autoconnect=true

[bridge]
stp=false

[ipv4]
address1=${EXTERNAL_SUBNET_V4_HOST}/${EXTERNAL_SUBNET_V4_PREFIX}
method=manual

[ipv6]
addr-gen-mode=stable-privacy
method=ignore
EOF
      fi
      sudo chmod 600 /etc/NetworkManager/system-connections/baremetal.nmconnection
      sudo nmcli con load /etc/NetworkManager/system-connections/baremetal.nmconnection
    fi
    sudo nmcli connection up baremetal
     # Add the internal interface to it if requests, this may also be the interface providing
     # external access so we need to make sure we maintain dhcp config if its available
    if [ "$INT_IF" ]; then
     #  sudo brctl addif "$INT_IF"
          echo -e "[connection]\nid=$INT_IF\ntype=ethernet\ninterface-name=$INT_IF\nmaster=provisioning\nslave-type=bridge\n\n[ethernet]\n\n[bridge-port]" | sudo dd of=/etc/NetworkManager/system-connections/"$INT_IF".nmconnection
          sudo chmod 600 /etc/NetworkManager/system-connections/"$INT_IF".nmconnection
          sudo nmcli con load /etc/NetworkManager/system-connections/"$INT_IF".nmconnection
          if sudo nmap --script broadcast-dhcp-discover -e "$INT_IF" | grep "IP Offered" ; then
              sudo nmcli connection modify baremetal ipv4.method auto
          fi
          sudo nmcli connection up "$INT_IF"
    fi
fi

 # restart the libvirt network so it applies an ip to the bridge
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
     sudo virsh net-destroy baremetal
     sudo virsh net-start baremetal
     if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
         sudo nmcli connection up "$INT_IF"
     fi
fi
