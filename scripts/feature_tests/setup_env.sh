#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

if [[ "${1}" == "ug" ]]; then
  # shellcheck disable=SC1091
  # shellcheck source="$M3PATH/scripts/feature_tests/upgrade/upgrade_vars.sh"
  source "$M3PATH/scripts/feature_tests/upgrade/upgrade_vars.sh"
  # TODO: set CAPM3RELEASE and CAPIRELEASE
  # https://github.com/metal3-io/metal3-dev-env/issues/427 is fixed
  echo "setup_env, CAPM3RELEASE: ${CAPM3RELEASE}"
  echo "setup_env, CAPIRELEASE: ${CAPIRELEASE}"
fi
pushd "${M3PATH}" || exit
make
