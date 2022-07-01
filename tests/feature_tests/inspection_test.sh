#!/bin/bash

set -x

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

# shellcheck disable=SC1091
# shellcheck disable=SC1090
# shellcheck disable=SC2046
source "${METAL3_DIR}/tests/feature_tests/feature_test_vars.sh"

export ACTION="inspection"

"${METAL3_DIR}"/tests/run.sh
