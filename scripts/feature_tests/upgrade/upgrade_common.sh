#!/bin/bash

export NAMESPACE=${NAMESPACE:-"metal3"}
export CLUSTER_NAME=${CLUSTER_NAME:-"test1"}

export IMAGE_OS=${IMAGE_OS:-"Ubuntu"}
export IMAGE_USERNAME=${IMAGE_USERNAME:-"metal3"}
export KUBERNETES_VERSION=${KUBERNETES_VERSION:-"v1.18.0"}
export KUBERNETES_BINARIES_VERSION=${KUBERNETES_BINARIES_VERSION:-"v1.18.0"}
export UPGRADED_K8S_VERSION_1=${UPGRADED_K8S_VERSION_1:-"v1.18.1"}
export UPGRADED_K8S_VERSION_2=${UPGRADED_K8S_VERSION_2:-"v1.18.2"}
export UPGRADED_BINARY_VERSION=${UPGRADED_BINARY_VERSION:-"v1.18.1"}

export CLUSTER_APIENDPOINT_IP=${CLUSTER_APIENDPOINT_IP:-"192.168.111.249"}
export NUM_NODES=${NUM_NODES:-"4"}
export NUM_IRONIC_IMAGES=${NUM_IRONIC_IMAGES:-"5"}

export IMAGE_RAW_URL="http://172.22.0.1/images/${IMAGE_RAW_NAME}"
export IMAGE_RAW_CHECKSUM="http://172.22.0.1/images/${IMAGE_RAW_NAME}.md5sum"

export CAPM3PATH=${CAPM3PATH:-"/home/${USER}/go/src/github.com/metal3-io/cluster-api-provider-metal3"}

function generate_metal3MachineTemplate() {
    NAME="${1}"
    CLUSTER_UID="${2}"
    Metal3MachineTemplate_OUTPUT_FILE="${3}"
    CAPM3_ALPHA_VERSION="${4}"
    CAPI_ALPHA_VERSION="${5}"
    TEMPLATE_NAME="${6}"

echo "
apiVersion: infrastructure.cluster.x-k8s.io/${CAPM3_ALPHA_VERSION}
kind: Metal3MachineTemplate
metadata:
  name: ${NAME}
  namespace: metal3
  ownerReferences:
  - apiVersion: cluster.x-k8s.io/${CAPI_ALPHA_VERSION}
    kind: Cluster
    name: test1
    uid: ${CLUSTER_UID}
spec:
  template:
    spec:
      dataTemplate:
        name: ${TEMPLATE_NAME}
      image:
        checksum: ${IMAGE_RAW_CHECKSUM}
        checksumType: md5
        format: raw
        url: ${IMAGE_RAW_URL}
" >"${Metal3MachineTemplate_OUTPUT_FILE}"
}

function set_number_of_master_node_replicas() {
    export NUM_OF_MASTER_REPLICAS="${1}"
}

function set_number_of_worker_node_replicas() {
    export NUM_OF_WORKER_REPLICAS="${1}"
}

function provision_controlplane_node() {
    pushd "${METAL3_DEV_ENV_DIR}" || exit
    echo "Provisioning a controlplane node...."
    bash ./scripts/provision/cluster.sh
    bash ./scripts/provision/controlplane.sh
    popd || exit
}

function provision_worker_node() {
    pushd "${METAL3_DEV_ENV_DIR}" || exit
    echo "Provisioning a worker node...."
    bash ./scripts/provision/worker.sh
    popd || exit
}

function deprovision_cluster() {
    pushd "${METAL3_DEV_ENV_DIR}" || exit
    echo "Deprovisioning the cluster...."
    bash ./scripts/deprovision/cluster.sh
    popd || exit
}

function wait_for_cluster_deprovisioned() {
    echo "Waiting for cluster to be deprovisioned"
    for i in {1..3600}; do
        cluster_count=$(kubectl get clusters -n metal3 2>/dev/null | awk 'NR>1' | wc -l)
        if [[ "${cluster_count}" -eq "0" ]]; then
            ready_bmhs=$(kubectl get bmh -n metal3 | awk 'NR>1' | grep -c 'ready')
            if [[ "${ready_bmhs}" -eq "${NUM_NODES}" ]]; then
                echo ''
                echo "Successfully deprovisioned the cluster"
                break
            fi
        else
            echo -n "-"
        fi
        sleep 10
    done
}

