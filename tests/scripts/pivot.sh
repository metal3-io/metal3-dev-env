#!/bin/bash
set -ex

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

export ACTION="pivoting"
"${METAL3_DIR}"/tests/run.sh

# Log and Manifest collection after pivot
"${METAL3_DIR}"/tests/scripts/fetch_target_logs.sh
"${METAL3_DIR}"/tests/scripts/fetch_manifests.sh
