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
export REPO_IMAGE_PREFIX="quay.io"

sudo mkdir -p "${IRONIC_DATA_DIR}"
sudo chown -R "${USER}:${USER}" "${IRONIC_DATA_DIR}"

# shellcheck disable=SC1091
source lib/ironic_tls_setup.sh
# shellcheck disable=SC1091
source lib/ironic_basic_auth.sh

# Create temporary folder for kustomizations where we can make changes (e.g. set image)
rm -rf "${TEMP_KUSTOMIZATIONS}"
mkdir "${TEMP_KUSTOMIZATIONS}"
cp --recursive "${SCRIPTDIR}/hack/kustomizations/." "${TEMP_KUSTOMIZATIONS}"

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
  local REPO_COMMIT="${4:-HEAD}"

  if [[ -d "${REPO_PATH}" && "${FORCE_REPO_UPDATE}" == "true" ]]; then
    rm -rf "${REPO_PATH}"
  fi
  if [ ! -d "${REPO_PATH}" ] ; then
    pushd "${M3PATH}"
    git clone "${REPO_URL}" "${REPO_PATH}"
    popd
    pushd "${REPO_PATH}"
    git checkout "${REPO_BRANCH}"
    git checkout "${REPO_COMMIT}"
    git pull -r || true
    popd
  fi
}

#
# Clone all needed repositories
#
function clone_repos() {
  mkdir -p "${M3PATH}"
  clone_repo "${BMOREPO}" "${BMOBRANCH}" "${BMOPATH}" "${BMOCOMMIT}"
  clone_repo "${CAPM3REPO}" "${CAPM3BRANCH}" "${CAPM3PATH}"
  clone_repo "${IPAMREPO}" "${IPAMBRANCH}" "${IPAMPATH}"
  clone_repo "${CAPIREPO}" "${CAPIBRANCH}" "${CAPIPATH}"
}

# ------------------------------------
# BMO and Ironic deployment functions
# ------------------------------------

