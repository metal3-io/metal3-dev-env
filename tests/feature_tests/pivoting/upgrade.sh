#!/bin/bash

export CONTROL_PLANE_MACHINE_COUNT=3
export WORKER_MACHINE_COUNT=1

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="upgrading"

"${METAL3_DIR}"/tests/run.sh
