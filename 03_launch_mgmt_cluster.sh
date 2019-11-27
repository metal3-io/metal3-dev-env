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
RUN_LOCAL_IRONIC_SCRIPT="${BMOPATH}/tools/run_local_ironic.sh"
CAPBMPATH="${M3PATH}/cluster-api-provider-baremetal"
KUSTOMIZE_FILE_PATH=${CAPBMPATH}/examples/provider-components/kustomization.yaml

BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
BMOBRANCH="${BMOBRANCH:-master}"
CAPBMREPO="${CAPBMREPO:-https://github.com/metal3-io/cluster-api-provider-baremetal.git}"

if [ "${V1ALPHA2_SWITCH}" == true ]; then
  CAPBMBRANCH="${CAPBMBRANCH:-v1alpha2}"
else
  CAPBMBRANCH="${CAPBMBRANCH:-master}"
fi

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

# Creates the overlay for kustomize to override the various settings
# needed for IPv6
function kustomize_ipv6_overlay() {
  overlay_path=$1
  cat <<EOF> "$overlay_path/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
configMapGenerator:
- behavior: merge
  literals:
  - PROVISIONING_IP=fd2e:6f44:5dd8:b856::2
  - DHCP_RANGE=fd2e:6f44:5dd8:b856::3,fd2e:6f44:5dd8:b856::ff
  - DEPLOY_KERNEL_URL=http://[fd2e:6f44:5dd8:b856::2]:6180/images/ironic-python-agent.kernel
  - DEPLOY_RAMDISK_URL=http://[fd2e:6f44:5dd8:b856::2]:6180/images/ironic-python-agent.initramfs
  - IRONIC_ENDPOINT=http://[fd2e:6f44:5dd8:b856::2]:6385/v1/
  - IRONIC_INSPECTOR_ENDPOINT=http://[fd2e:6f44:5dd8:b856::2]:5050/v1/
  - CACHEURL=http://[fd2e:6f44:5dd8:b856::1]/images
  name: ironic-bmo-configmap
resources:
- $(realpath --relative-to="$overlay_path" "$BMOPATH/deploy")
EOF
}

function kustomize_overlay() {
  overlay_path=$1
cat <<EOF> "$overlay_path/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- $(realpath --relative-to="$overlay_path" "$BMOPATH/deploy")
EOF
}

function launch_baremetal_operator() {
    pushd "${BMOPATH}"
    kustomize_overlay_path=$(mktemp -d bmo-XXXXXXXXXX)

    if [[ "${PROVISIONING_IPV6}" == "true" ]]
    then
      kustomize_ipv6_overlay "$kustomize_overlay_path"
    else
      kustomize_overlay "$kustomize_overlay_path"
    fi
    pushd "$kustomize_overlay_path"

    # Add custom images in overlay
    for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
       IMAGE=${!IMAGE_VAR}
       if [[ "$IMAGE" =~ "://" ]] ; then
         #shellcheck disable=SC2086
         IMAGE_NAME="${IMAGE##*/}:latest"
         LOCAL_IMAGE="192.168.111.1:5000/localimages/$IMAGE_NAME"
       fi

       OLD_IMAGE_VAR="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
       OLD_IMAGE=${!OLD_IMAGE_VAR}
       #shellcheck disable=SC2086
       kustomize edit set image $OLD_IMAGE=$LOCAL_IMAGE
     done
     popd

    if [ "${BMO_RUN_LOCAL}" = true ]; then
      touch bmo.out.log
      touch bmo.err.log
      kustomize build "$kustomize_overlay_path" | kubectl apply -f-
      kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
      ${RUN_LOCAL_IRONIC_SCRIPT}
      nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
    else
      kustomize build "$kustomize_overlay_path" | kubectl apply -f-
    fi

    rm -rf "$kustomize_overlay_path"
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
# Launch the cluster-api controller manager (v1alpha1) in the metal3 namespace.
#
function launch_cluster_api_provider_baremetal() {
    pushd "${CAPBMPATH}"

    if [ "${CAPBM_RUN_LOCAL}" == true ]; then
      touch capbm.out.log
      touch capbm.err.log
      make deploy
      if [ "${V1ALPHA2_SWITCH}" == true ]; then
        kubectl scale -n metal3 deployment.v1.apps capbm-controller-manager --replicas 0
      else
        kubectl scale statefulset cluster-api-provider-baremetal-controller-manager -n metal3 --replicas=0
      fi
      nohup make run >> capbm.out.log 2>> capbm.err.log &
    else
      make deploy
    fi
    popd
}

clone_repos

if [ "${V1ALPHA2_SWITCH}" == true ]; then
  if grep -q "namespace:*" "${KUSTOMIZE_FILE_PATH}"
  then
      sed -i '/namespace/c\namespace: metal3' "${KUSTOMIZE_FILE_PATH}"
  else
      echo 'namespace: metal3' >> "${KUSTOMIZE_FILE_PATH}"
  fi
fi

init_minikube
sudo su -l -c 'minikube start' "${USER}"
if [[ "${PROVISIONING_IPV6}" == "true" ]]; then
  sudo su -l -c 'minikube ssh "sudo ip -6 addr add '"${IPV6_ADDR_PREFIX}::2/64"' dev eth2"' "${USER}"
else
  sudo su -l -c 'minikube ssh sudo ip addr add 172.22.0.2/24 dev eth2' "${USER}"
fi

launch_baremetal_operator
apply_bm_hosts
launch_cluster_api_provider_baremetal
