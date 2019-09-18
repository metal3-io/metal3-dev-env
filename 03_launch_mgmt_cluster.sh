#!/bin/bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

eval "$(go env)"
export GOPATH

# Environment variables
# M3PATH : Path to clone the metal3 dev env repo
# BMOPATH : Path to clone the baremetal operator repo
# CAPBMPATH: Path to clone the CAPI operator repo
#
# BMOREPO : Baremetal operator repository URL
# BMOBRANCH : Baremetal operator repository branch to checkout
# CAPBMREPO : CAPI operator repository URL
# CAPBMBRANCH : CAPI repository branch to checkout
# FORCE_REPO_UPDATE : discard existing directories
#
# BMO_RUN_LOCAL : run the baremetal operator locally (not in Kubernetes cluster)
# CAPBM_RUN_LOCAL : run the CAPI operator locally

M3PATH="${GOPATH}/src/github.com/metal3-io"
BMOPATH="${M3PATH}/baremetal-operator"
CAPBMPATH="${M3PATH}/cluster-api-provider-baremetal"

BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
BMOBRANCH="${BMOBRANCH:-master}"
CAPBMREPO="${CAPBMREPO:-https://github.com/metal3-io/cluster-api-provider-baremetal.git}"
CAPBMBRANCH="${CAPBMBRANCH:-master}"
FORCE_REPO_UPDATE="${FORCE_REPO_UPDATE:-false}"

BMO_RUN_LOCAL="${BMO_RUN_LOCAL:-false}"
CAPBM_RUN_LOCAL="${CAPBM_RUN_LOCAL:-false}"

function clone_repos() {
    mkdir -p "${M3PATH}"
    if [[ -d ${BMOPATH} && "${FORCE_REPO_UPDATE}" == "true" ]]; then
      rm -rf "${BMOPATH}"
    fi
    if [ ! -d "${BMOPATH}" ] ; then
        pushd "${M3PATH}"
        git clone "${BMOREPO}"
        popd
    fi
    pushd "${BMOPATH}"
    git checkout "${BMOBRANCH}"
    git pull -r || true
    popd
    if [[ -d "${CAPBMPATH}" && "${FORCE_REPO_UPDATE}" == "true" ]]; then
      rm -rf "${CAPBMPATH}"
    fi
    if [ ! -d "${CAPBMPATH}" ] ; then
        pushd "${M3PATH}"
        git clone "${CAPBMREPO}"
        popd
    fi
    pushd "${CAPBMPATH}"
    git checkout "${CAPBMBRANCH}"
    git pull -r || true
    popd
}


function launch_baremetal_operator() {
    pushd "${BMOPATH}"
    if [ "${BMO_RUN_LOCAL}" = true ]; then
      touch bmo.out.log
      touch bmo.err.log
      make deploy
      kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
      nohup make run >> bmo.out.log 2>>bmo.err.log &
    else
      make deploy
    fi
    popd
}


function make_bm_hosts() {
    while read -r name address user password mac; do
        go run "${BMOPATH}"/cmd/make-bm-worker/main.go \
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

#
# Launch the cluster-api controller manager in the metal3 namespace.
#
function launch_cluster_api() {
    pushd "${CAPBMPATH}"
    if [ "${CAPBM_RUN_LOCAL}" = true ]; then
      touch capbm.out.log
      touch capbm.err.log
      make deploy
      kubectl scale statefulset cluster-api-provider-baremetal-controller-manager -n metal3 --replicas=0
      nohup make run >> capbm.out.log 2>> capbm.err.log &
    else
      make deploy
    fi
    popd
}

clone_repos
minikube start
launch_baremetal_operator
apply_bm_hosts
launch_cluster_api
