#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."


# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "upgrade_vars.sh"

export ACTION="upgrading"

"${METAL3_DIR}"/scripts/run.sh
