#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."
RUN_CI_TEST=false
PROVISION_CLUSTER=false
PROVISION_CONTROLPLANE=false
PROVISION_WORKER=false
DEPROVISION_CONTROLPLANE=false
DEPROVISION_WORKER=true
DEPROVISION_CLUSTER=false

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
   -e "PROVISION_CLUSTER=$PROVISION_CLUSTER" \
   -e "PROVISION_CONTROLPLANE=$PROVISION_CONTROLPLANE" \
   -e "PROVISION_WORKER=$PROVISION_WORKER" \
   -e "DEPROVISION_CLUSTER=$DEPROVISION_CLUSTER" \
   -e "DEPROVISION_CONTROLPLANE=$DEPROVISION_CONTROLPLANE" \
   -e "DEPROVISION_WORKER=$DEPROVISION_WORKER" \
   -i "${METAL3_DIR}/vm-setup/inventory.ini" \
   -b -vvv "${METAL3_DIR}/vm-setup/v1aX_integration_test.yml"
