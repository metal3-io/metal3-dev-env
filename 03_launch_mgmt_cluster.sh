#!/bin/bash
set -xe

source utils/logging.sh
source utils/common.sh

eval "$(go env)"

M3PATH="${GOPATH}/src/github.com/metal3-io"
BMOPATH="${M3PATH}/baremetal-operator"

function clone_repos() {
    if [ ! -d ${M3PATH} ] ; then
        mkdir -p ${M3PATH}
    fi

    if [ ! -d ${BMOPATH} ] ; then
        pushd ${M3PATH}
        git clone https://github.com/metal3-io/baremetal-operator.git
        popd
    fi
    pushd ${BMOPATH}
    #git checkout master
    #git pull -r
    popd
}

function launch_minikube() {
    minikube start --vm-driver kvm2
    # The interface doesn't appear in the minikube VM with --live,
    # so just attach it and make it reboot.
    sudo virsh attach-interface --domain minikube \
        --model virtio --source provisioning \
        --type network --config
    minikube stop
    minikube start --vm-driver kvm2
}

function launch_baremetal_operator() {
    DEPLOY_DIR=${BMOPATH}/deploy
    echo '{ "kind": "Namespace", "apiVersion": "v1", "metadata": { "name": "metal3", "labels": { "name": "metal3" } } }' | kubectl apply -f -
    kubectl apply -f ${DEPLOY_DIR}/service_account.yaml -n metal3
    kubectl apply -f ${DEPLOY_DIR}/role.yaml -n metal3
    kubectl apply -f ${DEPLOY_DIR}/role_binding.yaml
    kubectl apply -f ${DEPLOY_DIR}/crds/metal3_v1alpha1_baremetalhost_crd.yaml
    kubectl apply -f ${DEPLOY_DIR}/operator.yaml -n metal3
}

function list_nodes() {
    # Includes -machine and -machine-namespace
    cat $NODES_FILE | \
        jq '.nodes[] | {
           name,
           driver,
           address:.driver_info.ipmi_address,
           port:.driver_info.ipmi_port,
           user:.driver_info.ipmi_username,
           password:.driver_info.ipmi_password,
           mac: .ports[0].address
           } |
           .name + " " +
           .driver + "://" + .address + (if .port then ":" + .port else "" end)  + " " +
           .user + " " + .password + " " + .mac' \
       | sed 's/"//g'
}

function make_bm_hosts() {
    while read name address user password mac; do
        go run ${BMOPATH}/cmd/make-bm-worker/main.go \
           -address "$address" \
           -password "$password" \
           -user "$user" \
           -boot-mac "$mac" \
           "$name"
    done
}

function apply_bm_hosts() {
    list_nodes | make_bm_hosts > bmhosts_crs.yaml
    kubectl apply -f bmhosts_crs.yaml -n metal3
}

clone_repos
launch_minikube
launch_baremetal_operator
apply_bm_hosts
