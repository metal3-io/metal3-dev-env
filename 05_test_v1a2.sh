#!/bin/bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

# Disable SSH trong authentication
export ANSIBLE_HOST_KEY_CHECKING=False

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "metal3_dir=$SCRIPTDIR" \
    -e "IMAGE_OS=$IMAGE_OS" \
    -e "DEFAULT_HOSTS_MEMORY=$DEFAULT_HOSTS_MEMORY" \
    -e "CAPI_VERSION=$CAPI_VERSION" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/v1a2_integration_test.yml
