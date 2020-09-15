#!/bin/bash

set -x

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../../"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/upgrade_common.sh"

start_logging "${1}"

cleanup_clusterctl_configuration

buildClusterctl

# Install initial version folder structure
pushd /tmp/cluster-api-clone || exit
cmd/clusterctl/hack/local-overrides.py
popd || exit

create_clusterctl_configuration

# Create a new version
createNextVersionControllers

makeCrdChanges

# do upgrade
clusterctl upgrade plan | grep "upgrade apply" | xargs | xargs clusterctl

# Verify upgrade
upgraded_controllers_count=$(kubectl api-resources | grep -Ec "kcp2020|ma2020")
upgraded_bootstrap_crd_count=$(kubectl get crds \
  kubeadmconfigs.bootstrap.cluster.x-k8s.io -o json | jq '.spec.names.singular' | wc -l)
upgraded_capm3_controller_count=$(kubectl api-resources | grep -c m3c2020)

if [ "${upgraded_controllers_count}" -ne 2 ]; then
  log_error "Failed to upgrade cluster-api and controlplane components"
  log_test_result "upgrade_CAPI_and_CAPM3_with_clusterctl.sh" "fail"
  exit 1
fi
if [ "${upgraded_bootstrap_crd_count}" -ne 1 ]; then
  log_error "Failed to upgrade control-plane-kubeadm components"
  log_test_result "upgrade_CAPI_and_CAPM3_with_clusterctl.sh" "fail"
  exit 1
fi

if [ "${upgraded_capm3_controller_count}" -ne 1 ]; then
  log_error "Failed to upgrade infrastructure components"
  log_test_result "upgrade_CAPI_and_CAPM3_with_clusterctl.sh" "fail"
  exit 1
fi

sleep 30 # Wait for the controllers to be up and running

health_controllers=$(kubectl get pods -A | grep -E "capm3-system|capi-kubeadm|metal3" | grep -vc 'Running')
if [ "${health_controllers}" -ne 0 ]; then
  log_error "Some of the upgraded controlplane components are not healthy"
  log_test_result "upgrade_CAPI_and_CAPM3_with_clusterctl.sh" "fail"
  exit 1
fi

# cleanup
cleanup_clusterctl_configuration

echo "Successfully upgraded cluster-api, controlplane and controlplane-kubeadm components"
log_test_result "upgrade_CAPI_and_CAPM3_with_clusterctl.sh" "pass"
set +x


# This test case is no longer relevant as it is included in the combined tests
