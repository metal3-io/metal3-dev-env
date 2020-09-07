#!/bin/bash

set -x

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../../"
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/upgrade_common.sh"

echo '' >~/.ssh/known_hosts

start_logging "${1}"

# Old name does not matter
export new_wr_metal3MachineTemplate_name="${CLUSTER_NAME}-new-workers-image"
export new_cp_metal3MachineTemplate_name="${CLUSTER_NAME}-new-controlplane-image"

set_number_of_master_node_replicas 1
set_number_of_worker_node_replicas 3

provision_controlplane_node
controlplane_is_provisioned
controlplane_has_correct_replicas 1

# apply CNI
apply_cni

provision_worker_node
worker_has_correct_replicas 3

# Change metal3MachineTemplate references.
# Risk for race conditions if done after template generation
kubectl get machinedeployment -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
	jq '.spec.strategy.rollingUpdate.maxSurge=1|.spec.strategy.rollingUpdate.maxUnavailable=1' |
	kubectl apply -f-
kubectl get machinedeployment -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
	jq '.spec.template.spec.infrastructureRef.name="test1-new-workers-image"' |
	kubectl apply -f-

echo "Create a new metal3MachineTemplate with new node image for worker nodes"
wr_Metal3MachineTemplate_OUTPUT_FILE="/tmp/wr13_new_image.yaml"

CLUSTER_UID=$(kubectl get clusters -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
    jq '.metadata.uid' | cut -f2 -d\")
generate_metal3MachineTemplate "${new_wr_metal3MachineTemplate_name}" \
	"${CLUSTER_UID}" "${wr_Metal3MachineTemplate_OUTPUT_FILE}" \
	"${CAPM3_VERSION}" "${CAPI_VERSION}" \
	"${CLUSTER_NAME}-workers-template"

kubectl apply -f "${wr_Metal3MachineTemplate_OUTPUT_FILE}"

wr_nodes_using_new_bootDiskImage 3

deploy_workload_on_workers

scale_workers_to 2
worker_has_correct_replicas 2

# upgrade a Controlplane
echo "Create a new metal3MachineTemplate with new node image for both controlplane node"
cp_Metal3MachineTemplate_OUTPUT_FILE="/tmp/cp13_new_image.yaml"
CLUSTER_UID=$(kubectl get clusters -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
    jq '.metadata.uid' | cut -f2 -d\")
generate_metal3MachineTemplate "${new_cp_metal3MachineTemplate_name}" \
	"${CLUSTER_UID}" "${cp_Metal3MachineTemplate_OUTPUT_FILE}" \
	"${CAPM3_VERSION}" "${CAPI_VERSION}" \
	"${CLUSTER_NAME}-controlplane-template"
kubectl apply -f "${cp_Metal3MachineTemplate_OUTPUT_FILE}"

# Change metal3MachineTemplate references.
kubectl get kcp -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
	jq '.spec.infrastructureTemplate.name="test1-new-controlplane-image"' |
	kubectl apply -f-

cp_nodes_using_new_bootDiskImage 1
# wait for the original CP to be deprovisioned.
controlplane_has_correct_replicas 1

scale_workers_to 3
worker_has_correct_replicas 3

echo "Upgrading of both (1M + 3W) using scaling in of workers has succeeded"
log_test_result "1cp_3w_bootDiskImage_scaleInWorkers_upgrade_both.sh" "pass"

deprovision_cluster
wait_for_cluster_deprovisioned

set +x
