#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

if [[ "${1}" == "ug" ]]; then
  # shellcheck disable=SC1091
  # shellcheck source="$M3PATH/scripts/feature_tests/upgrade/upgrade_vars.sh"
  source "${M3PATH}/scripts/feature_tests/upgrade/upgrade_vars.sh"
fi
if [[ "${1}" == "no-tls" ]]; then
  export IRONIC_BASIC_AUTH="false"
  export IRONIC_TLS_SETUP="false"
  export NODE_DRAIN_TIMEOUT="300s"
fi
pushd "${M3PATH}" || exit
make
