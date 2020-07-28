#!/bin/bash

set -x

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../"

# Remove old test result
rm -rf /tmp/"$(date +%Y.%m.%d_upgrade.result.txt)"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/lib/common.sh"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/lib/network.sh"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/lib/images.sh"

# -----------------------------------------
# Syntax:
# source <script name>.sh <log file prefix>
# -----------------------------------------

# Run cluster level ugprade tests
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade" || exit
# shellcheck disable=SC1091
source 1cp_1w_bootDiskImage_cluster_upgrade.sh
popd || exit

# Run worker upgrade cases
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/workers_upgrade" || exit
# shellcheck disable=SC1091
source 1cp_3w_bootDiskImage_scaleInWorkers_upgrade_both.sh
popd || exit

# Run controlplane upgrade tests
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/controlplane_upgrade" || exit
# shellcheck disable=SC1091
source 3cp_1w_k8sVer_bootDiskImage_scaleInWorker_upgrade.sh
popd || exit

# This needs to be replaced by 1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh
# Run controlplane components upgrade tests | This should be the last one
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/controlplane_components_upgrade" || exit
# shellcheck disable=SC1091
source upgrade_CAPI_and_CAPM3_with_clusterctl.sh
popd || exit

set +x
