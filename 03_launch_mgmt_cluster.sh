#!/bin/bash
set -xe

source utils/logging.sh
source utils/common.sh

eval "$(go env)"

if [ ! -d ${GOPATH}/src/github.com/metal3-io/baremetal-operator ] ; then
    mkdir -p ${GOPATH}/src/github.com/metal3-io/
    pushd ${GOPATH}/src/github.com/metal3-io/baremetal-operator
    git clone https://github.com/metal3-io/baremetal-operator.git
    popd
fi
pushd ${GOPATH}/src/github.com/metal3-io/baremetal-operator
git checkout master
git pull -r
popd

minikube start --vm-driver kvm2

DEPLOY_DIR=${GOPATH}/src/github.com/metal3-io/baremetal-operator/deploy
echo '{ "kind": "Namespace", "apiVersion": "v1", "metadata": { "name": "metal3", "labels": { "name": "metal3" } } }' | kubectl apply -f -
kubectl apply -f ${DEPLOY_DIR}/service_account.yaml -n metal3
kubectl apply -f ${DEPLOY_DIR}/role.yaml -n metal3
kubectl apply -f ${DEPLOY_DIR}/role_binding.yaml
kubectl apply -f ${DEPLOY_DIR}/crds/metal3_v1alpha1_baremetalhost_crd.yaml
kubectl apply -f ${DEPLOY_DIR}/operator.yaml -n metal3
