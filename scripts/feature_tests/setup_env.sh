#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

if [[ "${1}" == "ug" ]]; then

  # shellcheck disable=SC1091
  # shellcheck source="$M3PATH/scripts/feature_tests/upgrade_vars.sh"
  source "$M3PATH/scripts/feature_tests/upgrade_vars.sh"
fi
pushd "${M3PATH}" || exit
make
