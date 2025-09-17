#!/bin/bash
set -ex

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

export ACTION="ci_test_deprovision"
"${METAL3_DIR}"/tests/run.sh