#
# Create the BMO deployment (not used for CAPM3 v1a4 since BMO is bundeled there)
#
function launch_baremetal_operator() {

  if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
    # Update container images to use local ones
    pushd "${TEMP_KUSTOMIZATIONS}/bmo"
    kustomize edit set image quay.io/metal3-io/baremetal-operator="${BAREMETAL_OPERATOR_LOCAL_IMAGE:-${BAREMETAL_OPERATOR_IMAGE}}"
    popd
  fi

  # Update Configmap parameters with correct urls
  cat << EOF | tee "${TEMP_KUSTOMIZATIONS}/bmo/ironic.env"
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
EOF

  if [ -n "${DEPLOY_ISO_URL}" ]; then
    echo "DEPLOY_ISO_URL=${DEPLOY_ISO_URL}" | tee -a "${TEMP_KUSTOMIZATIONS}/bmo/ironic.env"
  fi

  # Set correct repo and commit to use
  sed "s#BMOREPO#${BMOREPO}#g" -i "${TEMP_KUSTOMIZATIONS}/bmo/kustomization.yaml"
  sed "s#BMOCOMMIT#${BMOCOMMIT}#g" -i "${TEMP_KUSTOMIZATIONS}/bmo/kustomization.yaml"

  # Based on IRONIC_TLS_SETUP, IRONIC_BASIC_AUTH, pick the proper components
  # and edit the kustomization.
  pushd "${TEMP_KUSTOMIZATIONS}/bmo"
  if [ "${IRONIC_BASIC_AUTH}" == "true" ]; then
    kustomize edit add component components/basic-auth
  fi
  if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
    kustomize edit add component components/tls
  fi
  popd

  # Generate credentials
  echo "${IRONIC_USERNAME}" > "${TEMP_KUSTOMIZATIONS}/bmo/components/basic-auth/ironic-username"
  echo "${IRONIC_PASSWORD}" > "${TEMP_KUSTOMIZATIONS}/bmo/components/basic-auth/ironic-password"
  echo "${IRONIC_INSPECTOR_USERNAME}" > "${TEMP_KUSTOMIZATIONS}/bmo/components/basic-auth/ironic-inspector-username"
  echo "${IRONIC_INSPECTOR_PASSWORD}" > "${TEMP_KUSTOMIZATIONS}/bmo/components/basic-auth/ironic-inspector-password"

  kustomize build "${TEMP_KUSTOMIZATIONS}/bmo" | kubectl apply -f -

  pushd "${BMOPATH}"
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
    kubectl scale deployment baremetal-operator-controller-manager -n "${IRONIC_NAMESPACE}" --replicas=0
    # TODO: Why not run the container instead? For auto update we can use tilt.
    # This makes metal3-dev-env and BMO unnecessarily coupled.
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
    # Create Configmap parameters with correct urls
    cat << EOF | tee "${TEMP_KUSTOMIZATIONS}/ironic/ironic_bmo_configmap.env"
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
IRONIC_RAMDISK_SSH_KEY=${SSH_PUB_KEY_CONTENT}
EOF

  if [ -n "${DEPLOY_ISO_URL}" ]; then
    echo "DEPLOY_ISO_URL=${DEPLOY_ISO_URL}" | tee -a "${TEMP_KUSTOMIZATIONS}/ironic/ironic_bmo_configmap.env"
  fi

  if [ "$NODES_PLATFORM" == "libvirt" ] ; then
    echo "IRONIC_KERNEL_PARAMS=console=ttyS0" | tee -a "${TEMP_KUSTOMIZATIONS}/ironic/ironic_bmo_configmap.env"
  fi

  # Update manifests to use the correct images.
  # Note: Even though the manifests are not used for local deployment we need
  # to do this since Ironic will no longer run locally after pivot.
  # The workload cluster will use these images after pivoting.
  pushd "${TEMP_KUSTOMIZATIONS}/ironic"
  kustomize edit set image quay.io/metal3-io/ironic="${IRONIC_LOCAL_IMAGE:-${IRONIC_IMAGE}}"
  kustomize edit set image quay.io/metal3-io/mariadb="${MARIADB_LOCAL_IMAGE:-${MARIADB_IMAGE}}"
  kustomize edit set image quay.io/metal3-io/keepalived="${IRONIC_KEEPALIVED_LOCAL_IMAGE:-${IRONIC_KEEPALIVED_IMAGE}}"
  kustomize edit set image quay.io/metal3-io/ironic-ipa-downloader="${IPA_DOWNLOADER_LOCAL_IMAGE:-${IPA_DOWNLOADER_IMAGE}}"
  popd

  # Based on IRONIC_TLS_SETUP, IRONIC_BASIC_AUTH, pick the proper components
  # and edit the kustomization.
  pushd "${TEMP_KUSTOMIZATIONS}/ironic"
  if [ "${IRONIC_BASIC_AUTH}" == "true" ]; then
    kustomize edit add component components/basic-auth
  fi
  if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
    kustomize edit add component components/tls
  fi
  kustomize edit add component components/keepalived
  popd

  # Set correct repo and commit to use
  sed "s#BMOREPO#${BMOREPO}#g" -i "${TEMP_KUSTOMIZATIONS}/ironic/kustomization.yaml"
  sed "s#BMOCOMMIT#${BMOCOMMIT}#g" -i "${TEMP_KUSTOMIZATIONS}/ironic/kustomization.yaml"
  sed "s#BMOREPO#${BMOREPO}#g" -i "${TEMP_KUSTOMIZATIONS}/ironic/components/tls/kustomization.yaml"
  sed "s#BMOCOMMIT#${BMOCOMMIT}#g" -i "${TEMP_KUSTOMIZATIONS}/ironic/components/tls/kustomization.yaml"
  # Set correct IPs for the certificates
  sed -i "s/IRONIC_HOST_IP/${IRONIC_HOST_IP}/g; s/MARIADB_HOST_IP/${MARIADB_HOST_IP}/g" "${TEMP_KUSTOMIZATIONS}/ironic/components/tls/certificate.yaml"

  # Generate credentials
  envsubst < "${TEMP_KUSTOMIZATIONS}/ironic/components/basic-auth/ironic-auth-config-tpl" > \
  "${TEMP_KUSTOMIZATIONS}/ironic/components/basic-auth/ironic-auth-config"
  envsubst < "${TEMP_KUSTOMIZATIONS}/ironic/components/basic-auth/ironic-inspector-auth-config-tpl" > \
  "${TEMP_KUSTOMIZATIONS}/ironic/components/basic-auth/ironic-inspector-auth-config"

  echo "IRONIC_HTPASSWD=$(htpasswd -n -b -B "${IRONIC_USERNAME}" "${IRONIC_PASSWORD}")" > \
  "${TEMP_KUSTOMIZATIONS}/ironic/components/basic-auth/ironic-htpasswd"
  echo "INSPECTOR_HTPASSWD=$(htpasswd -n -b -B "${IRONIC_INSPECTOR_USERNAME}" \
  "${IRONIC_INSPECTOR_PASSWORD}")" > "${TEMP_KUSTOMIZATIONS}/ironic/components/basic-auth/ironic-inspector-htpasswd"

  if [ "${EPHEMERAL_CLUSTER}" != "minikube" ]; then
    update_images
    ${RUN_LOCAL_IRONIC_SCRIPT}
  else
    kustomize build "${TEMP_KUSTOMIZATIONS}/ironic" | kubectl apply -f -
  fi
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
      -boot-mode "${BOOT_MODE}" \
      "$name"
  done
}

