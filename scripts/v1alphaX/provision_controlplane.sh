#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

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
   -e "v1aX_integration_test_action=provision_controlplane" \
   -i "${METAL3_DIR}/vm-setup/inventory.ini" \
   -b -vvv "${METAL3_DIR}/vm-setup/v1aX_integration_test.yml"
