#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="deprovision_cluster"

"${METAL3_DIR}"/tests/run.sh