#
# Apply the BMH CRs
#
function apply_bm_hosts() {
  NAMESPACE=$1
  pushd "${BMOPATH}"
  list_nodes | make_bm_hosts > "${WORKING_DIR}/bmhosts_crs.yaml"
  if [[ -n "$(list_nodes)" ]]; then
    echo "bmhosts_crs.yaml is applying"
    while ! kubectl apply -f "${WORKING_DIR}/bmhosts_crs.yaml" -n "$NAMESPACE" &>/dev/null; do
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

  # Modify the kustomization imports to use local BMO repo instead of Github Main
  make hack/tools/bin/kustomize
  ./hack/tools/bin/kustomize build "${IPAMPATH}/config/default" > config/ipam/metal3-ipam-components.yaml

  sed -i -e "s#https://github.com/metal3-io/ip-address-manager/releases/download/v.*/ipam-components.yaml#metal3-ipam-components.yaml#" "config/ipam/kustomization.yaml"
  popd
}

#
# Update the CAPM3 and BMO manifests to use local images as defined in variables
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

  # NOTE: It is assumed that we are already in the correct directory to run make
  case "${IMPORT}" in
    "BMO")
      export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
      export MANIFEST_TAG="${TMP_IMAGE_TAG}"
      make set-manifest-image-bmo
      ;;
    "CAPM3")
      export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
      export MANIFEST_TAG="${TMP_IMAGE_TAG}"
      make set-manifest-image
      ;;
    "IPAM")
      export MANIFEST_IMG_IPAM="${REGISTRY}/localimages/$TMP_IMAGE_NAME"
      export MANIFEST_TAG_IPAM="$TMP_IMAGE_TAG"
      make set-manifest-image-ipam
      ;;
    "Ironic")
      export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
      export MANIFEST_TAG="${TMP_IMAGE_TAG}"
      make set-manifest-image-ironic
      ;;
    "Mariadb")
      export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
      export MANIFEST_TAG="${TMP_IMAGE_TAG}"
      make set-manifest-image-mariadb
      ;;
    "Keepalived")
      export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
      export MANIFEST_TAG="${TMP_IMAGE_TAG}"
      make set-manifest-image-keepalived
      ;;
    "IPA-downloader")
      export MANIFEST_IMG="${REGISTRY}/localimages/${TMP_IMAGE_NAME}"
      export MANIFEST_TAG="${TMP_IMAGE_TAG}"
      make set-manifest-image-ipa-downloader
      ;;
  esac
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

  if [ -n "${IPAM_LOCAL_IMAGE}" ]; then
    update_component_image IPAM "${IPAM_LOCAL_IMAGE}"
  else
    update_component_image IPAM "${IPAM_IMAGE}"
  fi

  update_capm3_imports
  make release-manifests

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
  cat <<EOF | sudo su -l -c "kind create cluster --name kind --image=${KIND_NODE_IMAGE} --config=- " "$USER"
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

  patch_clusterctl
  launch_cluster_api_provider_metal3
  BMO_NAME_PREFIX="${NAMEPREFIX}"
  launch_baremetal_operator
  launch_ironic

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
  apply_bm_hosts "$NAMESPACE"
elif [ "${EPHEMERAL_CLUSTER}" == "tilt" ]; then

source tilt-setup/deploy_tilt_env.sh
fi
