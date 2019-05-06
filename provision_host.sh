#!/bin/bash

source utils/common.sh

BMHOST=$1
IMAGE_NAME=${2:-CentOS-7-x86_64-GenericCloud-1901.qcow2}
IMAGE_URL=http://172.22.0.1/images/${IMAGE_NAME}
IMAGE_CHECKSUM=http://172.22.0.1/images/${IMAGE_NAME}.md5sum

if [ -z "${BMHOST}" ] ; then
    echo "Usage: provision_host.sh <BareMetalHost-name> [image-name]"
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
    if echo ${IMAGE_NAME} | grep -qi centos 2>/dev/null ; then
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
    printf "#cloud-config\n\nssh_authorized_keys:\n  - " > .userdata.tmp
    cat ${SSH_PUB_KEY} >> .userdata.tmp
    printf "\n" >> .userdata.tmp
    network_config_files >> .userdata.tmp
cat << EOF
apiVersion: v1
data:
  userData: $(base64 -w 0 .userdata.tmp)
kind: Secret
metadata:
  name: ${BMHOST}-user-data
  namespace: metal3
type: Opaque
EOF
rm .userdata.tmp
}
user_data_secret | kubectl apply -n metal3 -f -

kubectl patch baremetalhost ${BMHOST} -n metal3 --type merge \
    -p '{"spec":{"image":{"url":"'${IMAGE_URL}'","checksum":"'${IMAGE_CHECKSUM}'"},"userData":{"name":"'${BMHOST}'-user-data","namespace":"metal3"}}}'
