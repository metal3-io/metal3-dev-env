#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="repivoting"

"${METAL3_DIR}"/tests/run.sh
