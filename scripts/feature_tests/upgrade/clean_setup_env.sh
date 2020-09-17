#!/bin/bash

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../"

# Deploy a fresh metal3-dev-env after each test case
# to overcome environmental flakiness
pushd "${METAL3_DEV_ENV_DIR}" || exit
make clean
make setup_env
rc=$?
if [ "${rc}" -ne 0 ]; then
    echo "Metal3-dev-env setup failed, try again"
    make clean
    make setup_env
fi
popd || exit
