#!/usr/bin/env bash
set -x

source utils/logging.sh
source utils/common.sh

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -e @vm-setup/config/environments/dev_privileged_libvirt.yml \
    -i vm-setup/tripleo-quickstart-config/metalkube-inventory.ini \
    -b -vvv vm-setup/tripleo-quickstart-config/metalkube-teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/conf.d/dnsmasq.conf
# There was a bug in this file, it may need to be recreated.
if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-provisioning
fi
# Leaving this around causes issues when the host is rebooted
if [ "$MANAGE_BR_BRIDGE" == "y" ]; then
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-baremetal
fi
sudo virsh net-list --name|grep -q baremetal
if [ "$?" == "0" ]; then
    sudo virsh net-destroy baremetal
    sudo virsh net-undefine baremetal
fi
sudo virsh net-list --name|grep -q provisioning
if [ "$?" == "0" ]; then
     sudo virsh net-destroy provisioning
     sudo virsh net-undefine provisioning
fi
