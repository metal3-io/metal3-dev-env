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

# Get kubeconfig before pivoting | will be overriden when pivoting
# Relevant when re-using the cluster for successive tests
kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml
export KUBECONFIG=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml

controlplane_is_provisioned
controlplane_has_correct_replicas 3

# apply CNI
apply_cni

provision_worker_node
worker_has_correct_replicas 1

deploy_workload_on_workers

# Do pivoting
# This will be replace by a bash script specific to pivoting from upgrade scripts
export ACTION="upgrading"
pushd "/home/ubuntu/metal3-dev-env/scripts/feature_tests/pivoting/"
make pivoting
popd

manage_node_taints "${CLUSTER_APIENDPOINT_IP}"

scale_workers_to 0
worker_has_correct_replicas 0
expected_free_nodes 1

# k8s version upgrade
CLUSTER_NAME=$(kubectl get clusters -n "${NAMESPACE}" | grep Provisioned | cut -f1 -d' ')
FROM_VERSION=$(kubectl get kcp -n "${NAMESPACE}" -oyaml |
  grep "version: v1" | cut -f2 -d':' | awk '{$1=$1;print}')

if [[ "${FROM_VERSION}" < "${UPGRADED_K8S_VERSION_2}" ]]; then
  TO_VERSION="${UPGRADED_K8S_VERSION_2}"
elif [[ "${FROM_VERSION}" > "${KUBERNETES_VERSION}" ]]; then
  TO_VERSION="${KUBERNETES_VERSION}"
else
  exit 0
fi

# Node image version upgrade
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
# Trigger the upgrade by replacing node image and k8s version in kcp yaml:
kubectl get kcp -n "${NAMESPACE}" -oyaml |
  sed "s/version: ${FROM_VERSION}/version: ${TO_VERSION}/" |
  sed "s/name: ${M3_MACHINE_TEMPLATE_NAME}/name: new-controlplane-image/" | kubectl replace -f -

cp_nodes_using_new_bootDiskImage 3

scale_workers_to 1
worker_has_correct_replicas 1

echo "Successfully upgrade 3 CP and 1 worker nodes"
log_test_result "3cp_1w_k8sVer_bootDiskImage_scaleInWorker_upgrade.sh" "pass"

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

set +x
