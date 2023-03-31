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

export IRONIC_HOST="${CLUSTER_BARE_METAL_PROVISIONER_HOST}"
export IRONIC_HOST_IP="${CLUSTER_BARE_METAL_PROVISIONER_IP}"
export REPO_IMAGE_PREFIX="quay.io"

declare -a BMO_IRONIC_ARGS
# -k is for keepalived
BMO_IRONIC_ARGS=(-k)
if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
  BMO_IRONIC_ARGS+=("-t")
fi
if [ "${IRONIC_BASIC_AUTH}" == "false" ]; then
  BMO_IRONIC_ARGS+=("-n")
fi
if [ "${IRONIC_USE_MARIADB:-false}" == "true" ]; then
  BMO_IRONIC_ARGS+=("-m")
fi

sudo mkdir -p "${IRONIC_DATA_DIR}"
sudo chown -R "${USER}:${USER}" "${IRONIC_DATA_DIR}"

# shellcheck disable=SC1091
source lib/ironic_tls_setup.sh
# shellcheck disable=SC1091
source lib/ironic_basic_auth.sh

# ------------------------------------
# BMO and Ironic deployment functions
# ------------------------------------

#
# Create the BMO deployment (not used for CAPM3 v1a4 since BMO is bundeled there)
#
function launch_baremetal_operator() {
  pushd "${BMOPATH}"

  # Deploy BMO using deploy.sh script

if [ "${EPHEMERAL_CLUSTER}" != "tilt" ]; then
  # Update container images to use local ones
  if [ -n "${BARE_METAL_OPERATOR_LOCAL_IMAGE}" ]; then
    update_component_image BMO "${BARE_METAL_OPERATOR_LOCAL_IMAGE}"
  else
    update_component_image BMO "${BARE_METAL_OPERATOR_IMAGE}"
  fi
fi

  # Update Configmap parameters with correct urls
  cat << EOF | sudo tee "${BMOPATH}/config/default/ironic.env"
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
EOF

  if [ -n "${DEPLOY_ISO_URL}" ]; then
    echo "DEPLOY_ISO_URL=${DEPLOY_ISO_URL}" | sudo tee -a "${BMOPATH}/config/default/ironic.env"
  fi

  # Deploy BMO using deploy.sh script
  "${BMOPATH}/tools/deploy.sh" -b "${BMO_IRONIC_ARGS[@]}"

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
  pushd "${BMOPATH}"

    # Update Configmap parameters with correct urls
    cat << EOF | sudo tee "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
HTTP_PORT=${HTTP_PORT}
PROVISIONING_IP=${CLUSTER_BARE_METAL_PROVISIONER_IP}
PROVISIONING_CIDR=${BARE_METAL_PROVISIONER_CIDR}
PROVISIONING_INTERFACE=${BARE_METAL_PROVISIONER_INTERFACE}
DHCP_RANGE=${CLUSTER_DHCP_RANGE}
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
CACHEURL=http://${BARE_METAL_PROVISIONER_URL_HOST}/images
IRONIC_FAST_TRACK=true
RESTART_CONTAINER_CERTIFICATE_UPDATED="${RESTART_CONTAINER_CERTIFICATE_UPDATED}"
IRONIC_RAMDISK_SSH_KEY=${SSH_PUB_KEY_CONTENT}
IRONIC_USE_MARIADB=${IRONIC_USE_MARIADB:-false}
EOF

  if [ -n "${DEPLOY_ISO_URL}" ]; then
    echo "DEPLOY_ISO_URL=${DEPLOY_ISO_URL}" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
  fi

  if [[ "${NODES_PLATFORM}" == "libvirt" ]] ; then
    echo "IRONIC_KERNEL_PARAMS=console=ttyS0" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
  fi

  if [ -n "${DHCP_IGNORE}" ]; then
    echo "DHCP_IGNORE=${DHCP_IGNORE}" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
  fi

  if [ -n "${DHCP_HOSTS}" ]; then
    echo "DHCP_HOSTS=${DHCP_HOSTS}" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
  fi

  # Copy the generated configmap for ironic deployment
  if [[ ${BMOBRANCH} == "v0.1.2" ]] || [[ ${BMOBRANCH} == "v0.1.1" ]]; then # BMORELEASE until v0.1.2 used the old path TODO(mboukhalfa) can be removed after new bmo release
    cp "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env" "${BMOPATH}/ironic-deployment/keepalived/ironic_bmo_configmap.env"
  else
    cp "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"  "${BMOPATH}/ironic-deployment/components/keepalived/ironic_bmo_configmap.env"
  fi

  # Update manifests to use the correct images.
  # Note: Even though the manifests are not used for local deployment we need
  # to do this since Ironic will no longer run locally after pivot.
  # The workload cluster will use these images after pivoting.
  if [ -n "${IRONIC_LOCAL_IMAGE}" ]; then
    update_component_image Ironic "${IRONIC_LOCAL_IMAGE}"
  else
    update_component_image Ironic "${IRONIC_IMAGE}"
  fi
  if [ -n "${MARIADB_LOCAL_IMAGE}" ]; then
    update_component_image Mariadb "${MARIADB_LOCAL_IMAGE}"
  else
    update_component_image Mariadb "${MARIADB_IMAGE}"
  fi
  if [ -n "${IRONIC_KEEPALIVED_LOCAL_IMAGE}" ]; then
    update_component_image Keepalived "${IRONIC_KEEPALIVED_LOCAL_IMAGE}"
  else
    update_component_image Keepalived "${IRONIC_KEEPALIVED_IMAGE}"
  fi
  if [ -n "${IPA_DOWNLOADER_LOCAL_IMAGE}" ]; then
    update_component_image IPA-downloader "${IPA_DOWNLOADER_LOCAL_IMAGE}"
  else
    update_component_image IPA-downloader "${IPA_DOWNLOADER_IMAGE}"
  fi

  if [ "${EPHEMERAL_CLUSTER}" != "minikube" ]; then
    update_images
    ${RUN_LOCAL_IRONIC_SCRIPT}
  else
    # Deploy Ironic using deploy.sh script
    "${BMOPATH}/tools/deploy.sh" -i "${BMO_IRONIC_ARGS[@]}"
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
    while /bin/true; do
        minikube_error=0
        sudo su -l -c 'minikube start' "${USER}" || minikube_error=1
        if [[ $minikube_error -eq 0 ]]; then
          break
        fi
    done
    if [[ -n "${MINIKUBE_BMNET_V6_IP}" ]]; then
      sudo su -l -c "minikube ssh -- sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0" "${USER}"
      sudo su -l -c "minikube ssh -- sudo ip addr add $MINIKUBE_BMNET_V6_IP/64 dev eth3" "${USER}"
    fi
    if [[ "${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY}" == "true" ]]; then
      sudo su -l -c 'minikube ssh "sudo ip -6 addr add '"$CLUSTER_BARE_METAL_PROVISIONER_IP/$BARE_METAL_PROVISIONER_CIDR"' dev eth2"' "${USER}"
    else
      sudo su -l -c "minikube ssh sudo brctl addbr $BARE_METAL_PROVISIONER_INTERFACE" "${USER}"
      sudo su -l -c "minikube ssh sudo ip link set $BARE_METAL_PROVISIONER_INTERFACE up" "${USER}"
      sudo su -l -c "minikube ssh sudo brctl addif $BARE_METAL_PROVISIONER_INTERFACE eth2" "${USER}"
      sudo su -l -c "minikube ssh sudo ip addr add $INITIAL_BARE_METAL_PROVISIONER_BRIDGE_IP/$BARE_METAL_PROVISIONER_CIDR dev $BARE_METAL_PROVISIONER_INTERFACE" "${USER}"
    fi
  fi
}

# -----------------------------
# Deploy the management cluster
# -----------------------------

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
