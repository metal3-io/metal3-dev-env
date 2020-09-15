#!/bin/bash

set -x

IRONIC_IMAGE_TAG=master

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../../"
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
worker_has_correct_replicas 1

# Do pivoting
# This will be replace by a bash script specific to pivoting from upgrade scripts
export ACTION="upgrading"
pushd "/home/ubuntu/metal3-dev-env/scripts/feature_tests/pivoting/"
make pivoting
popd
# ----------- upgrade controlplane components ---------------
cleanup_clusterctl_configuration

buildClusterctl

# Install initial version folder structure
pushd /tmp/cluster-api-clone || exit
cmd/clusterctl/hack/local-overrides.py
popd || exit

create_clusterctl_configuration

createNextVersionControllers

makeCrdChanges

# show upgrade plan
clusterctl upgrade plan
# do upgrade
clusterctl upgrade plan | grep "upgrade apply" | xargs | xargs clusterctl
# shellcheck disable=SC2082
# Verify upgrade
upgraded_controllers_count=$(kubectl api-resources | grep -Ec "kcp2020|ma2020")
upgraded_bootstrap_crd_count=$(kubectl get crds \
  kubeadmconfigs.bootstrap.cluster.x-k8s.io -o json | jq '.spec.names.singular' | wc -l)
upgraded_capm3_controller_count=$(kubectl api-resources | grep -c m3c2020)

if [ "${upgraded_controllers_count}" -ne 2 ]; then
  log_error "Failed to upgrade cluster-api and controlplane components"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi
if [ "${upgraded_bootstrap_crd_count}" -ne 1 ]; then
  log_error "Failed to upgrade control-plane-kubeadm components"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi

if [ "${upgraded_capm3_controller_count}" -ne 1 ]; then
  log_error "Failed to upgrade infrastructure components"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi

sleep 30 # Wait for the controllers to be up and running

health_controllers=$(kubectl get pods -A | grep -E "capm3-system|capi-kubeadm|metal3" |
  grep -vc 'Running')
if [ "${health_controllers}" -ne 0 ]; then
  log_error "Some of the upgraded controlplane components are not healthy"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi

# ----------- upgrade ironic image ------

# Upgrade container images
for container in ironic ironic-dnsmasq ironic-httpd mariadb; do
  kubectl set image deployments metal3-ironic \
    $container=quay.io/metal3-io/ironic:"${IRONIC_IMAGE_TAG}" -n "${NAMESPACE}"
done
kubectl set image deployments metal3-ironic \
  ironic-inspector=quay.io/metal3-io/ironic-inspector:"${IRONIC_IMAGE_TAG}" -n "${NAMESPACE}"

updated_ironic_image_count=$(kubectl get deployments metal3-ironic -n "${NAMESPACE}" -o json |
  jq '.spec.template.spec.containers[].image' | grep -c "${IRONIC_IMAGE_TAG}")

if [ "${updated_ironic_image_count}" -lt "${NUM_IRONIC_IMAGES}" ]; then
  echo "All ironic images are not updated properly"
  exit 1
fi

sleep 60 # wait until images are downloaded

# Check if old and new ironic pods are running, wait until the old terminates
ironic_pod_count=$(kubectl get pods -n "${NAMESPACE}" -o name | grep -c metal3-ironic)
ironic_pod=$(kubectl get pods -n "${NAMESPACE}" -o name | grep metal3-ironic)

if [ "${ironic_pod_count}" -gt 1 ]; then
  for i in {1..300}; do
	  sleep 15
	  ironic_pod_count=$(kubectl get pods -n "${NAMESPACE}" -o name | grep -c metal3-ironic)
	  if [ "${ironic_pod_count}" -eq 1 ]; then
		  ironic_pod=$(kubectl get pods -n "${NAMESPACE}" -o name | grep metal3-ironic)
		  break
	  fi
    if [[ "${i}" -ge 300 ]]; then
      ironic_pod=$(kubectl get pods -n "${NAMESPACE}" -o name | grep metal3-ironic)
      log_error " Ironic pods failed: ${ironic_pod}"
      exit 1
    fi
  done
else
  echo "New ironic pod id: ${ironic_pod}"
fi

# Check that ironic containers are running
for container in ironic ironic-inspector ironic-dnsmasq ironic-httpd mariadb; do
  running_containers_count=$(
    kubectl get "${ironic_pod}" -n "${NAMESPACE}" -o json |
      jq ".status.containerStatuses[] | select(.name == \"${container}\") | .state" |
      grep -ic running
  )
  if [ "${running_containers_count}" -eq 0 ]; then
    echo "Upgrade of ironic image for container ${container} has failed"
    exit 1
  fi
done

# ----------- upgrade boot disk image and kubernetes version ------
echo "Create a new metal3MachineTemplate with new node image for both \
controlplane and worker nodes"
cp_Metal3MachineTemplate_OUTPUT_FILE="/tmp/cp_new_image.yaml"
wr_Metal3MachineTemplate_OUTPUT_FILE="/tmp/wr_new_image.yaml"
CLUSTER_UID=$(kubectl get clusters -n "${NAMESPACE}" test1 -o json | jq '.metadata.uid' |
  cut -f2 -d\")
generate_metal3MachineTemplate "${CLUSTER_NAME}-new-controlplane-image" "${CLUSTER_UID}" \
  "${cp_Metal3MachineTemplate_OUTPUT_FILE}" \
  "${CAPM3_VERSION}" "${CAPI_VERSION}" \
  "${CLUSTER_NAME}-controlplane-template"
generate_metal3MachineTemplate "${CLUSTER_NAME}-new-workers-image" "${CLUSTER_UID}" \
  "${wr_Metal3MachineTemplate_OUTPUT_FILE}" \
  "${CAPM3_VERSION}" "${CAPI_VERSION}" \
  "${CLUSTER_NAME}-workers-template"

kubectl apply -f "${cp_Metal3MachineTemplate_OUTPUT_FILE}"
kubectl apply -f "${wr_Metal3MachineTemplate_OUTPUT_FILE}"

# controllers
kubectl get kcp -n "${NAMESPACE}" test1 -o json |
  jq ".spec.infrastructureTemplate.name=\"test1-new-controlplane-image\" |
  .spec.version=\"${UPGRADED_K8S_VERSION_2}\"" |
  kubectl apply -f-
kubectl get machinedeployment -n "${NAMESPACE}" test1 -o json |
  jq ".spec.strategy.rollingUpdate.maxSurge=1|.spec.strategy.rollingUpdate.maxUnavailable=0 |
  .spec.template.spec.version=\"${UPGRADED_K8S_VERSION_2}\"" |
  kubectl apply -f-
sleep 10

# Verify kubernetes version upgrade
verify_kubernetes_version_upgrade "${UPGRADED_K8S_VERSION_2}" 2

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
log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "pass"

# Test cleanup
cleanup_clusterctl_configuration

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
