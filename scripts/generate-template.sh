#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/.."

export ACTION="generate_template"

"${METAL3_DIR}"/scripts/run.sh
