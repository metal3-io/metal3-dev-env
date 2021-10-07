#!/bin/bash
set -xe

METAL3_DIR="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1090
# shellcheck disable=SC1091
source "${METAL3_DIR}/lib/common.sh"

export ACTION="ci_test_provision"

"${METAL3_DIR}"/scripts/run.sh

"${METAL3_DIR}"/scripts/fetch_manifests.sh

kubectl get secrets "${CLUSTER_NAME}-kubeconfig" -n "${NAMESPACE}" -o json | jq -r '.data.value'| base64 -d > "/tmp/kubeconfig-${CLUSTER_NAME}.yaml"
NUM_DEPLOYED_NODES="$(kubectl get nodes --kubeconfig "/tmp/kubeconfig-${CLUSTER_NAME}.yaml" | grep -c -w Ready)"
process_status $? "Fetch number of deployed nodes"

if [ "${NUM_DEPLOYED_NODES}" -ne "$((NUM_OF_MASTER_REPLICAS + NUM_OF_WORKER_REPLICAS))" ]; then
    echo "Failed with incorrect number of nodes deployed"
    exit 1
fi

export ACTION="ci_test_deprovision"

