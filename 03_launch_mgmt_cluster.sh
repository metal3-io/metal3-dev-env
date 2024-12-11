#!/usr/bin/env bash

set -eux

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/releases.sh
# shellcheck disable=SC1091
source lib/network.sh

# Default CAPI_CONFIG_DIR to $HOME/.config directory if XDG_CONFIG_HOME not set
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}"
export CAPI_CONFIG_DIR="${CONFIG_DIR}/cluster-api"
export IRONIC_HOST="${CLUSTER_BARE_METAL_PROVISIONER_HOST}"
export IRONIC_HOST_IP="${CLUSTER_BARE_METAL_PROVISIONER_IP}"
export REPO_IMAGE_PREFIX="quay.io"

declare -a BMO_IRONIC_ARGS
# -k is for keepalived
BMO_IRONIC_ARGS=(-k)

if [[ "${IRONIC_TLS_SETUP:-true}" = "true" ]]; then
    BMO_IRONIC_ARGS+=("-t")
fi
if [[ "${IRONIC_BASIC_AUTH:-true}" = "false" ]]; then
    BMO_IRONIC_ARGS+=("-n")
fi
if [[ "${IRONIC_USE_MARIADB:-false}" = "true" ]]; then
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
launch_baremetal_operator()
{
    pushd "${BMOPATH}"

    # Deploy BMO using deploy.sh script
    if [[ "${EPHEMERAL_CLUSTER}" != "tilt" ]]; then
        # Update container images to use local ones
        if [[ -n "${BARE_METAL_OPERATOR_LOCAL_IMAGE:-}" ]]; then
            update_component_image BMO "${BARE_METAL_OPERATOR_LOCAL_IMAGE}"
        else
            update_component_image BMO "${BARE_METAL_OPERATOR_IMAGE}"
        fi
        if [[ -n "${IRONIC_KEEPALIVED_LOCAL_IMAGE:-}" ]]; then
            update_component_image Keepalived "${IRONIC_KEEPALIVED_LOCAL_IMAGE}"
        else
            update_component_image Keepalived "${IRONIC_KEEPALIVED_IMAGE}"
        fi
    fi

    # Update Configmap parameters with correct urls
    cat << EOF | sudo tee "${BMOPATH}/config/default/ironic.env"
DEPLOY_KERNEL_URL=${DEPLOY_KERNEL_URL}
DEPLOY_RAMDISK_URL=${DEPLOY_RAMDISK_URL}
IRONIC_ENDPOINT=${IRONIC_URL}
IRONIC_INSPECTOR_ENDPOINT=${IRONIC_INSPECTOR_URL}
EOF

    if [[ -n "${DEPLOY_ISO_URL}" ]]; then
        echo "DEPLOY_ISO_URL=${DEPLOY_ISO_URL}" | sudo tee -a "${BMOPATH}/config/default/ironic.env"
    fi

    # Deploy BMO using deploy.sh script
    "${BMOPATH}/tools/deploy.sh" -b "${BMO_IRONIC_ARGS[@]}"

    # If BMO should run locally, scale down the deployment and run BMO
    if [[ "${BMO_RUN_LOCAL}" = "true" ]]; then
        if [[ "${IRONIC_TLS_SETUP}" = "true" ]]; then
            sudo mkdir -p /opt/metal3/certs/ca/
            cp "${IRONIC_CACERT_FILE}" /opt/metal3/certs/ca/crt
            if [[ "${IRONIC_CACERT_FILE}" != "${IRONIC_INSPECTOR_CACERT_FILE}" ]]; then
                cat "${IRONIC_INSPECTOR_CACERT_FILE}" >> /opt/metal3/certs/ca/crt
            fi
        fi

        if [[ "${IRONIC_BASIC_AUTH}" = "true" ]]; then
            sudo mkdir -p /opt/metal3/auth/ironic
            sudo chown "${USER}":"${USER}" /opt/metal3/auth/ironic
            cp "${IRONIC_AUTH_DIR}ironic-username" /opt/metal3/auth/ironic/username
            cp "${IRONIC_AUTH_DIR}ironic-password" /opt/metal3/auth/ironic/password
            sudo mkdir -p /opt/metal3/auth/ironic-inspector
            sudo chown "${USER}":"${USER}" /opt/metal3/auth/ironic-inspector
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
update_images()
{
    local image_var image image_name local_image old_image_var

    for image_var in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
        image=${!image_var}
        #shellcheck disable=SC2086
        image_name="${image##*/}"
        local_image="${REGISTRY}/localimages/${image_name}"
        old_image_var="${image_var%_LOCAL_IMAGE}_IMAGE"
        eval "${old_image_var}"="${local_image}"
        export "${old_image_var?}"
    done

    # Assign images from local image registry after update image
    # This allows to use cached images for faster downloads
    for image_var in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
      image=${!image_var}
      #shellcheck disable=SC2086
      image_name="${image##*/}"
      local_image="${REGISTRY}/localimages/${image_name}"
      eval "${image_var}"="${local_image}"
    done
}

#
# Launch Ironic locally for Kind and Tilt, in cluster for Minikube
#
launch_ironic()
{
    pushd "${BMOPATH}"

    local inspector_default
    inspector_default=$(grep USE_IRONIC_INSPECTOR "${BMOPATH}/ironic-deployment/default/ironic_bmo_configmap.env" || true)

    # Update Configmap parameters with correct urls
    # Variable names inserted into the configmap might have different
    # naming conventions than the dev-env e.g. PROVISIONING_IP and CIDR are
    # called PROVISIONER_IP and CIDR in dev-env
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
RESTART_CONTAINER_CERTIFICATE_UPDATED="${RESTART_CONTAINER_CERTIFICATE_UPDATED}"
IRONIC_RAMDISK_SSH_KEY=${SSH_PUB_KEY_CONTENT}
IRONIC_USE_MARIADB=${IRONIC_USE_MARIADB:-false}
${inspector_default}
IPA_BASEURI=${IPA_BASEURI}
IPA_BRANCH=${IPA_BRANCH}
IPA_FLAVOR=${IPA_FLAVOR}
EOF

    if [[ -n "${DEPLOY_ISO_URL}" ]]; then
        echo "DEPLOY_ISO_URL=${DEPLOY_ISO_URL}" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
    fi

    if [[ "${NODES_PLATFORM}" = "libvirt" ]] ; then
        echo "IRONIC_KERNEL_PARAMS=console=ttyS0" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
    fi

    # TODO (mboukhalfa) enable heartbeating and ironic TLS when sushy-tools release v1.3.1
    if [[ "${NODES_PLATFORM}" = "fake" ]]; then
        echo "OS_AGENT__REQUIRE_TLS=false" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
    fi

    if [[ -n "${DHCP_IGNORE:-}" ]]; then
        echo "DHCP_IGNORE=${DHCP_IGNORE}" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
    fi

    if [[ -n "${DHCP_HOSTS:-}" ]]; then
        echo "DHCP_HOSTS=${DHCP_HOSTS}" | sudo tee -a "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
    fi

    # Copy the generated configmap for ironic deployment
    cp "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env" "${BMOPATH}/ironic-deployment/components/keepalived/ironic_bmo_configmap.env"

    # Update manifests to use the correct images.
    # Note: Even though the manifests are not used for local deployment we need
    # to do this since Ironic will no longer run locally after pivot.
    # The workload cluster will use these images after pivoting.
    if [[ -n "${IRONIC_LOCAL_IMAGE:-}" ]]; then
        update_component_image Ironic "${IRONIC_LOCAL_IMAGE}"
    else
        update_component_image Ironic "${IRONIC_IMAGE}"
    fi

    if [[ -n "${MARIADB_LOCAL_IMAGE:-}" ]]; then
        update_component_image Mariadb "${MARIADB_LOCAL_IMAGE}"
    else
        update_component_image Mariadb "${MARIADB_IMAGE}"
    fi

    if [[ -n "${IRONIC_KEEPALIVED_LOCAL_IMAGE:-}" ]]; then
        update_component_image Keepalived "${IRONIC_KEEPALIVED_LOCAL_IMAGE}"
    else
        update_component_image Keepalived "${IRONIC_KEEPALIVED_IMAGE}"
    fi

    if [[ -n "${IPA_DOWNLOADER_LOCAL_IMAGE:-}" ]]; then
        update_component_image IPA-downloader "${IPA_DOWNLOADER_LOCAL_IMAGE}"
    else
        update_component_image IPA-downloader "${IPA_DOWNLOADER_IMAGE}"
    fi

    if [[ "${EPHEMERAL_CLUSTER}" != "minikube" ]]; then
        update_images
        ${RUN_LOCAL_IRONIC_SCRIPT}
        # Wait for ironic to become ready
        echo "Waiting for Ironic to become ready"
        retry sudo "${CONTAINER_RUNTIME}" exec ironic /bin/ironic-readiness
    else
        # Deploy Ironic using deploy.sh script
        "${BMOPATH}/tools/deploy.sh" -i "${BMO_IRONIC_ARGS[@]}"
    fi
    popd
}

launch_ironic_standalone_operator()
{
    # TODO(dtantsur): IPA branch support
    # shellcheck disable=SC2311
    cat > "${IRSOPATH}/config/manager/manager.env" <<EOF
IRONIC_IMAGE=$(get_component_image "${IRONIC_LOCAL_IMAGE:-${IRONIC_IMAGE}}")
MARIADB_IMAGE=$(get_component_image "${MARIADB_LOCAL_IMAGE:-${MARIADB_IMAGE}}")
KEEPALIVED_IMAGE=$(get_component_image "${IRONIC_KEEPALIVED_LOCAL_IMAGE:-${IRONIC_KEEPALIVED_IMAGE}}")
RAMDISK_DOWNLOADER_IMAGE=$(get_component_image "${IPA_DOWNLOADER_LOCAL_IMAGE:-${IPA_DOWNLOADER_IMAGE}}")
EOF

    # shellcheck disable=SC2311
    make -C "${IRSOPATH}" install deploy IMG="$(get_component_image "${IRSO_LOCAL_IMAGE:-${IRSO_IMAGE}}")"
    kubectl wait --for=condition=Available --timeout=60s \
        -n ironic-standalone-operator-system deployment/ironic-standalone-operator-controller-manager
}

launch_ironic_via_irso()
{
    if [[ "${IRONIC_BASIC_AUTH}" != "true" ]]; then
        echo "Not possible to use ironic-standalone-operator without authentication"
        exit 1
    fi

    kubectl create secret generic ironic-auth -n "${IRONIC_NAMESPACE}" \
        --from-file=username="${IRONIC_AUTH_DIR}ironic-username"  \
        --from-file=password="${IRONIC_AUTH_DIR}ironic-password"

    local ironic="${IRONIC_DATA_DIR}/ironic.yaml"
    cat > "${ironic}" <<EOF
---
apiVersion: metal3.io/v1alpha1
kind: Ironic
metadata:
  name: ironic
  namespace: "${IRONIC_NAMESPACE}"
spec:
  credentialsRef:
    name: ironic-auth
  networking:
    dhcp:
      rangeBegin: "${CLUSTER_DHCP_RANGE_START}"
      rangeEnd: "${CLUSTER_DHCP_RANGE_END}"
      networkCIDR: "${BARE_METAL_PROVISIONER_NETWORK}"
    interface: "${BARE_METAL_PROVISIONER_INTERFACE}"
    ipAddress: "${CLUSTER_BARE_METAL_PROVISIONER_IP}"
    ipAddressManager: keepalived
  deployRamdisk:
    sshKey: "${SSH_PUB_KEY_CONTENT}"
EOF

    if [[ "${NODES_PLATFORM}" = "libvirt" ]]; then
        cat >> "${ironic}" <<EOF
    extraKernelParams: "console=ttyS0"
EOF
    fi

    if [[ -r "${IRONIC_CERT_FILE}" ]] && [[ -r "${IRONIC_KEY_FILE}" ]]; then
        kubectl create secret tls ironic-cert -n "${IRONIC_NAMESPACE}" --key="${IRONIC_KEY_FILE}" --cert="${IRONIC_CERT_FILE}"
        cat >> "${ironic}" <<EOF
  tlsRef:
    name: ironic-cert
EOF
    fi

    # This is not used by Ironic currently but is needed by BMO
    if [[ -r "${IRONIC_CACERT_FILE}" ]] && [[ -r "${IRONIC_CAKEY_FILE}" ]]; then
        kubectl create secret tls ironic-cacert -n "${IRONIC_NAMESPACE}" --key="${IRONIC_CAKEY_FILE}" --cert="${IRONIC_CACERT_FILE}"
    fi

    if [[ "${IRONIC_USE_MARIADB}" = "true" ]]; then
        cat >> "${ironic}" <<EOF
  databaseRef:
    name: ironic-db
---
apiVersion: metal3.io/v1alpha1
kind: IronicDatabase
metadata:
  name: ironic-db
  namespace: "${IRONIC_NAMESPACE}"
spec: {}
EOF
  fi

    # NOTE(dtantsur): the webhook may not be ready immediately, retry if needed
    while ! kubectl create -f "${ironic}"; do
        sleep 3
    done

    if ! kubectl wait --for=condition=Ready --timeout="${IRONIC_ROLLOUT_WAIT}m" -n "${IRONIC_NAMESPACE}" ironic/ironic; then
        # FIXME(dtantsur): remove this when Ironic objects are collected in the CI
        kubectl get -n "${IRONIC_NAMESPACE}" -o yaml ironic/ironic
        if [[ "${IRONIC_USE_MARIADB}" = "true" ]]; then
            kubectl get -n "${IRONIC_NAMESPACE}" -o yaml ironicdatabase/ironic-db
        fi
        exit 1
    fi
}

#
# Launch and configure fakeIPA
#
launch_fake_ipa()
{
    # Create a folder to host fakeIPA config and certs
    mkdir -p "${WORKING_DIR}/fake-ipa"
    if [[ "${EPHEMERAL_CLUSTER}" = "kind" ]] && [[ "${IRONIC_TLS_SETUP}" = "true" ]]; then
        cp "${IRONIC_CACERT_FILE}" "${WORKING_DIR}/fake-ipa/ironic-ca.crt"
    elif [[ "${IRONIC_TLS_SETUP}" = "true" ]]; then
        # wait for ironic to be running to ensure ironic-cert is created
        kubectl -n baremetal-operator-system wait --for=condition=available deployment/baremetal-operator-ironic --timeout=900s
        # Extract ironic-cert to be used inside fakeIPA for TLS
        kubectl get secret -n baremetal-operator-system ironic-cert -o json -o=jsonpath="{.data.ca\.crt}" | base64 -d > "${WORKING_DIR}/fake-ipa/ironic-ca.crt"
    fi

    # Create fake IPA custom config
    cat <<EOF > "${WORKING_DIR}/fake-ipa/config.py"
FAKE_IPA_API_URL = "https://${CLUSTER_BARE_METAL_PROVISIONER_IP}:${IRONIC_API_PORT}"
FAKE_IPA_INSPECTION_CALLBACK_URL = "${IRONIC_URL}/continue_inspection"
FAKE_IPA_ADVERTISE_ADDRESS_IP = "${EXTERNAL_SUBNET_V4_HOST}"
FAKE_IPA_INSECURE = ${FAKE_IPA_INSECURE:-False}
FAKE_IPA_CAFILE = "${FAKE_IPA_CAFILE:-/root/cert/ironic-ca.crt}"
FAKE_IPA_MIN_BOOT_TIME = ${FAKE_IPA_MIN_BOOT_TIME:-20}
FAKE_IPA_MAX_BOOT_TIME = ${FAKE_IPA_MAX_BOOT_TIME:-30}
EOF

    # shellcheck disable=SC2086
    sudo "${CONTAINER_RUNTIME}" run -d --net host --name fake-ipa ${POD_NAME_INFRA} \
        -v "/opt/metal3-dev-env/fake-ipa":/root/cert -v "/root/.ssh":/root/ssh \
        -e CONFIG='/root/cert/config.py' \
        "${FAKE_IPA_IMAGE}"
}


# ------------
# BMH Creation
# ------------

#
# Create the BMH CRs
#
make_bm_hosts()
{
    mkdir -p "${WORKING_DIR}/bmhs"

    local i=0
    while read -r name address user password mac; do
        go run "${BMOPATH}"/cmd/make-bm-worker/main.go \
            -address "${address}" \
            -password "${password}" \
            -user "${user}" \
            -boot-mac "${mac}" \
            -boot-mode "${BOOT_MODE}" \
            "${name}" | \
            tee "${WORKING_DIR}/bmhs/node_${i}.yaml" >> "${WORKING_DIR}/bmhosts_crs.yaml"
        i=$((i+1))
    done
}

#
# Apply the BMH CRs
#
apply_bm_hosts()
{
    local namespace="$1"
    pushd "${BMOPATH}"

    list_nodes | make_bm_hosts
    if [[ -n "$(list_nodes)" ]]; then
        echo "bmhosts_crs.yaml is applying"
        while ! kubectl apply -f "${WORKING_DIR}/bmhosts_crs.yaml" -n "${namespace}" &>/dev/null; do
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
update_capm3_imports()
{
    pushd "${CAPM3PATH}"

    make kustomize
    ./hack/tools/bin/kustomize build "${IPAMPATH}/config/default" > config/ipam/metal3-ipam-components.yaml

    sed -i -e "s#https://github.com/metal3-io/ip-address-manager/releases/download/v.*/ipam-components.yaml#metal3-ipam-components.yaml#" "config/ipam/kustomization.yaml"
    popd
}

get_component_image()
{
    local orig_image=$1
    # Split the image IMAGE_NAME AND IMAGE_TAG, if any tag exist
    local tmp_image="${orig_image##*/}"
    # Remove the digest (already considered when caching the image)
    tmp_image="${tmp_image%@*}"
    local tmp_image_name="${tmp_image%%:*}"
    local tmp_image_tag="${tmp_image##*:}"

    # Assign the image tag to latest if there is no tag in the image
    if [[ "${tmp_image_name}" = "${tmp_image_tag}" ]]; then
        tmp_image_tag="latest"
    fi

    echo "${REGISTRY}/localimages/${tmp_image_name}:${tmp_image_tag}"
}

#
# Update the CAPM3 and BMO manifests to use local images as defined in variables
#
update_component_image()
{
    local import="$1"
    local orig_image="$2"
    local tmp_image

    # shellcheck disable=SC2311
    tmp_image="$(get_component_image "${orig_image}")"
    if [[ "${import}" = "IPAM" ]]; then
        export MANIFEST_IMG_IPAM="${tmp_image%:*}"
        export MANIFEST_TAG_IPAM="${tmp_image##*:}"
    else
        export MANIFEST_IMG="${tmp_image%:*}"
        export MANIFEST_TAG="${tmp_image##*:}"
    fi

    # NOTE: It is assumed that we are already in the correct directory to run make
    case "${import}" in
        "BMO")
            make set-manifest-image-bmo
            ;;
        "CAPM3")
            make set-manifest-image
            ;;
        "IPAM")
            make set-manifest-image-ipam
            ;;
        "Ironic")
            make set-manifest-image-ironic
            ;;
        "Mariadb")
            make set-manifest-image-mariadb
            ;;
        "Keepalived")
            make set-manifest-image-keepalived
            ;;
        "IPA-downloader")
            make set-manifest-image-ipa-downloader
            ;;
        *)
            echo "WARNING: unknown image: ${import}"
            ;;
    esac
}

