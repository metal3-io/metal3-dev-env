#!/bin/bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/releases.sh
# shellcheck disable=SC1091
source lib/network.sh

if [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
  IRONIC_HOST="${CLUSTER_URL_HOST}"
  export IRONIC_HOST_IP="${CLUSTER_PROVISIONING_IP}"
else
  IRONIC_HOST="${PROVISIONING_URL_HOST}"
  export IRONIC_HOST_IP="${PROVISIONING_IP}"
fi

# Disable Basic Authentication towards Ironic in BMO and do not provide additional certs
# Those variables are used in the CAPM3 component files
export IRONIC_NO_CA_CERT="true"
export IRONIC_NO_BASIC_AUTH="true"
export IRONIC_INSPECTOR_NO_BASIC_AUTH="true"

# -----------------------
# Repositories management
# -----------------------

#
# Clone and checkout a repo
#
function clone_repo() {
  local REPO_URL="$1"
  local REPO_BRANCH="$2"
  local REPO_PATH="$3"
  if [[ -d "${REPO_PATH}" && "${FORCE_REPO_UPDATE}" == "true" ]]; then
    rm -rf "${REPO_PATH}"
  fi
  if [ ! -d "${REPO_PATH}" ] ; then
    pushd "${M3PATH}"
    git clone "${REPO_URL}" "${REPO_PATH}"
    popd
    pushd "${REPO_PATH}"
    git checkout "${REPO_BRANCH}"
    git pull -r || true
    popd
  fi
}

#
# Clone all needed repositories
#
function clone_repos() {
  mkdir -p "${M3PATH}"
  clone_repo "${BMOREPO}" "${BMOBRANCH}" "${BMOPATH}"
  clone_repo "${CAPM3REPO}" "${CAPM3BRANCH}" "${CAPM3PATH}"
  clone_repo "${IPAMREPO}" "${IPAMBRANCH}" "${IPAMPATH}"
  clone_repo "${CAPIREPO}" "${CAPIBRANCH}" "${CAPIPATH}"
}

# ------------------------------------
# BMO  and Ironic deployment functions
# ------------------------------------

#
# Modifies the images to use the ones built locally in the kustomization
# This is v1a3 specific for BMO, all versions for Ironic
#
function update_kustomization_images(){
  for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    OLD_IMAGE_VAR="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
    # Strip the tag for image replacement
    OLD_IMAGE="${!OLD_IMAGE_VAR%:*}"
    #shellcheck disable=SC2086
    kustomize edit set image $OLD_IMAGE=$LOCAL_IMAGE
  done
  # Assign images from local image registry for kustomization
  for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    #shellcheck disable=SC2086
    kustomize edit set image $IMAGE=$LOCAL_IMAGE
  done
}

#
# kustomization for V1a3 BMO kustomization and v1a3 and v1a4 kustomization for
# Ironic. In V1a4 we deploy BMO through CAPM3.
#
function kustomize_overlay() {
  overlay_path=$1
  cat <<EOF > "$overlay_path/kustomization.yaml"
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

#
# For BMO and Ironic in v1a3, only Ironic in v1a4.
#
function deploy_kustomization() {
  kustomize_overlay_path=$(mktemp -d bmo-XXXXXXXXXX)
  kustomize_overlay "$kustomize_overlay_path"
  pushd "$kustomize_overlay_path"

  # Add custom images in overlay, and override the images with local ones
  update_kustomization_images
  popd

  kustomize build "$kustomize_overlay_path" | kubectl apply -f-
  rm -rf "$kustomize_overlay_path"
}

#
# Create the BMO deployment (used for v1a3 only)
#
function launch_baremetal_operator() {
  pushd "${BMOPATH}"

  BMO_CONFIG="${BMOPATH}/deploy/default"
  deploy_kustomization

  if [ "${BMO_RUN_LOCAL}" = true ]; then
    touch bmo.out.log
    touch bmo.err.log
    kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
    nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
  fi
  popd
}

# ------------
# BMH Creation
# ------------

#
# Create the BMH CRs
#
function make_bm_hosts() {
  while read -r name address user password mac; do
    go run "${BMOPATH}"/cmd/make-bm-worker/main.go \
      -address "$address" \
      -password "$password" \
      -user "$user" \
      -boot-mac "$mac" \
      -boot-mode "legacy" \
      "$name"
  done
}

#
# Apply the BMH CRs
#
function apply_bm_hosts() {
  pushd "${BMOPATH}"
  list_nodes | make_bm_hosts > "${WORKING_DIR}/bmhosts_crs.yaml"
  if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
    kubectl apply -f "${WORKING_DIR}/bmhosts_crs.yaml" -n metal3
  fi
  popd
}

# --------------------------
# CAPM3 deployment functions
# --------------------------

#
# Update the imports for the CAPM3 deployment files
#
function update_capm3_imports(){
  pushd "${CAPM3PATH}"

  # Modify the kustomization imports to use local BMO repo instead of Github Master
  cp config/bmo/kustomization.yaml config/bmo/kustomization.yaml.orig
  FOLDERS="$(grep github.com/metal3-io/baremetal-operator/ "config/bmo/kustomization.yaml" | \
  awk '{ print $2 }' | sed -e 's#^github.com/metal3-io/baremetal-operator/##' -e 's/?ref=.*$//')"
  BMO_REAL_PATH="$(realpath --relative-to="${CAPM3PATH}/config/bmo" "${BMOPATH}")"
  for folder in $FOLDERS; do
    sed -i -e "s#github.com/metal3-io/baremetal-operator/${folder}?ref=.*#${BMO_REAL_PATH}/${folder}#" "config/bmo/kustomization.yaml"
  done

  # Render the IPAM components from local repo instead of using the released version
  make hack/tools/bin/kustomize
  ./hack/tools/bin/kustomize build "${IPAMPATH}/config/" > config/ipam/metal3-ipam-components.yaml
  sed -i -e "s#https://github.com/metal3-io/ip-address-manager/releases/download/v.*/ipam-components.yaml#metal3-ipam-components.yaml#" "config/ipam/kustomization.yaml"
  popd
}

#
# Update the images for the CAPM3 deployment file to use local ones
#
function update_component_image(){
  IMPORT=$1
  ORIG_IMAGE=$2
  # Split the image IMAGE_NAME AND IMAGE_TAG, if any tag exist
  TMP_IMAGE="${ORIG_IMAGE##*/}"
  TMP_IMAGE_NAME="${TMP_IMAGE%%:*}"
  TMP_IMAGE_TAG="${TMP_IMAGE##*:}"
  # Assign the image tag to latest if there is no tag in the image
  if [ "${TMP_IMAGE_NAME}" == "${TMP_IMAGE_TAG}" ]; then
    TMP_IMAGE_TAG="latest"
  fi

  if [ "${IMPORT}" == "CAPM3" ]; then
    export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
    export MANIFEST_TAG="${TMP_IMAGE_TAG}"
    make set-manifest-image
  elif [ "${IMPORT}" == "BMO" ]; then
    export MANIFEST_IMG_BMO="${REGISTRY}/localimages/$TMP_IMAGE_NAME"
    export MANIFEST_TAG_BMO="$TMP_IMAGE_TAG"
    make set-manifest-image-bmo
  elif [ "${IMPORT}" == "IPAM" ]; then
    export MANIFEST_IMG_IPAM="${REGISTRY}/localimages/$TMP_IMAGE_NAME"
    export MANIFEST_TAG_IPAM="$TMP_IMAGE_TAG"
    make set-manifest-image-ipam
  fi
}

#
# Update the clusterctl deployment files to use local repositories
#
function patch_clusterctl(){
  pushd "${CAPM3PATH}"
  mkdir -p "${HOME}"/.cluster-api
  touch "${HOME}"/.cluster-api/clusterctl.yaml

  # At this point the images variables have been updated with update_images
  # Reflect the change in components files
  update_component_image CAPM3 "${CAPM3_IMAGE}"

  if [ "${CAPM3_VERSION}" != "v1alpha3" ]; then
    update_component_image BMO "${BAREMETAL_OPERATOR_IMAGE}"
    update_component_image IPAM "${IPAM_IMAGE}"
    update_capm3_imports
  fi

  make release-manifests

  rm -rf "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  mkdir -p "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  cp out/*.yaml "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  popd
}

#
# Launch the cluster-api provider.
#
function launch_cluster_api_provider_metal3() {
  pushd "${CAPM3PATH}"

    # shellcheck disable=SC2153
  clusterctl init --core cluster-api:"${CAPIRELEASE}" --bootstrap kubeadm:"${CAPIRELEASE}" \
    --control-plane kubeadm:"${CAPIRELEASE}" --infrastructure=metal3:"${CAPM3RELEASE}"  -v5

  if [ "${CAPM3_RUN_LOCAL}" == true ]; then
    touch capm3.out.log
    touch capm3.err.log
    kubectl scale -n metal3 deployment.v1.apps capm3-controller-manager --replicas 0
    nohup make run >> capm3.out.log 2>> capm3.err.log &
  fi

  if [ "${BMO_RUN_LOCAL}" == true ] && [ "${CAPM3_VERSION}" != "v1alpha3" ]; then
    touch bmo.out.log
    touch bmo.err.log
    kubectl scale deployment capm3-metal3-baremetal-operator -n capm3-system --replicas=0
    nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
  fi

  popd
}

# -------------
# Miscellaneous
# -------------

#
# Write out a clouds.yaml for this environment
#
function create_clouds_yaml() {
  sed -e "s/__CLUSTER_URL_HOST__/$CLUSTER_URL_HOST/g" clouds.yaml.template > clouds.yaml
  # To bind this into the ironic-client container we need a directory
  mkdir -p "${SCRIPTDIR}"/_clouds_yaml
  cp clouds.yaml "${SCRIPTDIR}"/_clouds_yaml/
}

#
# Modifies the images to use the ones built locally
# Updates the environment variables to refer to the images
# pushed to the local registry for caching.
#
function update_images(){
  for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    OLD_IMAGE_VAR="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
    # Strip the tag for image replacement
    OLD_IMAGE="${!OLD_IMAGE_VAR%:*}"
    eval "$OLD_IMAGE_VAR"="$LOCAL_IMAGE"
    export "${OLD_IMAGE_VAR?}"
  done
  # Assign images from local image registry after update image
  # This allows to use cached images for faster downloads
  for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    eval "$IMAGE_VAR"="$LOCAL_IMAGE"
  done
}

# ------------------------
# Management cluster infra
# ------------------------

#
# Start a KinD management cluster
#
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

#
# Create a management cluster
#
function start_management_cluster () {
  if [ "${EPHEMERAL_CLUSTER}" == "kind" ]; then
    launch_kind
  elif [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
    init_minikube

    sudo su -l -c 'minikube start' "${USER}"
    if [[ -n "${MINIKUBE_BMNET_V6_IP}" ]]; then
      sudo su -l -c "minikube ssh -- sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0" "${USER}"
      sudo su -l -c "minikube ssh -- sudo ip addr add $MINIKUBE_BMNET_V6_IP/64 dev eth3" "${USER}"
    fi
    if [[ "${PROVISIONING_IPV6}" == "true" ]]; then
      sudo su -l -c 'minikube ssh "sudo ip -6 addr add '"$CLUSTER_PROVISIONING_IP/$PROVISIONING_CIDR"' dev eth2"' "${USER}"
    else
      sudo su -l -c "minikube ssh sudo brctl addbr $CLUSTER_PROVISIONING_INTERFACE" "${USER}"
      sudo su -l -c "minikube ssh sudo ip link set $CLUSTER_PROVISIONING_INTERFACE up" "${USER}"
      sudo su -l -c "minikube ssh sudo brctl addif $CLUSTER_PROVISIONING_INTERFACE eth2" "${USER}"
      sudo su -l -c "minikube ssh sudo ip addr add $INITIAL_IRONICBRIDGE_IP/$PROVISIONING_CIDR dev $CLUSTER_PROVISIONING_INTERFACE" "${USER}"
    fi
  fi
}

# -----------------------------
# Deploy the management cluster
# -----------------------------

clone_repos
create_clouds_yaml
if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  start_management_cluster
  if [ "${CAPM3_VERSION}" == "v1alpha3" ]; then
    launch_baremetal_operator
  else
    kubectl create namespace metal3
  fi
fi

update_images

if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  patch_clusterctl
  launch_cluster_api_provider_metal3
  apply_bm_hosts
fi

if [ "${EPHEMERAL_CLUSTER}" != "minikube" ]; then
  ${RUN_LOCAL_IRONIC_SCRIPT}
else
  BMO_CONFIG="${BMOPATH}/ironic-deployment/keepalived"
  deploy_kustomization
fi
