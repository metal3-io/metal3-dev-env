#!/bin/bash
set -xe

source utils/logging.sh
source utils/common.sh

eval "$(go env)"

BMOPATH="${GOPATH}/src/github.com/metal3-io/baremetal-operator"

if [ ! -d ${BMOPATH} ] ; then
    mkdir -p ${GOPATH}/src/github.com/metal3-io/
    pushd ${BMOPATH}
    git clone https://github.com/metal3-io/baremetal-operator.git
    popd
fi
pushd ${BMOPATH}
#git checkout master
#git pull -r
popd

minikube start --vm-driver kvm2

DEPLOY_DIR=${BMOPATH}/deploy
echo '{ "kind": "Namespace", "apiVersion": "v1", "metadata": { "name": "metal3", "labels": { "name": "metal3" } } }' | kubectl apply -f -
kubectl apply -f ${DEPLOY_DIR}/service_account.yaml -n metal3
kubectl apply -f ${DEPLOY_DIR}/role.yaml -n metal3
kubectl apply -f ${DEPLOY_DIR}/role_binding.yaml
kubectl apply -f ${DEPLOY_DIR}/crds/metal3_v1alpha1_baremetalhost_crd.yaml
kubectl apply -f ${DEPLOY_DIR}/operator.yaml -n metal3

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

list_nodes | make_bm_hosts > bmhosts_crs.yaml

kubectl apply -f bmhosts_crs.yaml -n metal3
