#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

# shellcheck disable=SC1091
source "${M3PATH}/tests/feature_tests/feature_test_vars.sh"

pushd "${M3PATH}" || exit
make
