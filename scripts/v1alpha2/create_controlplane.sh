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

make_v1alpha2_machine controlplane | kubectl apply -n metal3 -f -
