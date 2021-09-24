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

export IRONIC_HOST="${CLUSTER_URL_HOST}"
export IRONIC_HOST_IP="${CLUSTER_PROVISIONING_IP}"

sudo mkdir -p "${IRONIC_DATA_DIR}"
sudo chown -R "${USER}:${USER}" "${IRONIC_DATA_DIR}"

# shellcheck disable=SC1091
source lib/ironic_tls_setup.sh
# shellcheck disable=SC1091
source lib/ironic_basic_auth.sh

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
}

# ------------------------------------
# BMO and Ironic deployment functions
# ------------------------------------

#
# Modifies the images to use the ones built locally in the kustomization
# This is v1a3 specific for BMO, all versions for Ironic
#
function update_kustomization_images(){
  FILE_PATH=$1
  for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    OLD_IMAGE_VAR="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
    # Strip the tag for image replacement
    OLD_IMAGE="${!OLD_IMAGE_VAR%:*}"
    sed -i -E "s $OLD_IMAGE$ $LOCAL_IMAGE g" "$FILE_PATH"
  done
  # Assign images from local image registry for kustomization
  for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    #shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    LOCAL_IMAGE="${REGISTRY}/localimages/$IMAGE_NAME"
    sed -i -E "s $IMAGE$ $LOCAL_IMAGE g" "$FILE_PATH"
  done
}

#
# Create the BMO deployment (used for v1a4 only)
#
function launch_baremetal_operator() {
  pushd "${BMOPATH}"

  # Deploy BMO using deploy.sh script

  # Update container images to use local ones
  cp "${BMOPATH}/config/manager/manager.yaml" "${BMOPATH}/config/manager/manager.yaml.orig"
  update_kustomization_images "${BMOPATH}/config/manager/manager.yaml"

  # Update Configmap parameters with correct urls
  cp "${BMOPATH}/config/default/ironic.env" "${BMOPATH}/config/default/ironic.env.orig"
  cat << EOF | sudo tee "${BMOPATH}/config/default/ironic.env"
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
EOF

  # Deploy. Args: <deploy-BMO> <deploy-Ironic> <deploy-TLS> <deploy-Basic-Auth> <deploy-Keepalived>
  "${BMOPATH}/tools/deploy.sh" true false "${IRONIC_TLS_SETUP}" "${IRONIC_BASIC_AUTH}" true

  # If BMO should run locally, scale down the deployment and run BMO
  if [ "${BMO_RUN_LOCAL}" == "true" ]; then
    if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
      sudo mkdir -p /opt/metal3/certs/ca/
      cp "${IRONIC_CACERT_FILE}" /opt/metal3/certs/ca/crt
      if [ "${IRONIC_CACERT_FILE}" != "${IRONIC_INSPECTOR_CACERT_FILE}" ]; then
        cat "${IRONIC_INSPECTOR_CACERT_FILE}" >> /opt/metal3/certs/ca/crt
      fi
    fi
    if [ "${IRONIC_BASIC_AUTH}" == "true" ]; then
      sudo mkdir -p /opt/metal3/auth/ironic
      sudo chown "$USER":"$USER" /opt/metal3/auth/ironic
      cp "${IRONIC_AUTH_DIR}ironic-username" /opt/metal3/auth/ironic/username
      cp "${IRONIC_AUTH_DIR}ironic-password" /opt/metal3/auth/ironic/password
      sudo mkdir -p /opt/metal3/auth/ironic-inspector
      sudo chown "$USER":"$USER" /opt/metal3/auth/ironic-inspector
      cp "${IRONIC_AUTH_DIR}${IRONIC_INSPECTOR_USERNAME}" /opt/metal3/auth/ironic-inspector/username
      cp "${IRONIC_AUTH_DIR}${IRONIC_INSPECTOR_PASSWORD}" /opt/metal3/auth/ironic-inspector/password
    fi

    export IRONIC_ENDPOINT=${IRONIC_URL}
    export IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}

    touch bmo.out.log
    touch bmo.err.log
    kubectl scale deployment baremetal-operator-controller-manager -n baremetal-operator-system --replicas=0
    nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
  fi
  popd
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

