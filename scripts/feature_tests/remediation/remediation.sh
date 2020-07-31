#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

export ACTION="remediation"

"${METAL3_DIR}"/scripts/run.sh