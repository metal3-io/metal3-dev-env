#!/bin/bash
set -ex

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

export ACTION="ci_test_provision"
"${METAL3_DIR}"/tests/run.sh

# Manifest collection before pivot
"${METAL3_DIR}"/tests/scripts/fetch_manifests.sh