#
# Launch Ironic locally for Kind and Tilt, in cluster for Minikube
#
function launch_ironic() {
  pushd "${BMOPATH}"

    # Update Configmap parameters with correct urls
    cp "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env" "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env.orig"
    cat << EOF | sudo tee "$IRONIC_DATA_DIR/ironic_bmo_configmap.env"
HTTP_PORT=${HTTP_PORT}
PROVISIONING_IP=${CLUSTER_PROVISIONING_IP}
PROVISIONING_CIDR=${PROVISIONING_CIDR}
PROVISIONING_INTERFACE=${CLUSTER_PROVISIONING_INTERFACE}
DHCP_RANGE=${CLUSTER_DHCP_RANGE}
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
CACHEURL=http://${PROVISIONING_URL_HOST}/images
IRONIC_FAST_TRACK=true
RESTART_CONTAINER_CERTIFICATE_UPDATED="${RESTART_CONTAINER_CERTIFICATE_UPDATED}"
EOF

  if [ "$NODES_PLATFORM" == "libvirt" ] ; then
    echo "IRONIC_KERNEL_PARAMS=console=ttyS0" | sudo tee -a "$IRONIC_DATA_DIR/ironic_bmo_configmap.env"
  fi

  if [ "${EPHEMERAL_CLUSTER}" != "minikube" ]; then
    update_images
    ${RUN_LOCAL_IRONIC_SCRIPT}
  else
    # Deploy Ironic using deploy.sh script

    # Update container images to use local ones
    cp "${BMOPATH}/ironic-deployment/ironic/ironic.yaml" "${BMOPATH}/ironic-deployment/ironic/ironic.yaml.orig"
    cp "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml" "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml.orig"
    update_kustomization_images "${BMOPATH}/ironic-deployment/ironic/ironic.yaml"
    update_kustomization_images "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml"

    # Copy the generated configmap for ironic deployment
    cp "$IRONIC_DATA_DIR/ironic_bmo_configmap.env"  "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env"
    
    # Deploy. Args: <deploy-BMO> <deploy-Ironic> <deploy-TLS> <deploy-Basic-Auth> <deploy-Keepalived>
    "${BMOPATH}/tools/deploy.sh" false true "${IRONIC_TLS_SETUP}" "${IRONIC_BASIC_AUTH}" true

    # Restore original files
    mv "${BMOPATH}/ironic-deployment/ironic/ironic.yaml.orig" "${BMOPATH}/ironic-deployment/ironic/ironic.yaml"
    mv "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml.orig" "${BMOPATH}/ironic-deployment/keepalived/keepalived_patch.yaml"
  fi
  
  # Restore original files
  mv "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env.orig" "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env"
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
  if [[ -n "$(list_nodes)" ]]; then
    echo "bmhosts_crs.yaml is applying"
    while ! kubectl apply -f "${WORKING_DIR}/bmhosts_crs.yaml" -n metal3 &>/dev/null; do
	    sleep 3
    done
    echo "bmhosts_crs.yaml is successfully applied"
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

  # Assign empty secret to BMO when TLS is disabled
  if [ "${IRONIC_TLS_SETUP}" == "false" ] && [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
    sed -i "s/ironic-cacert/empty-ironic-cacert/g" "config/bmo/secret_mount_patch.yaml"
  fi
  # Modify the kustomization imports to use local BMO repo instead of Github Master
  if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then 
    cp config/bmo/kustomization.yaml config/bmo/kustomization.yaml.orig
  fi

  cp config/ipam/kustomization.yaml config/ipam/kustomization.yaml.orig
  make hack/tools/bin/kustomize

  if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
    # Render the BMO components from local repo
    ./hack/tools/bin/kustomize build "${BMOPATH}/config/default" > config/bmo/bmo-components.yaml
    sed -i -e "s#https://raw.githubusercontent.com/metal3-io/baremetal-operator/master/config/render/capm3.yaml#bmo-components.yaml#" "config/bmo/kustomization.yaml"
    # Render the IPAM components from local repo instead of using the released version
    ./hack/tools/bin/kustomize build "${IPAMPATH}/config/" > config/ipam/metal3-ipam-components.yaml
  else
    ./hack/tools/bin/kustomize build "${IPAMPATH}/config/default" > config/ipam/metal3-ipam-components.yaml
  fi

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

  if [ "${IMPORT}" == "BMO" ] && [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
    export MANIFEST_IMG_BMO="${REGISTRY}/localimages/$TMP_IMAGE_NAME"
    export MANIFEST_TAG_BMO="$TMP_IMAGE_TAG"
    make set-manifest-image-bmo
  fi

  if [ "${IMPORT}" == "CAPM3" ]; then
    export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
    export MANIFEST_TAG="${TMP_IMAGE_TAG}"
    make set-manifest-image
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
  if [ -n "${CAPM3_LOCAL_IMAGE}" ]; then
    update_component_image CAPM3 "${CAPM3_LOCAL_IMAGE}"
  else
    update_component_image CAPM3 "${CAPM3_IMAGE}"
  fi

  if  [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
    if [ -n "${BAREMETAL_OPERATOR_LOCAL_IMAGE}" ]; then
      update_component_image BMO "${BAREMETAL_OPERATOR_LOCAL_IMAGE}"
    else
      update_component_image BMO "${BAREMETAL_OPERATOR_IMAGE}"
    fi
  fi

  if [ -n "${IPAM_LOCAL_IMAGE}" ]; then
    update_component_image IPAM "${IPAM_LOCAL_IMAGE}"
  else
    update_component_image IPAM "${IPAM_IMAGE}"
  fi

  update_capm3_imports
  make release-manifests

  if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
    mv config/bmo/kustomization.yaml.orig config/bmo/kustomization.yaml
    rm config/bmo/bmo-components.yaml
  fi

  mv config/ipam/kustomization.yaml.orig config/ipam/kustomization.yaml
  rm config/ipam/metal3-ipam-components.yaml

  rm -rf "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  mkdir -p "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  cp out/*.yaml "${HOME}"/.cluster-api/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
  
  popd
}

#
# Launch the cluster-api provider metal3.
#
function launch_cluster_api_provider_metal3() {
  pushd "${CAPM3PATH}"

    # shellcheck disable=SC2153
  clusterctl init --core cluster-api:"${CAPIRELEASE}" --bootstrap kubeadm:"${CAPIRELEASE}" \
    --control-plane kubeadm:"${CAPIRELEASE}" --infrastructure=metal3:"${CAPM3RELEASE}"  -v5

  if [ "${CAPM3_RUN_LOCAL}" == true ]; then
    touch capm3.out.log
    touch capm3.err.log
    kubectl scale -n capm3-system deployment.v1.apps capm3-controller-manager --replicas 0
    nohup make run >> capm3.out.log 2>> capm3.err.log &
  fi

  if [ "${BMO_RUN_LOCAL}" == true ] && [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
    touch bmo.out.log
    touch bmo.err.log
    kubectl scale deployment capm3-baremetal-operator-controller-manager -n capm3-system --replicas=0
    nohup "${SCRIPTDIR}/hack/run-bmo-loop.sh" >> bmo.out.log 2>>bmo.err.log &
  fi

  popd
}

# -------------
# Miscellaneous
# -------------

function render_j2_config () {
  python3 -c 'import os; import sys; import jinja2; sys.stdout.write(jinja2.Template(sys.stdin.read()).render(env=os.environ))' < "${1}"
}

#
# Write out a clouds.yaml for this environment
#
function create_clouds_yaml() {
  # To bind this into the ironic-client container we need a directory
  mkdir -p "${SCRIPTDIR}"/_clouds_yaml
  if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
    cp "${IRONIC_CACERT_FILE}" "${SCRIPTDIR}"/_clouds_yaml/ironic-ca.crt
  fi
  render_j2_config "${SCRIPTDIR}"/clouds.yaml.j2 > _clouds_yaml/clouds.yaml
}

# ------------------------
# Management cluster infra
# ------------------------

#
# Start a KinD management cluster
#
function launch_kind() {
  cat <<EOF | sudo su -l -c "kind create cluster --name kind --image=kindest/node:${KIND_NODE_IMAGE_VERSION} --config=- " "$USER"
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
    sudo systemctl restart libvirtd.service
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

# Kill and remove the running ironic containers
"$BMOPATH"/tools/remove_local_ironic.sh

create_clouds_yaml
if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  start_management_cluster
  kubectl create namespace metal3
fi

if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  patch_clusterctl
  launch_cluster_api_provider_metal3
fi

if [ "${CAPM3_VERSION}" != "v1alpha4" ]; then 
  launch_baremetal_operator
fi

launch_ironic

if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
    BMO_NAME_PREFIX="${NAMEPREFIX}-baremetal-operator"
  else
    BMO_NAME_PREFIX="${NAMEPREFIX}"
  fi

  if [[ "${BMO_RUN_LOCAL}" != true ]]; then
    if ! kubectl rollout status deployment "${BMO_NAME_PREFIX}"-controller-manager -n "${IRONIC_NAMESPACE}" --timeout=5m; then
      echo "baremetal-operator-controller-manager deployment can not be rollout"
      exit 1
    fi
  else
    # There is no certificate to run validation webhook on local.
    # Thus we are deleting validatingwebhookconfiguration resource if exists to let BMO is working properly on local runs.
    kubectl delete validatingwebhookconfiguration/"${BMO_NAME_PREFIX}"-validating-webhook-configuration --ignore-not-found=true
  fi
  apply_bm_hosts
fi
