#!/bin/bash

set -x
# Make sure capm3 is of v3.0.2, at least the folder should exist
METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../"
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/upgrade_common.sh"

echo '' >~/.ssh/known_hosts

start_logging "${1}"
# Provision original nodes
set_number_of_master_node_replicas 1
set_number_of_worker_node_replicas 3 # Temporary solution for moving all BMHs

provision_controlplane_node

# Get kubeconfig before pivoting | will be overriden when pivoting
# Relevant when re-using the cluster for successive tests
kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml
export KUBECONFIG=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml

controlplane_is_provisioned
controlplane_has_correct_replicas 1

# apply CNI
apply_cni

provision_worker_node
worker_has_correct_replicas 3

# Do pivoting
# This will be replace by a bash script specific to pivoting from upgrade scripts
export ACTION="upgrading"
pushd "/home/ubuntu/metal3-dev-env/scripts/feature_tests/pivoting/"
make pivoting
popd

# All bmh resources are moved, now scale back workers to 1
scale_workers_to 1
worker_has_correct_replicas 1

#  ----------------------- peform upgrade tasks ----------------------
# Change boot disk image
echo "Create a new metal3MachineTemplate with new node image for both \
controlplane and worker nodes"
cp_Metal3MachineTemplate_OUTPUT_FILE="/tmp/cp11_new_image.yaml"
wr_Metal3MachineTemplate_OUTPUT_FILE="/tmp/wr11_new_image.yaml"
CLUSTER_UID=$(kubectl get clusters -n "${NAMESPACE}" test1 -o json | jq '.metadata.uid' |
  cut -f2 -d\")
generate_metal3MachineTemplate "${CLUSTER_NAME}-new-controlplane-image" \
  "${CLUSTER_UID}" "${cp_Metal3MachineTemplate_OUTPUT_FILE}" \
  "${CAPM3_VERSION}" "${CAPI_VERSION}" \
  "${CLUSTER_NAME}-controlplane-template"
generate_metal3MachineTemplate "${CLUSTER_NAME}-new-workers-image" \
  "${CLUSTER_UID}" "${wr_Metal3MachineTemplate_OUTPUT_FILE}" \
  "${CAPM3_VERSION}" "${CAPI_VERSION}" \
  "${CLUSTER_NAME}-workers-template"

kubectl apply -f "${cp_Metal3MachineTemplate_OUTPUT_FILE}"
kubectl apply -f "${wr_Metal3MachineTemplate_OUTPUT_FILE}"

kubectl get kcp -n "${NAMESPACE}" test1 -o json |
  jq '.spec.infrastructureTemplate.name="test1-new-controlplane-image"' | kubectl apply -f-
kubectl get machinedeployment -n "${NAMESPACE}" test1 -o json |
  jq '.spec.strategy.rollingUpdate.maxSurge=1|.spec.strategy.rollingUpdate.maxUnavailable=0' |
  kubectl apply -f-
sleep 10
kubectl get machinedeployment -n "${NAMESPACE}" test1 -o json |
  jq '.spec.template.spec.infrastructureRef.name="test1-new-workers-image"' |
  kubectl apply -f-

# Verify new boot disk image usage
cp_nodes_using_new_bootDiskImage 1
wr_nodes_using_new_bootDiskImage 1

# Verify nodes are freed
expected_free_nodes 2

# verify that extra nodes are not removed
controlplane_has_correct_replicas 1
worker_has_correct_replicas 1

# Report result
echo "Boot disk upgrade of both controlplane and worker nodes has succeeded."
log_test_result "1cp_1w_bootDiskImage_cluster_upgrade.sh" "pass"

# ------------------pivot back here ----------------------- #
# This needs to be replaced by a script that does pivot-back
export ACTION="pivotBack"
pushd "/home/ubuntu/metal3-dev-env/scripts/feature_tests/pivoting/"
make pivoting
popd
# Test cleanup

unset KUBECONFIG # point to ~/.kube/config

deprovision_cluster
wait_for_cluster_deprovisioned

set -x
