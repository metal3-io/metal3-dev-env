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

controlplane_is_provisioned
controlplane_has_correct_replicas 3

# apply CNI
apply_cni

provision_worker_node
worker_has_correct_replicas 1

deploy_workload_on_workers

manage_node_taints "${CLUSTER_APIENDPOINT_IP}"

scale_workers_to 0
worker_has_correct_replicas 0

# k8s version upgrade
CLUSTER_NAME=$(kubectl get clusters -n metal3 | grep Provisioned | cut -f1 -d' ')
FROM_VERSION=$(kubectl get kcp -n metal3 -oyaml |
  grep "version: v1" | cut -f2 -d':' | awk '{$1=$1;print}')

if [[ "${FROM_VERSION}" < "${UPGRADED_K8S_VERSION_2}" ]]; then
  TO_VERSION="${UPGRADED_K8S_VERSION_2}"
elif [[ "${FROM_VERSION}" > "${KUBERNETES_VERSION}" ]]; then
  TO_VERSION="${KUBERNETES_VERSION}"
else
  exit 0
fi

# Node image version upgrade
M3_MACHINE_TEMPLATE_NAME=$(kubectl get Metal3MachineTemplate -n metal3 -oyaml |
  grep "name: " | grep controlplane | cut -f2 -d':' | awk '{$1=$1;print}')

Metal3MachineTemplate_OUTPUT_FILE="/tmp/new_image.yaml"
CLUSTER_UID=$(kubectl get clusters -n metal3 "${CLUSTER_NAME}" -o json |
  jq '.metadata.uid' | cut -f2 -d\")
generate_metal3MachineTemplate new-controlplane-image "${CLUSTER_UID}" \
  "${Metal3MachineTemplate_OUTPUT_FILE}"
kubectl apply -f "${Metal3MachineTemplate_OUTPUT_FILE}"

echo "Upgrading a control plane node image and k8s version from ${FROM_VERSION}\
 to ${TO_VERSION} in cluster ${CLUSTER_NAME}"
# Trigger the upgrade by replacing node image and k8s version in kcp yaml:
kubectl get kcp -n metal3 -oyaml |
  sed "s/version: ${FROM_VERSION}/version: ${TO_VERSION}/" |
  sed "s/name: ${M3_MACHINE_TEMPLATE_NAME}/name: new-controlplane-image/" | kubectl replace -f -

cp_nodes_using_new_bootDiskImage 3

scale_workers_to 1
worker_has_correct_replicas 1

echo "Successfully upgrade 1 CP and 3 worker nodes"
log_test_result "3cp_1w_k8sVer_bootDiskImage_scaleInWorker_upgrade.sh" "pass"

deprovision_cluster
wait_for_cluster_deprovisioned

set +x
