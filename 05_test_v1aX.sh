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

RUN_CI_TEST=true
RUN_LOCAL_TEST_PROVISIONING=false
RUN_LOCAL_TEST_DEPROVISIONING=false

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "metal3_dir=$SCRIPTDIR" \
    -e "RUN_CI_TEST=$RUN_CI_TEST" \
    -e "RUN_LOCAL_TEST_PROVISIONING=$RUN_LOCAL_TEST_PROVISIONING" \
    -e "RUN_LOCAL_TEST_DEPROVISIONING=$RUN_LOCAL_TEST_DEPROVISIONING" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/v1aX_integration_test.yml \
