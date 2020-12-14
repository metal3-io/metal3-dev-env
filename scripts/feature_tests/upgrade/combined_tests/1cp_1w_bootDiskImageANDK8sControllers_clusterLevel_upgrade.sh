#!/bin/bash
 
set -x
export CACHEURL=http://172.22.0.1/images
export DEPLOY_KERNEL_URL=http://172.22.0.2:6180/images/ironic-python-agent.kernel
export DEPLOY_RAMDISK_URL=http://172.22.0.2:6180/images/ironic-python-agent.initramfs
export DHCP_RANGE=172.22.0.10,172.22.0.100
export HTTP_PORT="6180"
export IRONIC_CACERT_FILE=/opt/metal3/certs/ca/tls.crt
export IRONIC_ENDPOINT=https://172.22.0.2:6385/v1/
export IRONIC_FAST_TRACK="true"
export IRONIC_INSPECTOR_ENDPOINT=https://172.22.0.2:5050/v1/
export PROVISIONING_INTERFACE=eth2
export IRONIC_INSPECTOR_URL=https://172.22.0.2:6385/v1/
export IRONIC_URL=https://172.22.0.2:6385/v1/

#export IRONIC_BASIC_AUTH=true
#export IRONIC_TLS_SETUP=true

export CAPM3RELEASE="v0.4.0"
export CAPIRELEASE="v0.3.12" 
export CAPIRELEASE_HARDCODED="v0.3.8"

export CAPM3_REL_TO_VERSION="v0.4.1"
export CAPI_REL_TO_VERSION="v0.3.14"

export IMAGE_OS=Centos

#set -ex

# shellcheck disable=SC2034
IRONIC_IMAGE_TAG=master # default = latest


METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/../../../../"
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/upgrade/upgrade_common.sh"

echo '' >~/.ssh/known_hosts

start_logging "${1}"
# Provision original nodes
set_number_of_master_node_replicas 3
set_number_of_worker_node_replicas 1

provision_controlplane_node

set_kubeconfig_towards_target_cluster

point_to_target_cluster
controlplane_has_correct_replicas 3

point_to_management_cluster

provision_worker_node
point_to_target_cluster
worker_has_correct_replicas 1

point_to_management_cluster

# Start pivoting
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/pivoting" || exit
make upgrading
popd || exit
sleep 120

point_to_target_cluster

# Untaint the masters
manage_node_taints
scale_controlplane_to 1
controlplane_has_correct_replicas 1
point_to_target_cluster # | Enable this once pivoting done | and remove the previous line
# ----------- upgrade ironic image ------
# Upgrade container images
for container in ironic-api ironic-dnsmasq ironic-httpd mariadb; do
  kubectl set image deployments metal3-ironic \
    $container=quay.io/metal3-io/ironic:"${IRONIC_IMAGE_TAG}" -n "${NAMESPACE}"
done
kubectl set image deployments metal3-ironic \
  ironic-inspector=quay.io/metal3-io/ironic-inspector:"${IRONIC_IMAGE_TAG}" -n "${NAMESPACE}"

# Delete Both old and new pods to avoid port conflict when both scheduled on the same node
#kubectl get pods -n metal3 -o name | xargs kubectl delete -n metal3
kubectl scale deployment -n metal3 metal3-ironic --replicas 0 
kubectl scale deployment -n metal3 metal3-ironic --replicas 1

sleep 120 # wait until images are downloaded
updated_ironic_image_count=$(kubectl get deployments metal3-ironic -n "${NAMESPACE}" -o json |
  jq '.spec.template.spec.containers[].image' | grep -c "${IRONIC_IMAGE_TAG}")

if [ "${updated_ironic_image_count}" -lt "${NUM_IRONIC_IMAGES}" ]; then
 echo "All ironic images are not updated properly"
  exit 1
fi

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
for container in ironic-api ironic-inspector ironic-dnsmasq ironic-httpd mariadb; do
  running_containers_count=$(
    kubectl get "${ironic_pod}" -n "${NAMESPACE}" -o json |
      jq ".status.containerStatuses[] | select(.name == \"${container}\") | .state" |
      grep -ic running
  )
  if [ "${running_containers_count}" -eq 0 ]; then
    sleep 30
    running_containers_count_retry=$(
      kubectl get "${ironic_pod}" -n "${NAMESPACE}" -o json |
        jq ".status.containerStatuses[] | select(.name == \"${container}\") | .state" |
        grep -ic running
      )
    if [ "${running_containers_count_retry}" -eq 0 ]; then
      echo "Upgrade of ironic image for container ${container} has failed"
      exit 1
    fi
  fi
