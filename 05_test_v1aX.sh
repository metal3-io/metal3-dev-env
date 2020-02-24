#!/bin/bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh
# shellcheck disable=SC1091
source lib/images.sh

# Disable SSH strong authentication
export ANSIBLE_HOST_KEY_CHECKING=False

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "metal3_dir=$SCRIPTDIR" \
    -e "v1aX_integration_test_action=ci_test" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/v1aX_integration_test.yml
