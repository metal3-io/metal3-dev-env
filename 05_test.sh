#!/bin/bash
set -xe

METAL3_DIR="$(dirname "$(readlink -f "${0}")")"

export ACTION="ci-test"

"${METAL3_DIR}"/scripts/run.sh