function deploy_workload_on_workers() {
    echo "Deploy workloads on workers"
    # Deploy workloads
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-1-deployment
spec:
  replicas: 10
  selector:
    matchLabels:
      app: workload-1
  template:
    metadata:
      labels:
        app: workload-1
    spec:
      containers:
      - name: nginx
        image: nginx
EOF

    echo "Waiting for workloads to be ready"
    for i in {1..1800}; do
        workload_replicas=$(kubectl get deployments workload-1-deployment \
            -o json | jq '.status.readyReplicas')
        if [[ "$workload_replicas" == "10" ]]; then
            echo ''
            echo "Successfully deployed workloads across the cluster"
            break
        fi
        echo -n "*"
        sleep 10
        if [[ "${i}" -ge 1800 ]]; then
            log_error " Workload failed to be deployed on the cluster"
            deprovision_cluster
            wait_for_cluster_deprovisioned
            break
        fi
    done
}

function manage_node_taints() {
    kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | \
    jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml

    # Enable workload on masters
    # untaint all masters (one workers also gets untainted, doesn't matter):
    kubectl --kubeconfig=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml taint nodes --all node-role.kubernetes.io/master-
}

function start_logging() {
    log_file="${1}"
    log_file+=$(date +".%Y.%m.%d-%T-upgrade.result.txt")

    echo "${log_file}"

    exec > >(tee /tmp/"${log_file}")
}

function log_test_result() {
    test_case_file="${1}"
    test_result="${2}" # pass or fail

    if [ "${test_result}" == "pass" ]; then
        echo "Test case ${test_case_file} has passed" >>/tmp/"$(date +%Y.%m.%d_upgrade.result.txt)"
    elif [ "${test_result}" == "fail" ]; then
        echo "Test case ${test_case_file} has failed" >>/tmp/"$(date +%Y.%m.%d_upgrade.result.txt)"
    else
        echo "Unknown result for Test case ${test_case_file}" >>/tmp/"$(date +%Y.%m.%d_upgrade.result.txt)"
    fi
}

function log_error() {
    message="Error: ${1}"
    echo "${message}"
    logger -s "${message}"
}

