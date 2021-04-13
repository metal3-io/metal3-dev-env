#!/bin/bash

set -x

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../../"

# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/upgrade_common.sh"
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/upgrade_vars.sh"

echo '' >~/.ssh/known_hosts

start_logging "${1}"

set_number_of_master_node_replicas 3
set_number_of_worker_node_replicas 1
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
#                       source cluster: Provision 3CP + 1W cluster
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
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

# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
#                       source cluster: Start pivoting
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
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
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
#                       target cluster: Upgrade CP components
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
point_to_target_cluster
# Add missing variables that were absent on the source cluster due to ironic running as containers.
kubectl get cm -n capm3-system capm3-baremetal-operator-ironic -o json |
    jq '.data' |grep -E "_URL|_ENDPOINT" | cut -sf2,4 -d\" --output-delimiter=' ' |
    awk '{{print "export "$1"="$2}}' > /tmp/configmap.with.values

# shellcheck disable=SC1091
source "/tmp/configmap.with.values"
export IRONIC_URL=${IRONIC_ENDPOINT}
export IRONIC_INSPECTOR_URL=${IRONIC_INSPECTOR_ENDPOINT}

# During upgrade of CP components relevant fields of secrets are cleared.
# Therefore, back up secrets as username,password and tls values
kubectl get secrets -n capm3-system -o json | 
	jq '.items[]|del(.metadata|.managedFields,.uid,.resourceVersion)' > /tmp/secrets.with.values.yaml

cleanup_clusterctl_configuration

buildClusterctl

# Install initial version folder structure
pushd /tmp/cluster-api-clone || exit
git checkout "${CAPIRELEASE}"
cmd/clusterctl/hack/create-local-repository.py
popd || exit

create_clusterctl_configuration

createNextVersionControllers

makeCrdChanges

# show upgrade plan
clusterctl upgrade plan
# do upgrade
clusterctl upgrade apply --management-group capi-system/cluster-api --contract v1alpha3
sleep 30

# restore secrets to fill missing secret fields
kubectl replace -f /tmp/secrets.with.values.yaml
sleep 120

# Verify that CP components' pods are running
for i in {1..10}; do
  non_healthy_controllers=$(kubectl get pods -A | 
	  grep -E "capi-kubeadm-bootstrap-|capi-kubeadm-control-plane-|capi-|capm3-|metal3" | grep -vc 'Running')
  if [ "${non_healthy_controllers}" -eq 0 ]; then
      break
  fi
  if [[ "${i}" -ge 10 ]]; then
     echo "The following controllers are not upgraded"
     kubectl get pods -A | grep -E "capi-kubeadm-bootstrap-|capi-kubeadm-control-plane-|capi-|capm3-|metal3" | grep -v Running | awk '{{print $2}}'
     log_error "Some of the upgraded controlplane components are not healthy"
     log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
     exit 1
  fi
     sleep 10
done

# Verify upgrade of CRDs
upgraded_capi_controller_count=$(kubectl explain machine | grep -i description -A1 | grep -ic upgradedMachine)
upgraded_controllers_kcp_count=$(kubectl explain kcp | grep -i description -A1 | grep -ci upgradedKubeadmControlPlane)
upgraded_bootstrap_count=$(kubectl explain KubeadmConfig | grep -i description -A1 | grep -ci upgradedKubeadmConfig)
upgraded_capm3_controller_count=$(kubectl api-resources -o wide | grep -c m3c2020)

if [ "${upgraded_controllers_kcp_count}" -ne 1 ]; then
  log_error "Failed to upgrade KubeadmControlPlane controlplane component"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi

if [ "${upgraded_capi_controller_count}" -ne 1 ]; then
  log_error "Failed to upgrade cluster-api controlplane component"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi

if [ "${upgraded_bootstrap_count}" -ne 1 ]; then
  log_error "Failed to upgrade KubeadmConfig controlplane component"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi

if [ "${upgraded_capm3_controller_count}" -ne 1 ]; then
    log_error "Failed to upgrade CAPM3 controlplane component"
    log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
    exit 1
