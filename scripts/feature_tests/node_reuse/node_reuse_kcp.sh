#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="node_reuse_kcp"

"${METAL3_DIR}"/scripts/run.sh