# Using the VIP, verify that initial CP node is provisioned | no need to check start of the process.
function controlplane_is_provisioned() {
    echo "Waiting for provisioning of controlplane node to complete"

    for i in {1..3600}; do
        kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | \
          jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml
        kubectl --kubeconfig=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml version /dev/null 2>&1
        # shellcheck disable=SC2181
        if [[ "$?" == '0' ]]; then
            CP_NODE_NAME=$(kubectl --kubeconfig=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml get nodes -o json | jq '.items[0].metadata.name')
            echo "Successfully provisioned a controlplane node: ${CP_NODE_NAME}"
            break
        else
            echo -n "-"
        fi
        sleep 10
        if [[ "${i}" -ge 1800 ]]; then
            log_error "Controlplane provisioning took longer than expected."
            break
        fi
    done

}
# Using the VIP, verify that required replicas of CP are present
function controlplane_has_correct_replicas() {
    replicas="${1}"
    echo "Waiting for all replicas of controlplane node"
    for i in {1..3600}; do
        kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | \
          jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml
        cp_replicas=$(kubectl --kubeconfig=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml get nodes |
            awk 'NR>1' | grep -c master)
        if [[ "${cp_replicas}" == "${replicas}" ]]; then
            echo "Successfully provisioned controlplane replica nodes"
            break
        else
            echo -n "+"
        fi
        sleep 10
        if [[ "${i}" -ge 1800 ]]; then
            log_error "Controlplane replicas not provisioned in expected time frame"
            break
        fi
    done

}
# Using the VIP verify that a worker has joined the cluster
function worker_has_correct_replicas() {
    replicas="${1}"
    wr_replicas=0
    if [[ "${replicas}" -eq 0 ]]; then
      echo "Waiting for all replicas of worker nodes to leave the cluster"
    else
      echo "Waiting for all replicas of worker nodes to join the cluster"
    fi

    for i in {1..1800}; do
        wr_replicas=$(kubectl get bmh -n metal3 | grep -i provisioned | grep -c worker)
        if [[ "${replicas}" -eq 0 ]]; then
            if [[ "${wr_replicas}" -eq "${replicas}" ]]; then
                echo "Expected worker replicas have left the cluster"
                break
            fi
        elif [[ "${wr_replicas}" -eq "${replicas}" ]]; then
            for ind in {1..1800}; do
                kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | \
                jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml
                wr_nodes=$(kubectl --kubeconfig=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml get nodes |
                    awk 'NR>1' | grep -vc master)
                if [[ "${wr_nodes}" -eq "${replicas}" ]]; then
                    echo "Expected worker replicas have joined the cluster"
                    break 2
                fi
                sleep 10
            done
        else
            echo -n "*"
        fi
        sleep 10
        if [[ "${i}" -ge 1800 || "${ind}" -ge 1800 ]]; then
          if [[ "${replicas}" -eq 0 ]]; then
            log_error "Time out while waiting for workers to leave the cluster"
          else
            log_error "Time out while waiting for workers to join the cluster"
          fi
          break
        fi
    done

}
# From the developer machine, verify that new image is being used
function cp_nodes_using_new_bootDiskImage() {
    replicas="${1}"
    echo "Waiting for all CP nodes to to use the new boot disk image"
    for i in {1..3600}; do
        cp_replicas=$(kubectl get bmh -n metal3 | grep -i provisioned |
            grep -c 'new-controlplane-image')
        if [[ "${cp_replicas}" == "${replicas}" ]]; then
            echo "All CP nodes provisioned with a new boot disk image"
            break
        else
            echo -n "*+"
        fi
        sleep 10
        if [[ "${i}" -ge 1800 ]]; then
            log_error "Time out while waiting for CP nodes to be provisioned \
            with a new boot disk image"
            break
        fi
    done

}
# From the developer machine, verify that a number of nodes are freed (ready state)
function wr_nodes_using_new_bootDiskImage() {
    replicas="${1}"
    echo "Waiting for all worker nodes to use the new boot disk image"
    for i in {1..3600}; do
        worker_replicas=$(kubectl get bmh -n metal3 | grep -i provisioned |
            grep -c 'new-workers-image')
        if [[ "${worker_replicas}" == "${replicas}" ]]; then
            echo "All worker nodes provisioned with a new boot disk image"
            break
        else
            echo -n "*-"
        fi
        sleep 10
        if [[ "${i}" -ge 1800 ]]; then
            log_error "Time out while waiting for worker nodes to be provisioned\
             with a new boot disk image"
            break
        fi
    done

}
# From the developer machine, verify that a number of nodes are freed (ready state)
function expected_free_nodes() {
    node_count="${1}"
    echo "Waiting for original nodes to be freed"
    for i in {1..3600}; do
        released_nodes=$(kubectl get bmh -n metal3 | awk '{{print $3}}' |
            grep -c 'ready')
        if [[ "${released_nodes}" == "${node_count}" ]]; then
            echo "Original nodes are released"
            break
        else
            echo -n "**"
        fi
        sleep 10
        if [[ "${i}" -ge 1800 ]]; then
            log_error "Time out while waiting for original nodes to be released"
            break
        fi
    done

}

# Scale up or down workers
function scale_workers_to() {
    scale_to="${1}"
    echo "Scaling worker nodes to replica of ${scale_to}"
    kubectl get machinedeployment -n metal3 test1 -o json |
        jq '.spec.replicas='"${scale_to}"'' | kubectl apply -f-
}
# Scale up or down controlplane nodes
function scale_controlplane_to() {
    scale_to="${1}"
    echo "Scaling controlplane nodes to replica of ${scale_to}"
    kubectl get kcp -n metal3 test1 -o json |
        jq '.spec.replicas='"${scale_to}"'' | kubectl apply -f-
}
function apply_cni() {
    kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | \
    jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml

    kubectl --kubeconfig=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml \
    apply -f https://docs.projectcalico.org/manifests/calico.yaml
}

function cleanup_clusterctl_configuration() {
    # Delete old environment and create new one
    rm -rf /tmp/cluster-api-clone
    mkdir /tmp/cluster-api-clone

    # clean up if previous test has failed.
    rm -rf /home/"${USER}"/.cluster-api/overrides/cluster-api/v0.3.6
    rm -rf /home/"${USER}"/.cluster-api/overrides/bootstrap-kubeadm/v0.3.6
    rm -rf /home/"${USER}"/.cluster-api/overrides/control-plane-kubeadm/v0.3.6
    rm -rf /home/"${USER}"/.cluster-api/overrides/infrastructure-metal3/v0.3.6

    echo '' >/home/"${USER}"/.cluster-api/clusterctl.yaml
}

