#!/bin/bash
set -x

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh

# Remove old SSH keys
ssh-keygen -f /home/"${USER}"/.ssh/known_hosts -R "${CLUSTER_APIENDPOINT_IP}"

# Kill and remove the running ironic containers
for name in ironic ironic-inspector ironic-endpoint-keepalived dnsmasq httpd mariadb; do
  sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill $name
  sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm $name -f
done

pushd "${CAPIPATH}" || exit
cd bin || exit
./clusterctl delete --all -v5
popd || exit

pushd "${BMOPATH}" || exit
kubectl delete -f bmhosts_crs.yaml -n "${NAMESPACE}" --timeout 10s
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

# Re-create ironic containers and BMH
pushd "${BMOPATH}" || exit
./tools/run_local_ironic.sh
popd || exit

pushd "${CAPIPATH}" || exit
cd bin || exit
./clusterctl init --infrastructure=metal3:"${CAPM3RELEASE}" -v5
popd || exit

pushd "${BMOPATH}" || exit
kubectl apply -f bmhosts_crs.yaml -n "${NAMESPACE}"
popd || exit

make -C "${SCRIPTDIR}" verify
