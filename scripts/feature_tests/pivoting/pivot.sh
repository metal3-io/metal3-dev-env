#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="post_pivot"

"${METAL3_DIR}"/scripts/run.sh
