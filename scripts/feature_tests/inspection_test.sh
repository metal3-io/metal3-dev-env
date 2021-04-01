#!/bin/bash

set -x

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

export ACTION="inspection"

"${METAL3_DIR}"/scripts/run.sh