done
# ----------- upgrade boot disk image and kubernetes version ------
echo "Create a new metal3MachineTemplate with new node image for both \
controlplane and worker nodes"
cp_Metal3MachineTemplate_OUTPUT_FILE="/tmp/cp_new_image.yaml"
wr_Metal3MachineTemplate_OUTPUT_FILE="/tmp/wr_new_image.yaml"
CLUSTER_UID=$(kubectl get clusters -n "${NAMESPACE}" test1 -o json | jq '.metadata.uid' |
  cut -f2 -d\")
generate_metal3MachineTemplate "${CLUSTER_NAME}-new-controlplane-image" \
  "${CLUSTER_UID}" "${cp_Metal3MachineTemplate_OUTPUT_FILE}" \
  "${CAPM3_VERSION}" "${CAPI_VERSION}" \
  "${CLUSTER_NAME}-controlplane-template"
generate_metal3MachineTemplate "${CLUSTER_NAME}-new-workers-image" \
  "${CLUSTER_UID}" "${wr_Metal3MachineTemplate_OUTPUT_FILE}" \
  "${CAPM3_VERSION}" "${CAPI_VERSION}" \
  "${CLUSTER_NAME}-workers-template"

kubectl get kubeadmcontrolplane -n "${NAMESPACE}" test1 -o json |
  jq ".spec.infrastructureTemplate.name=\"test1-new-controlplane-image\" |
  .spec.version=\"${UPGRADED_K8S_VERSION_2}\"" |
  kubectl apply -f-
sleep 10
kubectl get machinedeployment -n "${NAMESPACE}" test1 -o json |
  jq ".spec.strategy.rollingUpdate.maxSurge=1|.spec.strategy.rollingUpdate.maxUnavailable=1 |
  .spec.template.spec.version=\"${UPGRADED_K8S_VERSION_2}\"" |
  kubectl apply -f-
sleep 10
kubectl get machinedeployment -n "${NAMESPACE}" test1 -o json |
 jq '.spec.template.spec.infrastructureRef.name="test1-new-workers-image"' |
  kubectl apply -f-

kubectl apply -f "${cp_Metal3MachineTemplate_OUTPUT_FILE}"
kubectl apply -f "${wr_Metal3MachineTemplate_OUTPUT_FILE}"

# Verify new boot disk image usage
cp_nodes_using_new_bootDiskImage 1
wr_nodes_using_new_bootDiskImage 1

# Untaint the masters | after the upgrade
manage_node_taints

# Verify nodes are freed
expected_free_nodes 2

# verify that extra nodes are not removed
point_to_target_cluster
controlplane_has_correct_replicas 1
worker_has_correct_replicas 1

# ----------- upgrade controlplane components ---------------
point_to_target_cluster
# Done: Assert all controllers except metal3 related are upgraded
# In case secrets are emptied during the upgrade
#kubectl get secrets -n capm3-system -o json | jq '.items[]|del(.metadata|.managedFields,.uid,.resourceVersion)' > /tmp/secrets.with.values.yaml

cleanup_clusterctl_configuration

buildClusterctl

# Install initial version folder structure
pushd /tmp/cluster-api-clone || exit
git checkout "${CAPIRELEASE}"
./cmd/clusterctl/hack/create-local-repository.py
popd || exit

create_clusterctl_configuration
createNextVersionControllers # did not work the first time ?

makeCrdChanges

# show upgrade plan
clusterctl upgrade plan
# do upgrade
clusterctl upgrade plan | grep "upgrade apply" | xargs | xargs clusterctl 
sleep 60
#kubectl replace -f  /tmp/secrets.with.values.yaml
sleep 60
#kubectl get pods -n capm3-system -o name| grep capm3-baremetal-operator | xargs kubectl delete -n capm3-system

# Verify upgrade | requires a second view
upgraded_controllers_capi_count=$(kubectl get deploy -n capi-system capi-controller-manager -o yaml | grep -c 'cluster-api-controller:v0.3.14')
upgraded_bootstrap_count=$(kubectl get deploy -n capi-kubeadm-bootstrap-system capi-kubeadm-bootstrap-controller-manager -o yaml | grep -c 'kubeadm-bootstrap-controller:v0.3.14')
#upgraded_controllers_kcp_count=$(kubectl get deploy -n capi-kubeadm-control-plane-system -o yaml | grep -c 'kubeadm-control-plane-controller:v0.3.14')

# Delete next three lines
#upgraded_controllers_kcp_count=$(kubectl explain kcp | grep -c "upgradedKubeadmControlPlane ")
#upgraded_bootstrap_count=$(kubectl explain KubeadmConfig | grep -c 'upgradedKubeadmConfig ')
#upgraded_capi_controller_count=$(kubectl api-resources | grep -c m3c2020)

if [ "${upgraded_controllers_capi_count}" -ne 1 ]; then
  log_error "Failed to upgrade cluster-api and controlplane components"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi
if [ "${upgraded_bootstrap_count}" -ne 1 ]; then
  log_error "Failed to upgrade control-plane-kubeadm components"
  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
  exit 1
fi
# ======= approved above this line =====
#if [ "${upgraded_capm3_controller_count}" -ne 1 ]; then
#  log_error "Failed to upgrade infrastructure components"
#  log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
#  exit 1
#fi

# Next blocks require further verification | secrets seems to be missing
# specifically, at what point should this be done
for i in {1..10}; do
  non_healthy_controllers=$(kubectl get pods -A | grep -E "capm3-system|capi-kubeadm|metal3" |
    grep -vc 'Running')
  if [ "${non_healthy_controllers}" -eq 0 ]; then
   break
  fi
  if [[ "${i}" -ge 10 ]]; then
   log_error "Some of the upgraded controlplane components are not healthy"
    log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "fail"
    exit 1
  fi
  sleep 10
done

# Report result
echo "Boot disk upgrade of both controlplane and worker nodes has succeeded."
log_test_result "1cp_1w_bootDiskImageANDK8sCotrollers_clusterLevel_upgrade.sh" "pass"

# Scale up so that we have 4 bmh resources when re-pivoting
point_to_target_cluster # keep it here
# The following would fail due to the following error.
# Error from server: conversion webhook for controlplane.cluster.x-k8s.io/v1alpha3, Kind=KubeadmControlPlane failed: the server could not find the requested resource 
scale_controlplane_to 3
controlplane_has_correct_replicas 3

# Pivot back
point_to_management_cluster
pushd "${METAL3_DEV_ENV_DIR}/scripts/feature_tests/pivoting" || exit
make repivoting
popd || exit

sleep 120
# Test cleanup
cleanup_clusterctl_configuration
deprovision_cluster
#wait_for_cluster_deprovisioned # No need to wait

set -x
