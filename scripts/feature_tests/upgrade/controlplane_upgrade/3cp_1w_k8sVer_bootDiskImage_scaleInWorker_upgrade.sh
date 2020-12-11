#!/bin/bash

set -x

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../../"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/upgrade_common.sh"

echo '' >~/.ssh/known_hosts

start_logging "${1}"

set_number_of_master_node_replicas 3
set_number_of_worker_node_replicas 1
provision_controlplane_node

set_kubeconfig_towards_target_cluster
controlplane_has_correct_replicas 3
point_to_management_cluster

provision_worker_node

point_to_target_cluster
worker_has_correct_replicas 1
point_to_management_cluster

# Add maxSurge and maxUnvailable to 1 in the machinedeployment.
kubectl get machinedeployment -n "${NAMESPACE}" test1 -o json |
  jq '.spec.strategy.rollingUpdate.maxSurge=1|.spec.strategy.rollingUpdate.maxUnavailable=1' |
  kubectl apply -f-
sleep 30

## Start pivoting
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/pivoting" || exit
make upgrading
popd || exit
sleep 120

point_to_target_cluster
# Untaint the masters
manage_node_taints

scale_workers_to 0
worker_has_correct_replicas 0
expected_free_nodes 1

# k8s version upgrade
CLUSTER_NAME=$(kubectl get clusters -n "${NAMESPACE}" | grep -i provisioned | cut -f1 -d' ')
FROM_VERSION=$(kubectl get kcp -n "${NAMESPACE}" -oyaml |
  grep "version: v1" | cut -f2 -d':' | awk '{$1=$1;print}')

if [[ "${FROM_VERSION}" < "${UPGRADED_K8S_VERSION_2}" ]]; then
  TO_VERSION="${UPGRADED_K8S_VERSION_2}"
elif [[ "${FROM_VERSION}" > "${KUBERNETES_VERSION}" ]]; then
  TO_VERSION="${KUBERNETES_VERSION}"
else
  echo "Provided kubernetes version is not correct........."
  exit 1
fi

# Controlplane node image upgrade
M3_MACHINE_TEMPLATE_NAME=$(kubectl get Metal3MachineTemplate -n "${NAMESPACE}" -oyaml |
  grep "name: " | grep -o "${CLUSTER_NAME}-controlplane" -m1)

Metal3MachineTemplate_OUTPUT_FILE="/tmp/cp31_image.yaml"
CLUSTER_UID=$(kubectl get clusters -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
  jq '.metadata.uid' | cut -f2 -d\")
generate_metal3MachineTemplate new-controlplane-image "${CLUSTER_UID}" \
  "${Metal3MachineTemplate_OUTPUT_FILE}" \
  "${CAPM3_VERSION}" "${CAPI_VERSION}" \
  "${CLUSTER_NAME}-controlplane-template"
kubectl apply -f "${Metal3MachineTemplate_OUTPUT_FILE}"

echo "Upgrading a control plane node image and k8s version from ${FROM_VERSION}\
 to ${TO_VERSION} in cluster ${CLUSTER_NAME}"

# Trigger the upgrade by replacing node image and k8s version in KCP
kubectl get kcp -n "${NAMESPACE}" -oyaml | 
	sed "s/version: ${FROM_VERSION}/version: ${TO_VERSION}/" | 
	sed "s/name: ${M3_MACHINE_TEMPLATE_NAME}/name: new-controlplane-image/" | 
	kubectl replace -f -

cp_nodes_using_new_bootDiskImage 3

# Untaint the masters
manage_node_taints

controlplane_has_correct_replicas 3
expected_free_nodes 1
scale_workers_to 1
worker_has_correct_replicas 1
echo "Successfully upgrade 3 CP nodes"

# Applying workload to the worker with node affinity
WORKER_NAME=$(kubectl get nodes -n "${NAMESPACE}" | awk 'NR>1'| grep -v master | awk '{print $1}')
kubectl label node "${WORKER_NAME}" type=worker

# Deploy workload with node affinity
deploy_workload_on_workers

# Upgrade worker node image
export new_wr_metal3MachineTemplate_name="${CLUSTER_NAME}-new-workers-image"
echo "Create a new metal3MachineTemplate with new node image for worker nodes"
wr_Metal3MachineTemplate_OUTPUT_FILE="/tmp/wr31_new_image.yaml"

CLUSTER_UID=$(kubectl get clusters -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
    jq '.metadata.uid' | cut -f2 -d\")
generate_metal3MachineTemplate "${new_wr_metal3MachineTemplate_name}" \
        "${CLUSTER_UID}" "${wr_Metal3MachineTemplate_OUTPUT_FILE}" \
        "${CAPM3_VERSION}" "${CAPI_VERSION}" \
        "${CLUSTER_NAME}-workers-template"

kubectl apply -f "${wr_Metal3MachineTemplate_OUTPUT_FILE}"

kubectl get machinedeployment -n "${NAMESPACE}" "${CLUSTER_NAME}" -o json |
        jq '.spec.template.spec.infrastructureRef.name="test1-new-workers-image"' |
        kubectl apply -f-

wr_nodes_using_new_bootDiskImage 1
worker_has_correct_replicas 1
log_test_result "3cp_1w_k8sVer_bootDiskImage_scaleInWorker_upgrade.sh" "pass"

point_to_management_cluster

# Pivot back
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/pivoting" || exit
make repivoting
popd || exit

deprovision_cluster
wait_for_cluster_deprovisioned
set +x
