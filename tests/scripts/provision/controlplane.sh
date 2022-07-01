#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."

export ACTION="provision_controlplane"

"${METAL3_DIR}"/tests/run.sh