function create_clusterctl_configuration() {
cat <<EOF >/home/"${USER}"/.cluster-api/clusterctl.yaml
providers:
  - name: cluster-api
    url: /home/$USER/.cluster-api/overrides/cluster-api/v0.3.6/core-components.yaml
    type: CoreProvider
  - name: kubeadm
    url: /home/$USER/.cluster-api/overrides/bootstrap-kubeadm/v0.3.6/bootstrap-components.yaml
    type: BootstrapProvider
  - name: kubeadm
    url: /home/$USER/.cluster-api/overrides/control-plane-kubeadm/v0.3.6/control-plane-components.yaml
    type: ControlPlaneProvider
  - name: metal3
    url: /home/$USER/.cluster-api/overrides/infrastructure-metal3/v0.3.6/infrastructure-components.yaml
    type: InfrastructureProvider
EOF

# At first we install "v0.3.0" for which we need to move this
# to the CAPM3PATH repo root folder
#
# For the upgrade we need to do two things
# 1. copy v0.3.0 folder to v0.3.6
# 2. update $HOME/.cluster-api/clusterctl.yaml accordingly
cat <<EOF >clusterctl-settings-metal3.json
{
   "name": "infrastructure-metal3",
    "config": {
      "componentsFile": "infrastructure-components.yaml",
      "nextVersion": "v0.3.2"
    }
}
EOF

    mv clusterctl-settings-metal3.json "${CAPM3PATH}/clusterctl-settings.json"

}

function makeCrdChanges() {
    # Make changes on CRDs
    sed -i 's/\bma\b/ma2020/g' \
        /home/"${USER}"/.cluster-api/overrides/cluster-api/v0.3.6/core-components.yaml
    sed -i 's/singular: kubeadmconfig/singular: kubeadmconfig2020/' \
        home/"${USER}"/.cluster-api/overrides/bootstrap-kubeadm/v0.3.6/bootstrap-components.yaml
    sed -i 's/kcp/kcp2020/' \
        /home/"${USER}"/.cluster-api/overrides/control-plane-kubeadm/v0.3.6/control-plane-components.yaml
    sed -i 's/\bm3c\b/m3c2020/g' \
        /home/"${USER}"/.cluster-api/overrides/infrastructure-metal3/v0.3.6/infrastructure-components.yaml

}

function createNextVersionControllers() {
    # Create a new version
    cp -r /home/"${USER}"/.cluster-api/overrides/cluster-api/v0.3.0 \
        /home/"${USER}"/.cluster-api/overrides/cluster-api/v0.3.6
    cp -r /home/"${USER}"/.cluster-api/overrides/bootstrap-kubeadm/v0.3.0 \
        /home/"${USER}"/.cluster-api/overrides/bootstrap-kubeadm/v0.3.6
    cp -r /home/"${USER}"/.cluster-api/overrides/control-plane-kubeadm/v0.3.0 \
        /home/"${USER}"/.cluster-api/overrides/control-plane-kubeadm/v0.3.6
    cp -r /home/"${USER}"/.cluster-api/overrides/infrastructure-metal3/v0.3.2 \
        /home/"${USER}"/.cluster-api/overrides/infrastructure-metal3/v0.3.6

}

function buildClusterctl() {
    git clone https://github.com/kubernetes-sigs/cluster-api.git /tmp/cluster-api-clone
    pushd /tmp/cluster-api-clone || exit
    make clusterctl
    sudo mv bin/clusterctl /usr/local/bin

    # create required configuration files
cat <<EOF >clusterctl-settings.json
{
  "providers": [ "cluster-api", "bootstrap-kubeadm", "control-plane-kubeadm"]
}
EOF
    popd || exit
}

function verify_kubernetes_version_upgrade() {
    expected_k8s_version=${1}
    expected_nodes=${2}
    echo "Waiting for all nodes to be upgraded to ${expected_k8s_version}"

    for i in {1..3600}; do
        kubectl get secrets "${CLUSTER_NAME}"-kubeconfig -n "${NAMESPACE}" -o json | \
          jq -r '.data.value'| base64 -d > /tmp/kubeconfig-"${CLUSTER_NAME}".yaml
        upgraded_cp=$(kubectl --kubeconfig=/tmp/kubeconfig-"${CLUSTER_NAME}".yaml get nodes | awk 'NR>1' | grep -c "${expected_k8s_version}")
        if [[ "${upgraded_cp}" == "${expected_nodes}" ]]; then
            echo "Upgrade of Kubernetes version of all nodes done successfully"
            break
        else
            echo -n "*"
        fi
        sleep 10
        if [[ "${i}" -ge 1800 ]]; then
            log_error "Time out while waiting for upgrade of kubernetes version of all nodes"
            break
        fi
    done

}
