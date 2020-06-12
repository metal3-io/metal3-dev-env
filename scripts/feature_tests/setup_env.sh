#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

pushd "${M3PATH}" || exit
make

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${M3PATH}/lib/common.sh"
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${M3PATH}/lib/network.sh"
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${M3PATH}/lib/images.sh"

