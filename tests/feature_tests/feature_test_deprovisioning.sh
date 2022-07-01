#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

export ACTION="feature_test_deprovisioning"

"${METAL3_DIR}"/tests/run.sh
