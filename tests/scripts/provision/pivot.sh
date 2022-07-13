#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="pivoting"

"${METAL3_DIR}"/tests/run.sh