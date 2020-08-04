#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

if [[ "${1}" == "ug" ]]; then
  export CAPM3RELEASE="v0.3.2"
  export CAPIRELEASE="v0.3.4"
fi
pushd "${M3PATH}" || exit
make
