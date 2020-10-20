#!/bin/bash
set -e

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/.."

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/lib/common.sh"

eval "$(go env)"
export GOPATH

# Environment variables
# M3PATH : Path to clone the Metal3 Development Environment repository
# BMOPATH : Path to clone the Bare Metal Operator repository

M3PATH="${GOPATH}/src/github.com/metal3-io"
BMOPATH="${M3PATH}/baremetal-operator"

pushd "${BMOPATH}"
while :
do
	make run || true
done
