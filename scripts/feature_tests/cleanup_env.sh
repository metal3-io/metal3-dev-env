#!/bin/bash
set -x

ROOTPATH="$(dirname "$(readlink -f "${0}")")/../.."

# shellcheck disable=SC1091
source "${ROOTPATH}/scripts/feature_tests/feature_test_vars.sh"
# shellcheck disable=SC1091
source "${ROOTPATH}/lib/logging.sh"
# shellcheck disable=SC1091
source "${ROOTPATH}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOTPATH}/lib/releases.sh"
# shellcheck disable=SC1091
source "${ROOTPATH}/lib/network.sh"
# shellcheck disable=SC1091
source "${ROOTPATH}/lib/ironic_tls_setup.sh"
# shellcheck disable=SC1091
source "${ROOTPATH}/lib/ironic_basic_auth.sh"

# Remove old SSH keys
ssh-keygen -f /home/"${USER}"/.ssh/known_hosts -R "${CLUSTER_APIENDPOINT_IP}"

if [ "${EPHEMERAL_CLUSTER}" == "kind" ]; then
  # Kill and remove the running ironic containers
  "$BMOPATH"/tools/remove_local_ironic.sh
else 
  # Scale down ironic
  kubectl scale deploy -n "${IRONIC_NAMESPACE}" capm3-ironic --replicas=0
fi

clusterctl delete --all -v5

pushd "${BMOPATH}" || exit
kubectl delete -f "${WORKING_DIR}/bmhosts_crs.yaml" -n "${NAMESPACE}" --timeout 10s
popd || exit

declare -a OBJECTS=("cluster" \
"baremetalhost" \
"kubeadmconfig" \
"kubeadmcontrolplane" \
"machines" \
"metal3cluster" \
"metal3machine" \
"metal3machinetemplate" \
"m3ippool" \
"m3ipclaim" \
"ipaddress" \
"m3data" \
"m3dataclaim" \
"m3datatemplate")

delete_finalizers(){
local kind
for name in "${OBJECTS[@]}"; do
  kind="$(kubectl get "${name}" -n "${NAMESPACE}" -o name)"
  for item in $kind; do
          kubectl patch "${item}" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":[]}}' --type=merge
          kubectl delete "${item}" -n "${NAMESPACE}" --timeout 10s
  done
  process_status $?
done
}

delete_finalizers

if [ "${EPHEMERAL_CLUSTER}" == "kind" ]; then
  # Re-create ironic containers and BMH 
  pushd "${BMOPATH}" || exit
  ./tools/run_local_ironic.sh
  popd || exit
else 
  # Scale up ironic
  kubectl scale deploy -n "${IRONIC_NAMESPACE}" capm3-ironic --replicas=1
fi

# shellcheck disable=SC2153
clusterctl init --core cluster-api:"${CAPIRELEASE}" --bootstrap kubeadm:"${CAPIRELEASE}" --control-plane kubeadm:"${CAPIRELEASE}" --infrastructure=metal3:"${CAPM3RELEASE}" -v5

pushd "${BMOPATH}" || exit
kubectl apply -f "${WORKING_DIR}/bmhosts_crs.yaml" -n "${NAMESPACE}"
popd || exit

make -C "${SCRIPTDIR}" verify
