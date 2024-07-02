#!/bin/bash
set -xe

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/.."

# shellcheck disable=SC1090,SC1091
source "${METAL3_DIR}/lib/common.sh"

export ACTION="ci_test_provision"

"${METAL3_DIR}"/tests/run.sh

# Manifest collection before pivot
"${METAL3_DIR}"/tests/scripts/fetch_manifests.sh

# wait until status of Metal3Machine is rebuilt
while [[ -z "${status:-}" ]]
do
    status=$(kubectl get m3m -n "${NAMESPACE}" -o=jsonpath="{.items[*]['status.ready']}")
    sleep 1s
done

# Manifest collection after re-pivot
"${METAL3_DIR}"/tests/scripts/fetch_manifests.sh

kubectl get secrets "${CLUSTER_NAME}-kubeconfig" -n "${NAMESPACE}" -o json | jq -r '.data.value'| base64 -d > "/tmp/kubeconfig-${CLUSTER_NAME}.yaml"
NUM_DEPLOYED_NODES="$(kubectl get nodes --kubeconfig "/tmp/kubeconfig-${CLUSTER_NAME}.yaml" | grep -c -w Ready)"
process_status $? "Fetch number of deployed nodes"

if [ "${NUM_DEPLOYED_NODES}" -ne "$((CONTROL_PLANE_MACHINE_COUNT + WORKER_MACHINE_COUNT))" ]; then
    echo "Failed with incorrect number of nodes deployed"
    exit 1
fi

export ACTION="ci_test_deprovision"

"${METAL3_DIR}"/tests/run.sh
