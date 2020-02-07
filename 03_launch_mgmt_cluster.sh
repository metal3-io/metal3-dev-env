#!/bin/bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh

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

BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"
BMOBRANCH="${BMOBRANCH:-master}"
CAPBMREPO="${CAPBMREPO:-https://github.com/metal3-io/cluster-api-provider-baremetal.git}"

if [ "${CAPI_VERSION}" == "v1alpha3" ]; then
  CAPBMBRANCH="${CAPBMBRANCH:-master}"
elif [ "${CAPI_VERSION}" == "v1alpha2" ]; then
  CAPBMBRANCH="${CAPBMBRANCH:-release-0.2}"
elif [ "${CAPI_VERSION}" == "v1alpha1" ]; then
  CAPBMBRANCH="${CAPBMBRANCH:-v1alpha1}"
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
        git clone "${BMOREPO}" "${BMOPATH}"
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
        git clone "${CAPBMREPO}" "${CAPBMPATH}"
        popd
    fi
    pushd "${CAPBMPATH}"
    git checkout "${CAPBMBRANCH}"
    git pull -r || true
    popd
}

# Modifies the images to use the ones built locally
function update_images(){
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
}

function kustomize_overlay_bmo() {
  overlay_path=$1
cat <<EOF> "$overlay_path/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
configMapGenerator:
- behavior: merge
  literals:
  - PROVISIONING_IP=$CLUSTER_PROVISIONING_IP
  - DHCP_RANGE=$CLUSTER_DHCP_RANGE
  - DEPLOY_KERNEL_URL=http://$CLUSTER_URL_HOST:6180/images/ironic-python-agent.kernel
  - DEPLOY_RAMDISK_URL=http://$CLUSTER_URL_HOST:6180/images/ironic-python-agent.initramfs
  - IRONIC_ENDPOINT=http://$CLUSTER_URL_HOST:6385/v1/
  - IRONIC_INSPECTOR_ENDPOINT=http://$CLUSTER_URL_HOST:5050/v1/
  - CACHEURL=http://$PROVISIONING_URL_HOST/images
  name: ironic-bmo-configmap
resources:
- $(realpath --relative-to="$overlay_path" "$BMOPATH/deploy")
EOF
}

function launch_baremetal_operator() {
    pushd "${BMOPATH}"
    kustomize_overlay_path=$(mktemp -d bmo-XXXXXXXXXX)

    kustomize_overlay_bmo "$kustomize_overlay_path"
    pushd "$kustomize_overlay_path"

    # Add custom images in overlay
    update_images
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

function kustomize_overlay_capbm() {
  overlay_path=$1
  provider_cmpt=$2
cat <<EOF> "$overlay_path/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: metal3
resources:
- $(realpath --relative-to="$overlay_path" "$provider_cmpt")
EOF
}


#
# Launch the cluster-api controller manager (v1alpha1) in the metal3 namespace.
#
function launch_cluster_api_provider_baremetal() {
    pushd "${CAPBMPATH}"
    kustomize_overlay_path=$(mktemp -d capbm-XXXXXXXXXX)


    if [ "${CAPI_VERSION}" == "v1alpha2" ] || \
      [ "${CAPI_VERSION}" == "v1alpha3" ]; then
      ./examples/generate.sh -f
      kustomize_overlay_capbm "$kustomize_overlay_path" \
        "$CAPBMPATH/examples/provider-components"
    elif [ "${CAPI_VERSION}" == "v1alpha1" ]; then
      make manifests
      cp "$CAPBMPATH/provider-components.yaml" \
        "${kustomize_overlay_path}/provider-components.yaml"
      kustomize_overlay_capbm "$kustomize_overlay_path" \
        "${kustomize_overlay_path}/provider-components.yaml"
    fi

    pushd "$kustomize_overlay_path"
    update_images
    popd
    kustomize build "$kustomize_overlay_path" | kubectl apply -f-

    rm -rf "$kustomize_overlay_path"

    if [ "${CAPBM_RUN_LOCAL}" == true ]; then
      touch capbm.out.log
      touch capbm.err.log
      if [ "${CAPI_VERSION}" == "v1alpha1" ]; then
        kubectl scale statefulset cluster-api-provider-baremetal-controller-manager -n metal3 --replicas=0
      elif [ "${CAPI_VERSION}" == "v1alpha2" ] || \
        [ "${CAPI_VERSION}" == "v1alpha3" ]; then
        kubectl scale -n metal3 deployment.v1.apps capbm-controller-manager --replicas 0
      fi
      nohup make run >> capbm.out.log 2>> capbm.err.log &
    fi
    popd
}


#
# Write out a clouds.yaml for this environment
#
function create_clouds_yaml() {
  sed -e "s/__CLUSTER_URL_HOST__/$CLUSTER_URL_HOST/g" clouds.yaml.template > clouds.yaml
}

clone_repos
create_clouds_yaml
init_minikube
sudo su -l -c 'minikube start' "${USER}"
if [[ "${PROVISIONING_IPV6}" == "true" ]]; then
  sudo su -l -c 'minikube ssh "sudo ip -6 addr add '"$CLUSTER_PROVISIONING_IP/$PROVISIONING_CIDR"' dev eth2"' "${USER}"
else
  sudo su -l -c "minikube ssh sudo ip addr add $CLUSTER_PROVISIONING_IP/$PROVISIONING_CIDR dev eth2" "${USER}"
fi

launch_baremetal_operator
apply_bm_hosts
launch_cluster_api_provider_baremetal
