#!/bin/bash

export NUM_OF_CONTROLPLANE_REPLICAS=3
export NUM_OF_WORKER_REPLICAS=1

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="upgrading"

"${METAL3_DIR}"/scripts/run.sh
