#!/bin/bash

#
# This is the subnet used on the "baremetal" libvirt network, created as the
# primary network interface for the virtual bare metalhosts.
#
# Default of 192.168.111.0/24 set in utils/common.sh
#
#export EXTERNAL_SUBNET="192.168.111.0/24"

#
# This SSH key will be automatically injected into the provisioned host
# by the provision_host.sh script.
#
# Default of ~/.ssh/id_rsa.pub is set in utils/common.sh
#
#export SSH_PUB_KEY=~/.ssh/id_rsa.pub
