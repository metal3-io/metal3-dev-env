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
# M3PATH : Path to clone the metal3 dev env repo
# BMOPATH : Path to clone the baremetal operator repo
# CAPM3PATH: Path to clone the CAPI operator repo
#
# BMOREPO : Baremetal operator repository URL
# BMOBRANCH : Baremetal operator repository branch to checkout
# CAPM3REPO : CAPI operator repository URL
# CAPM3BRANCH : CAPI repository branch to checkout
# FORCE_REPO_UPDATE : discard existing directories
#
# BMO_RUN_LOCAL : run the baremetal operator locally (not in Kubernetes cluster)
# CAPM3_RUN_LOCAL : run the CAPI operator locally

M3PATH="${GOPATH}/src/github.com/metal3-io"
BMOPATH="${M3PATH}/baremetal-operator"

pushd "${BMOPATH}"
while :
do
	make run || true
done