#
# Update the clusterctl deployment files to use local repositories
#
patch_clusterctl()
{
    pushd "${CAPM3PATH}"
    mkdir -p "${CAPI_CONFIG_DIR}"
    touch "${CAPI_CONFIG_DIR}"/clusterctl.yaml

    # At this point the images variables have been updated with update_images
    # Reflect the change in components files
    if [[ -n "${CAPM3_LOCAL_IMAGE:-}" ]]; then
        update_component_image CAPM3 "${CAPM3_LOCAL_IMAGE}"
    else
        update_component_image CAPM3 "${CAPM3_IMAGE}"
    fi

    if [[ -n "${IPAM_LOCAL_IMAGE:-}" ]]; then
        update_component_image IPAM "${IPAM_LOCAL_IMAGE}"
    else
        update_component_image IPAM "${IPAM_IMAGE}"
    fi

    update_capm3_imports
    make release-manifests

    rm -rf "${CAPI_CONFIG_DIR}"/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
    mkdir -p "${CAPI_CONFIG_DIR}"/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
    cp out/*.yaml "${CAPI_CONFIG_DIR}"/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
    popd
}

# Install clusterctl client
# TODO: use download_and_verify_clusterctl
# Currently we just download latest CAPIRELEASE version, which means we don't know
# the expected SHA, and can't pin it
install_clusterctl()
{
    wget --no-verbose -O clusterctl "https://github.com/kubernetes-sigs/cluster-api/releases/download/${CAPIRELEASE}/clusterctl-linux-amd64"
    chmod +x ./clusterctl
    sudo mv ./clusterctl /usr/local/bin/
}

if ! [[ -x "$(command -v clusterctl)" ]]; then
    install_clusterctl
elif [[ "$(clusterctl version | grep -o -P '(?<=GitVersion:").*?(?=",)')" != "${CAPIRELEASE}" ]]; then
    sudo rm /usr/local/bin/clusterctl
    install_clusterctl
fi

#
# Launch the cluster-api provider metal3.
#
launch_cluster_api_provider_metal3()
{
    pushd "${CAPM3PATH}"

    # shellcheck disable=SC2153
    clusterctl init --core cluster-api:"${CAPIRELEASE}" --bootstrap kubeadm:"${CAPIRELEASE}" \
        --control-plane kubeadm:"${CAPIRELEASE}" --infrastructure=metal3:"${CAPM3RELEASE}"  -v5

    if [[ "${CAPM3_RUN_LOCAL}" = true ]]; then
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

render_j2_config ()
{
    "${ANSIBLE_VENV}/bin/python" -c 'import os; import sys; import jinja2; sys.stdout.write(jinja2.Template(sys.stdin.read()).render(env=os.environ))' < "${1}"
}

#
# Write out a clouds.yaml for this environment
#
create_clouds_yaml()
{
    # To bind this into the ironic-client container we need a directory
    mkdir -p "${SCRIPTDIR}"/_clouds_yaml
    if [[ "${IRONIC_TLS_SETUP}" = "true" ]]; then
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
launch_kind()
{
    cat <<EOF | sudo su -l -c "kind create cluster --name kind --image=${KIND_NODE_IMAGE} --config=- " "${USER}"
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
start_management_cluster()
{
    local minikube_error

    if [[ "${EPHEMERAL_CLUSTER}" = "kind" ]]; then
        launch_kind
    elif [[ "${EPHEMERAL_CLUSTER}" = "minikube" ]]; then
        # This method, defined in lib/common.sh, will either ensure sockets are up'n'running
        # for CS9 and RHEL9, or restart the libvirtd.service for other DISTRO
        manage_libvirtd

        while /bin/true; do
            minikube_error=0
            sudo su -l -c 'minikube start' "${USER}" || minikube_error=1
            if [[ "${minikube_error}" -eq 0 ]]; then
                break
            fi
        done

        if [[ -n "${MINIKUBE_BMNET_V6_IP:-}" ]]; then
            sudo su -l -c "minikube ssh -- sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0" "${USER}"
            sudo su -l -c "minikube ssh -- sudo ip addr add ${MINIKUBE_BMNET_V6_IP}/64 dev eth3" "${USER}"
        fi

        if [[ "${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY:-}" = "true" ]]; then
            sudo su -l -c "minikube ssh -- sudo ip -6 addr add ${CLUSTER_BARE_METAL_PROVISIONER_IP}/  ${BARE_METAL_PROVISIONER_CIDR} dev eth2" "${USER}"
        else
            sudo su -l -c "minikube ssh -- sudo brctl addbr ${BARE_METAL_PROVISIONER_INTERFACE}" "${USER}"
            sudo su -l -c "minikube ssh -- sudo ip link set ${BARE_METAL_PROVISIONER_INTERFACE} up" "${USER}"
            sudo su -l -c "minikube ssh -- sudo brctl addif ${BARE_METAL_PROVISIONER_INTERFACE} eth2" "${USER}"
            sudo su -l -c "minikube ssh -- sudo ip addr add ${INITIAL_BARE_METAL_PROVISIONER_BRIDGE_IP}/${BARE_METAL_PROVISIONER_CIDR} dev ${BARE_METAL_PROVISIONER_INTERFACE}" "${USER}"
        fi
    fi
}

build_ipxe_firmware()
{
    # Build iPXE firmware during deployment (only available on ubuntu)
    # vars with CENV_ARG postfix are container environment variable arguments
    # and only used to pass the env var to the containers
    local ipxe_builder_image="${REGISTRY}/localimages/ipxe-builder:latest"
    export IPXE_ENABLE_TLS_CENV_ARG="IPXE_ENABLE_TLS='false'"
    export IPXE_ENABLE_IPV6_CENV_ARG="IPXE_ENABLE_IPV6='false'"
    declare -a certs_mounts=()

    if [[ "${BUILD_IPXE}" != "true" ]]; then
        return 0
    fi

    if [[ ! -r "${IPXE_SOURCE_DIR}" ]]; then
        git clone --depth 1 --branch "${IPXE_RELEASE_BRANCH}" \
            "https://github.com/ipxe/ipxe.git" "${IPXE_SOURCE_DIR}"
        chmod -R 777 "${IPXE_SOURCE_DIR}"
    elif [[ "${IPXE_SOURCE_FORCE_UPDATE}" = "true" ]]; then
        rm -rf "/tmp/ipxe-source"
        # shellcheck disable=SC2086
        git clone --depth 1 --branch "${IPXE_RELEASE_BRANCH}" \
            "https://github.com/ipxe/ipxe.git" "/tmp/ipxe-source"
        rm -rf "${IPXE_SOURCE_DIR}"
        mv "/tmp/ipxe-source" "${IPXE_SOURCE_DIR}"
        rm -rf "/tmp/ipxe-source"
    fi

    if [[ "${IPXE_ENABLE_TLS}" = "true" ]]; then
        export IPXE_ENABLE_TLS_CENV_ARG="IPXE_ENABLE_TLS=true"
        certs_mounts+=("-v ${IPXE_CACERT_FILE}:/certs/ca/ipxe/tls.crt")
        certs_mounts+=("-v ${IPXE_CERT_FILE}:/certs/ipxe/tls.crt")
        certs_mounts+=("-v ${IPXE_KEY_FILE}:/certs/ipxe/tls.key ")
    fi

    if [[ "${IPXE_ENABLE_IPV6}" = "true" ]]; then
        export IPXE_ENABLE_IPV6_CENV_ARG="IPXE_ENABLE_IPV6=true"
    fi

    # shellcheck disable=SC2086,SC2068
    sudo "${CONTAINER_RUNTIME}" run \
        --net host \
        --name ipxe-builder ${POD_NAME} \
        -e "${IPXE_ENABLE_TLS_CENV_ARG}" \
        -e "${IPXE_ENABLE_IPV6_CENV_ARG}" \
        -e "IRONIC_IP=${IRONIC_HOST_IP}" \
        ${certs_mounts[@]} \
        -v "${IRONIC_DATA_DIR}":/shared \
        "${ipxe_builder_image}"
}


# -----------------------------
# Deploy the management cluster
# -----------------------------

# Kill and remove the running ironic containers
"${BMOPATH}"/tools/remove_local_ironic.sh
create_clouds_yaml

if [[ "${EPHEMERAL_CLUSTER}" = "tilt" ]]; then
    # shellcheck disable=SC1091
    . tilt-setup/deploy_tilt_env.sh
    exit 0
fi

build_ipxe_firmware
start_management_cluster
kubectl create namespace metal3

patch_clusterctl
launch_cluster_api_provider_metal3
BMO_NAME_PREFIX="${NAMEPREFIX}"
launch_baremetal_operator
launch_ironic_standalone_operator
if [[ "${USE_IRSO}" = true ]]; then
    launch_ironic_via_irso
else
    launch_ironic
fi

if [[ "${BMO_RUN_LOCAL}" != true ]]; then
    if ! kubectl rollout status deployment "${BMO_NAME_PREFIX}"-controller-manager -n "${IRONIC_NAMESPACE}" --timeout="${BMO_ROLLOUT_WAIT}"m; then
        echo "baremetal-operator-controller-manager deployment can not be rollout"
        exit 1
    fi
else
    # There is no certificate to run validation webhook on local.
    # Thus we are deleting validatingwebhookconfiguration resource if exists
    # to let BMO is working properly on local runs.
    kubectl delete validatingwebhookconfiguration/"${BMO_NAME_PREFIX}"-validating-webhook-configuration --ignore-not-found=true
fi

# Tests might want to apply bmh inside the test scipt
# then dev-env will create the bmh files but do not apply them
if [[ "${SKIP_APPLY_BMH:-false}" = "true" ]]; then
    pushd "${BMOPATH}"
    list_nodes | make_bm_hosts
    popd
else
    # this is coming from lib/common.sh
    # shellcheck disable=SC2153
    apply_bm_hosts "${NAMESPACE}"
fi

# if fake platform (no VMs) run FakeIPA
if [[ "${NODES_PLATFORM}" = "fake" ]]; then
    launch_fake_ipa
fi
