#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

if [[ "${1}" == "ug" ]]; then
  # shellcheck disable=SC1091
  source "${M3PATH}/tests/feature_tests/upgrade/upgrade_vars.sh"
else
  # shellcheck disable=SC1091
  source "${M3PATH}/tests/feature_tests/feature_test_vars.sh"
fi

pushd "${M3PATH}" || exit
make
