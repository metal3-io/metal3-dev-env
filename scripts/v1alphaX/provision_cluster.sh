#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."
RUN_CI_TEST=false
RUN_LOCAL_TEST_PROVISIONING=true
RUN_LOCAL_TEST_DEPROVISIONING=false

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DIR}/lib/common.sh"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DIR}/lib/network.sh"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DIR}/lib/images.sh"

ANSIBLE_FORCE_COLOR=true ansible-playbook \
   -e "metal3_dir=$SCRIPTDIR" \
   -e "RUN_CI_TEST=$RUN_CI_TEST" \
   -e "RUN_LOCAL_TEST_PROVISIONING=$RUN_LOCAL_TEST_PROVISIONING" \
   -e "RUN_LOCAL_TEST_DEPROVISIONING=$RUN_LOCAL_TEST_DEPROVISIONING" \
   -i "${METAL3_DIR}/vm-setup/inventory.ini" \
   -b -vvv "${METAL3_DIR}/vm-setup/v1aX_integration_test.yml" \
