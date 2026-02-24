#!/bin/bash
set -ex

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

export ACTION="verify"
"${METAL3_DIR}"/tests/run.sh