fi
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
#                       source cluster: Upgrade CP components
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
# In order for re-pivoting to succeed, the CP components on the source cluster should not be
# older than the ones in the target cluster. Therefore, upgrade the ones in the source as well.
point_to_management_cluster

clusterctl upgrade plan
clusterctl upgrade apply --management-group capi-system/cluster-api --contract v1alpha3
sleep 30
kubectl replace -f /tmp/secrets.with.values.yaml
sleep 120

# Verify that CP pods are running on the source
for i in {1..10}; do
   non_healthy_controllers=$(kubectl get pods -A | 
           grep -E "capi-kubeadm-bootstrap-|capi-kubeadm-control-plane-|capi-|capm3-|metal3" | grep -vc 'Running')
   if [ "${non_healthy_controllers}" -eq 0 ]; then
       break
   fi
   if [[ "${i}" -ge 10 ]]; then
      echo "The following controllers are not upgraded are not upgrade on the source cluster"
      kubectl get pods -A | grep -E "capi-kubeadm-bootstrap-|capi-kubeadm-control-plane-|capi-|capm3-|metal3" | grep -v Running | awk '{{print $2}}'
      exit 1
   fi
      sleep 10
done
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
#                       Target cluster: Upgrade Ironic
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
point_to_target_cluster
# shellcheck disable=SC2034
IRONIC_IMAGE_TAG=master
kubectl scale deploy metal3-ironic -n metal3 --replicas 0
sleep 120
# Upgrade containers that use ironic image
for container in mariadb ironic-api ironic-dnsmasq ironic-conductor ironic-log-watch;do
   kubectl set image deploy metal3-ironic \
   "${container}"=quay.io/metal3-io/ironic:"${IRONIC_IMAGE_TAG}" -n "${NAMESPACE}"
done

# Upgrade containers that use ironic-inspector image
for container in ironic-inspector httpd-reverse-proxy ironic-inspector-log-watch; do
   kubectl set image deploy metal3-ironic \
   "${container}"=quay.io/metal3-io/ironic-inspector:"${IRONIC_IMAGE_TAG}" -n "${NAMESPACE}"
done
kubectl scale deploy metal3-ironic -n metal3 --replicas 1

sleep 300
updated_ironic_image_count=$(kubectl get deployments metal3-ironic -n "${NAMESPACE}" -o json |
  jq '.spec.template.spec.containers[].image' | grep -c "${IRONIC_IMAGE_TAG}")

if [ "${updated_ironic_image_count}" -lt "${NUM_IRONIC_IMAGES}" ]; then
 echo "PodInitializing of the Ironic pod not completed in 5 minutes"
  exit 1
fi
# Check if old and new ironic pods are running together, wait until the old terminates
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

# Check that upgraded ironic containers are running
for wait in {1..12}; do
  not_running_containers_count=$(kubectl get "${ironic_pod}" -n "${NAMESPACE}" -o json | 
	  jq '.status.containerStatuses[].ready' | grep -ic false)
  if [ "${not_running_containers_count}" == "0" ]; then break; fi
  if [ "${wait}" -ge 12 ]; then
    echo "some of the ironic containers are not running"
    kubectl get "${ironic_pod}" -n "${NAMESPACE}" -o json |
        jq '.status.containerStatuses[]| select(.ready==false)|.name'
    exit 1
  fi
  sleep 10
done

# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
#                       Target cluster: Upgrade K8S version and node image
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
# set k8s version to upgrade to
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

# Upgrade node image and k8s version of CP nodes
point_to_target_cluster
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
echo "Successfully upgraded k8s version and node image of 3 CP nodes"

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

# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
#                       source cluster: re-pivot and cleanup
# ---------- ---------- ---------- ---------- ---------- ---------- ---------- ----------
point_to_management_cluster
# Pivot back
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/pivoting" || exit
make repivoting
popd || exit

deprovision_cluster
wait_for_cluster_deprovisioned
set +x
