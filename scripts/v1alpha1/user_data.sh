#!/bin/bash

SECRET_NAME_PREFIX=$1
OS_TYPE=${2:-unknown}

if [ -z "${SECRET_NAME_PREFIX}" ] || [ -z "${SSH_PUB_KEY}" ] ; then
    echo "Usage: user_data.sh <secret name prefix> [os type]"
    echo
    echo '    os type: "centos", or "unknown" (default)'
    echo
    echo 'Expected env vars:'
    echo '    SSH_PUB_KEY - path to ssh public key'
    exit 1
fi

#
# Our virtual bare metal environment is created with two networks: NIC 1)
# "provisioning" NIC 2) "baremetal"
#
# cloud-init based images will only bring up the first network interface by
# default.  We need it to bring up our second interface, as well.
#
# TODO(russellb) - It would be nice to make this more dynamic and also not
# platform specific.  cloud-init knows how to read a network_data.json file
# from config drive.  Maybe we could have the baremetal-operator automatically
# generate a network_data.json file that says to do DHCP on all interfaces that
# we know about from introspection.
#
network_config_files() {
    if [ "$OS_TYPE" = "centos" ] ; then
cat << EOF
write_files:
- path: /etc/sysconfig/network-scripts/ifcfg-eth1
  owner: root:root
  permissions: '0644'
  content: |
    BOOTPROTO=dhcp
    DEVICE=eth1
    ONBOOT=yes
    TYPE=Ethernet
    USERCTL=no
runcmd:
 - [ ifup, eth1 ]
EOF
    fi
}

user_data_secret() {
  {
    printf "#cloud-config\n\nssh_authorized_keys:\n  - "
    cat "${SSH_PUB_KEY}"
    printf "\n"
    network_config_files
  } > .userdata.tmp
cat << EOF
apiVersion: v1
data:
  userData: $(base64 -w 0 .userdata.tmp)
kind: Secret
metadata:
  name: ${SECRET_NAME_PREFIX}-user-data
  namespace: metal3
type: Opaque
EOF
rm .userdata.tmp
}

user_data_secret
