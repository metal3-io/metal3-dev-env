#!/bin/bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh

if [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
  IRONIC_HOST="${CLUSTER_URL_HOST}"
  export IRONIC_HOST_IP="${CLUSTER_PROVISIONING_IP}"
else
  IRONIC_HOST="${PROVISIONING_URL_HOST}"
  export IRONIC_HOST_IP="${PROVISIONING_IP}"
fi

function clone_repos() {
    mkdir -p "${M3PATH}"
    if [[ -d "${BMOPATH}" && "${FORCE_REPO_UPDATE}" == "true" ]]; then
      rm -rf "${BMOPATH}"
    fi
    if [ ! -d "${BMOPATH}" ] ; then
      pushd "${M3PATH}"
      git clone "${BMOREPO}" "${BMOPATH}"
      popd
    fi
    pushd "${BMOPATH}"
    git fetch
    git checkout "${BMOBRANCH}"
    git pull -r || true
    popd

    if [[ -d "${CAPM3PATH}" && "${FORCE_REPO_UPDATE}" == "true" ]]; then
      rm -rf "${CAPM3PATH}"
    fi
    if [ ! -d "${CAPM3PATH}" ] ; then
      pushd "${M3PATH}"
      git clone "${CAPM3REPO}" "${CAPM3PATH}"
      popd
    fi
    pushd "${CAPM3PATH}"
    git fetch
    git checkout "${CAPM3BRANCH}"
    git pull -r || true
    popd
    #TODO Consider option to download prebaked clusterctl binary
    if [[ -d "${CAPIPATH}" && "${FORCE_REPO_UPDATE}" == "true" ]]; then
      rm -rf "${CAPIPATH}"
    fi
    if [ ! -d "${CAPIPATH}" ] ; then
      pushd "${M3PATH}"
      git clone "${CAPIREPO}" "${CAPIPATH}"
      popd
    fi
    pushd "${CAPIPATH}"
    git fetch
    git checkout "${CAPIBRANCH}"
    git pull -r || true
    popd

}

function patch_clusterctl(){
  pushd "${CAPM3PATH}"
  if [ -n "${CAPM3_LOCAL_IMAGE}" ]; then
    CAPM3_IMAGE_NAME="${CAPM3_LOCAL_IMAGE##*/}"
    export MANIFEST_IMG="${REGISTRY}/localimages/$CAPM3_IMAGE_NAME"
    export MANIFEST_TAG="latest"
    make set-manifest-image
  fi

  if [ -n "${BAREMETAL_OPERATOR_LOCAL_IMAGE}" ] && [ "${CAPI_VERSION}" != "v1alpha3" ]; then
    BMO_IMAGE_NAME="${BAREMETAL_OPERATOR_LOCAL_IMAGE##*/}"
    export MANIFEST_IMG_BMO="${REGISTRY}/localimages/$BMO_IMAGE_NAME"
    export MANIFEST_TAG_BMO="latest"
    make set-manifest-image-bmo
  fi

  make release-manifests
  rm -rf "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  mkdir -p "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  cp out/*.yaml "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  popd

}

# Modifies the images to use the ones built locally
function update_images(){
  for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}:latest"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"

    OLD_IMAGE_VAR="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
    # Strip the tag for image replacement
    OLD_IMAGE="${!OLD_IMAGE_VAR%:*}"
    #shellcheck disable=SC2086
    if [ -z "${CAPM3_LOCAL_IMAGE}" ]; then
      kustomize edit set image $OLD_IMAGE=$LOCAL_IMAGE
    fi
    eval "$OLD_IMAGE_VAR"="$LOCAL_IMAGE"
    export "${OLD_IMAGE_VAR?}"
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
  - PROVISIONING_INTERFACE=$CLUSTER_PROVISIONING_INTERFACE
  - PROVISIONING_CIDR=$PROVISIONING_CIDR
  - DHCP_RANGE=$CLUSTER_DHCP_RANGE
  - DEPLOY_KERNEL_URL=http://$IRONIC_HOST:6180/images/ironic-python-agent.kernel
  - DEPLOY_RAMDISK_URL=http://$IRONIC_HOST:6180/images/ironic-python-agent.initramfs
  - IRONIC_ENDPOINT=http://$IRONIC_HOST:6385/v1/
  - IRONIC_INSPECTOR_ENDPOINT=http://$IRONIC_HOST:5050/v1/
  - CACHEURL=http://$IRONIC_HOST/images
  - IRONIC_FAST_TRACK=false
  name: ironic-bmo-configmap
resources:
- $(realpath --relative-to="$overlay_path" "$BMO_CONFIG")
EOF
}


function deploy_kustomization() {
    kustomize_overlay_path=$(mktemp -d bmo-XXXXXXXXXX)
    kustomize_overlay_bmo "$kustomize_overlay_path"
    pushd "$kustomize_overlay_path"

    # Add custom images in overlay, and override the images with local ones
    update_images
    popd

    kustomize build "$kustomize_overlay_path" | kubectl apply -f-
    rm -rf "$kustomize_overlay_path"
}

function launch_baremetal_operator() {
    pushd "${BMOPATH}"

    if [ "${CAPI_VERSION}" != "v1alpha3" ]; then
      kubectl create namespace metal3
    else
      BMO_CONFIG="${BMOPATH}/deploy/default"
      deploy_kustomization
    fi

    if [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
      BMO_CONFIG="${BMOPATH}/ironic-deployment/keepalived"
      deploy_kustomization
    fi

    if [ "${EPHEMERAL_CLUSTER}" = kind ]; then
      ${RUN_LOCAL_IRONIC_SCRIPT}
    fi

    if [ "${BMO_RUN_LOCAL}" = true ] && [ "${CAPI_VERSION}" == "v1alpha3" ]; then
      touch bmo.out.log
      touch bmo.err.log
      kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
      nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
    fi

    rm -rf "$kustomize_overlay_path"
    popd
}

function launch_kind() {
  cat <<EOF | sudo su -l -c "kind create cluster --name kind --image=kindest/node:${KUBERNETES_VERSION} --config=- " "$USER"
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${REGISTRY}"]
      endpoint = ["http://${REGISTRY}"]
EOF
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
    pushd "${BMOPATH}"
    list_nodes | make_bm_hosts > bmhosts_crs.yaml
    kubectl apply -f bmhosts_crs.yaml -n metal3
    popd
}

function kustomize_overlay_capm3() {
  overlay_path=$1
  provider_cmpt=$2

  cat <<EOF> "$overlay_path/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- $(realpath --relative-to="$overlay_path" "$provider_cmpt")
EOF
}

#
# Launch the cluster-api provider.
#
function launch_cluster_api_provider_metal3() {
    pushd "${CAPM3PATH}"
    kustomize_overlay_path=$(mktemp -d capm3-XXXXXXXXXX)
    mkdir -p "${HOME}"/.cluster-api
    touch "${HOME}"/.cluster-api/clusterctl.yaml
    pushd "${CAPIPATH}"
    if ! [ -x "$(command -v clusterctl)" ]; then
      make clusterctl
    fi
    popd

    patch_clusterctl

    pushd "${CAPIPATH}"
    cd bin
    ./clusterctl init --infrastructure=metal3:"${CAPM3RELEASE}"  -v5
    popd

    rm -rf "$kustomize_overlay_path"

    if [ "${CAPM3_RUN_LOCAL}" == true ]; then
      touch capm3.out.log
      touch capm3.err.log
      kubectl scale -n metal3 deployment.v1.apps capm3-controller-manager --replicas 0
      nohup make run >> capm3.out.log 2>> capm3.err.log &
    fi

    if [ "${BMO_RUN_LOCAL}" == true ] && [ "${CAPI_VERSION}" != "v1alpha3" ]; then
      touch bmo.out.log
      touch bmo.err.log
      kubectl scale deployment capm3-metal3-baremetal-operator -n capm3-system --replicas=0
      nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
    fi

    popd
}


clone_repos

#
# Write out a clouds.yaml for this environment
#
function create_clouds_yaml() {
  sed -e "s/__CLUSTER_URL_HOST__/$CLUSTER_URL_HOST/g" clouds.yaml.template > clouds.yaml
  # To bind this into the ironic-client container we need a directory
  mkdir -p "${SCRIPTDIR}"/_clouds_yaml
  cp clouds.yaml "${SCRIPTDIR}"/_clouds_yaml/
}

create_clouds_yaml

if [ "${EPHEMERAL_CLUSTER}" == "kind" ]; then
  launch_kind
else
  init_minikube

  sudo su -l -c 'minikube start' "${USER}"
  if [[ -n "${MINIKUBE_BMNET_V6_IP}" ]]; then
	  sudo su -l -c "minikube ssh -- sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0" "${USER}"
	  sudo su -l -c "minikube ssh -- sudo ip addr add $MINIKUBE_BMNET_V6_IP/64 dev eth3" "${USER}"
  fi
  if [[ "${PROVISIONING_IPV6}" == "true" ]]; then
    sudo su -l -c 'minikube ssh "sudo ip -6 addr add '"$CLUSTER_PROVISIONING_IP/$PROVISIONING_CIDR"' dev eth2"' "${USER}"
  else
    if sudo su -l -c "minikube ssh sudo brctl show" "${USER}" | grep -q "$CLUSTER_PROVISIONING_INTERFACE"; then
      sudo su -l -c "minikube ssh sudo ip link set $CLUSTER_PROVISIONING_INTERFACE down" "${USER}"
      sudo su -l -c "minikube ssh sudo brctl delbr $CLUSTER_PROVISIONING_INTERFACE" "${USER}"
    fi
    sudo su -l -c "minikube ssh sudo brctl addbr $CLUSTER_PROVISIONING_INTERFACE" "${USER}"
    sudo su -l -c "minikube ssh sudo ip link set $CLUSTER_PROVISIONING_INTERFACE up" "${USER}"
    sudo su -l -c "minikube ssh sudo brctl addif $CLUSTER_PROVISIONING_INTERFACE eth2" "${USER}"
    sudo su -l -c "minikube ssh sudo ip addr add $INITIAL_IRONICBRIDGE_IP/$PROVISIONING_CIDR dev $CLUSTER_PROVISIONING_INTERFACE" "${USER}"
  fi
fi

launch_baremetal_operator
launch_cluster_api_provider_metal3
apply_bm_hosts
