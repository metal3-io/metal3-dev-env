#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DIR}/lib/common.sh"

make_v1alphaX_machine controlplane v1alpha3 | kubectl delete -n metal3 -f -
