#!/usr/bin/env bash

set -eu

selinux="#security_driver = \"selinux\""
apparmor="security_driver = \"apparmor\""
none="security_driver = \"none\""
sudo sed -i \
    -e "s/${selinux}/${none}/g" \
    -e "s/${apparmor}/${none}/g" \
    /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd
