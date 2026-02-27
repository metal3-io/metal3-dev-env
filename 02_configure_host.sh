#!/usr/bin/env bash
set -eux

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh
# shellcheck disable=SC1091
source lib/releases.sh
# pre-pull node and container images
# shellcheck disable=SC1091
source lib/image_prepull.sh

# cleanup ci config file if it exists from earlier run
rm -f "${CI_CONFIG_FILE}"

# add registry config for skopeo
cat > "${WORKING_DIR}/registries.conf" <<EOF
unqualified-search-registries = []

[[registry]]
location = "${REGISTRY}"
insecure = true
EOF

# Add usr/local/go/bin to the PATH environment variable
GOBINARY="${GOBINARY:-/usr/local/go/bin}"
if [[ ! "${PATH}" =~ .*(:|^)(${GOBINARY})(:|$).* ]]; then
    echo "export PATH=${PATH}:${GOBINARY}" >> ~/.bashrc
    export PATH=${PATH}:${GOBINARY}
fi

# Allow local non-root-user access to libvirt
# shellcheck disable=SC2312
if ! id "${USER}" | grep -q libvirt; then
    sudo usermod -a -G "libvirt" "${USER}"
fi

# Clean-up any old ironic containers
remove_ironic_containers

# Clean-up existing pod, if podman
case "${CONTAINER_RUNTIME}" in
    podman)
        for pod in ironic-pod infra-pod; do
            if  sudo "${CONTAINER_RUNTIME}" pod exists "${pod}" ; then
                sudo "${CONTAINER_RUNTIME}" pod rm "${pod}" -f
            fi
            sudo "${CONTAINER_RUNTIME}" pod create -n "${pod}"
        done
        ;;
    *)
        ;;
esac

# (workaround) disable tdp_mmu to avoid
# kernel crashes with  NULL pointer dereference
# note(elfosardo): run this only if we have kvm support
if grep -q vmx /proc/cpuinfo; then
    sudo modprobe -r -a kvm_intel kvm
    sudo modprobe kvm tdp_mmu=0
    sudo modprobe -a kvm kvm_intel
elif grep -q svm /proc/cpuinfo; then
    sudo modprobe -r -a kvm_amd kvm
    sudo modprobe kvm tdp_mmu=0
    sudo modprobe -a kvm kvm_amd
fi

# Clean, copy and extract local IPA
if [[ "${USE_LOCAL_IPA}" == "true" ]]; then
    sudo rm -f  "${IRONIC_DATA_DIR}/html/images/ironic-python-agent*"
    sudo cp "${LOCAL_IPA_PATH}/ironic-python-agent.tar" "${IRONIC_DATA_DIR}/html/images"
    sudo tar --extract --file "${IRONIC_DATA_DIR}/html/images/ironic-python-agent.tar" \
        --directory "${IRONIC_DATA_DIR}/html/images"
    # avoid duplicating the same process in BMO run_local script
    export USE_LOCAL_IPA="false"
fi

configure_minikube()
{
    "${MINIKUBE}" config set driver kvm2
    "${MINIKUBE}" config set memory 4096
}

#
# Create Minikube VM and add correct interfaces
#
init_minikube()
{
    #If the vm exists, it has already been initialized
    if [[ ! "$(sudo virsh list --name --all)" =~ .*(minikube).* ]]; then
        # Loop to ignore minikube issues
        while /bin/true; do
            minikube_error=0
            # This method, defined in lib/common.sh, will either ensure sockets are up'n'running
            # for CS9 and RHEL9, or restart the libvirtd.service for other DISTRO
            manage_libvirtd
            configure_minikube
            #NOTE(elfosardo): workaround for https://bugzilla.redhat.com/show_bug.cgi?id=2057769
            sudo mkdir -p "/etc/qemu/firmware"
            sudo touch "/etc/qemu/firmware/50-edk2-ovmf-amdsev.json"
            sudo su -l -c "${MINIKUBE} start --insecure-registry ${REGISTRY}" "${USER}" || minikube_error=1
            if [[ ${minikube_error} -eq 0 ]]; then
                break
            fi
            sudo su -l -c "${MINIKUBE} delete --all --purge" "${USER}"
            # NOTE (Mohammed): workaround for https://github.com/kubernetes/minikube/issues/9878
            if ip link show virbr0 > /dev/null 2>&1; then
                sudo ip link delete virbr0
            fi
        done
        sudo su -l -c "${MINIKUBE} stop" "${USER}"
    fi

    MINIKUBE_IFACES="$(sudo virsh domiflist minikube)"

    # The interface doesn't appear in the minikube VM with --live,
    # so just attach it before next boot. As long as the
    # 02_configure_host.sh script does not run, the provisioning network does
    # not exist. Attempting to start Minikube will fail until it is created.
    if ! echo "${MINIKUBE_IFACES}" | grep -w -q provisioning; then
        sudo virsh attach-interface --domain minikube \
            --model virtio --source provisioning \
            --type network --config
    fi

    if ! echo "${MINIKUBE_IFACES}" | grep -w -q external; then
        sudo virsh attach-interface --domain minikube \
            --model virtio --source external \
            --type network --config
    fi
}

if [[ "${BOOTSTRAP_CLUSTER}" == "minikube" ]]; then
    init_minikube
fi

# Root needs a private key to talk to libvirt
# See tripleo-quickstart-config/roles/virtbmc/tasks/configure-vbmc.yml
if ! sudo test -f /root/.ssh/id_rsa_virt_power; then
    sudo ssh-keygen -f /root/.ssh/id_rsa_virt_power -P ""
    sudo cat /root/.ssh/id_rsa_virt_power.pub | sudo tee -a /root/.ssh/authorized_keys
fi

ANSIBLE_FORCE_COLOR=true "${ANSIBLE}-playbook" \
    -e "working_dir=${WORKING_DIR}" \
    -e "num_nodes=${NUM_NODES}" \
    -e "extradisks=${VM_EXTRADISKS}" \
    -e "virthost=${HOSTNAME}" \
    -e "vm_platform=${NODES_PLATFORM}" \
    -e "libvirt_firmware=${LIBVIRT_FIRMWARE}" \
    -e "libvirt_secure_boot=${LIBVIRT_SECURE_BOOT}" \
    -e "libvirt_domain_type=${LIBVIRT_DOMAIN_TYPE}" \
    -e "default_memory=${TARGET_NODE_MEMORY}" \
    -e "manage_external=${MANAGE_EXT_BRIDGE}" \
    -e "provisioning_url_host=${BARE_METAL_PROVISIONER_URL_HOST}" \
    -e "nodes_file=${NODES_FILE}" \
    -e "fake_nodes_file=${FAKE_NODES_FILE}" \
    -e "node_hostname_format=${NODE_HOSTNAME_FORMAT}" \
    -i vm-setup/inventory.ini \
    -b vm-setup/setup-playbook.yml

# Usually virt-manager/virt-install creates this: https://www.redhat.com/archives/libvir-list/2008-August/msg00179.html
if ! sudo virsh pool-uuid default > /dev/null 2>&1 ; then
    sudo virsh pool-define /dev/stdin <<EOF
<pool type='dir'>
    <name>default</name>
    <target>
        <path>/var/lib/libvirt/images</path>
    </target>
</pool>
EOF
    sudo virsh pool-start default
    sudo virsh pool-autostart default
fi

# When running kind ironic is running on the host, hence we need ironicendpoint
# interface on the host.
configure_kind_network() {
    if [[ ! -e /etc/NetworkManager/system-connections/provisioning.nmconnection ]]; then
        # Don't define an IP address to the bridge, put both into ironicendpoint.
        # ironicendpoint needs 2 IP-addresses for keepalived.
        sudo tee -a /etc/NetworkManager/system-connections/provisioning.nmconnection <<EOF
[connection]
id=provisioning
type=bridge
interface-name=provisioning

[bridge]
stp=false
EOF
    fi
    sudo chmod 600 /etc/NetworkManager/system-connections/provisioning.nmconnection
    sudo nmcli con load /etc/NetworkManager/system-connections/provisioning.nmconnection
    sudo nmcli con up provisioning

    sudo ip link add ironicendpoint type veth peer name ironic-peer
    sudo ip link set ironic-peer master provisioning

    if [[ "${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY}" = "true" ]]; then
        sudo ip -6 addr add dev ironicendpoint "${BARE_METAL_PROVISIONER_IP}"/"${BARE_METAL_PROVISIONER_CIDR}"
        sudo ip -6 addr add dev ironicendpoint "${CLUSTER_BARE_METAL_PROVISIONER_IP}"/32
    else
        sudo ip addr add dev ironicendpoint "${BARE_METAL_PROVISIONER_IP}"/"${BARE_METAL_PROVISIONER_CIDR}"
        sudo ip addr add dev ironicendpoint "${CLUSTER_BARE_METAL_PROVISIONER_IP}"/32
    fi
    sudo ip link set ironicendpoint up
    sudo ip link set ironic-peer up
}

# When running minikube, ironic is running inside the cluster, provisioning named
# interface on the host is enough
configure_minikube_network() {
    if [[ "${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY}" == "true" ]]; then
        # Adding an IP address in the libvirt definition for this network results in
        # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
        # the IP address here
        sudo tee -a /etc/NetworkManager/system-connections/provisioning.nmconnection <<EOF
[connection]
id=provisioning
type=bridge
interface-name=provisioning

[bridge]
stp=false

[ipv4]
method=disabled

[ipv6]
addr-gen-mode=eui64
address1=${BARE_METAL_PROVISIONER_IP}/${BARE_METAL_PROVISIONER_CIDR}
method=manual
EOF
    else
        sudo tee -a /etc/NetworkManager/system-connections/provisioning.nmconnection <<EOF
[connection]
id=provisioning
type=bridge
interface-name=provisioning

[bridge]
stp=false

[ipv4]
address1=${BARE_METAL_PROVISIONER_IP}/${BARE_METAL_PROVISIONER_CIDR}
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled
EOF
    fi
    sudo chmod 600 /etc/NetworkManager/system-connections/provisioning.nmconnection
    sudo nmcli con load /etc/NetworkManager/system-connections/provisioning.nmconnection
    sudo nmcli con up provisioning
}

if [[ "${OS}" == "ubuntu" ]]; then
    # source ubuntu_bridge_network_configuration.sh
    # shellcheck disable=SC1091
    source ubuntu_bridge_network_configuration.sh
    # shellcheck disable=SC1091
    source disable_apparmor_driver_libvirtd.sh
else
    if [[ "${MANAGE_PRO_BRIDGE}" == "y" ]]; then
        if [[ ${BOOTSTRAP_CLUSTER} == "kind" ]]; then
            configure_kind_network
        else
            configure_minikube_network
        fi
    fi

    # Need to pass the provision interface for bare metal
    if [[ -n "${PRO_IF}" ]]; then
        sudo tee -a /etc/NetworkManager/system-connections/"${PRO_IF}".nmconnection <<EOF
[connection]
id=${PRO_IF}
type=ethernet
interface-name=${PRO_IF}
master=provisioning
slave-type=bridge
EOF
        sudo chmod 600 /etc/NetworkManager/system-connections/"${PRO_IF}".nmconnection
        sudo nmcli con load /etc/NetworkManager/system-connections/"${PRO_IF}".nmconnection
        sudo nmcli con up "${PRO_IF}"
    fi

    if [[ "${MANAGE_INT_BRIDGE}" == "y" ]]; then
        if [[ "$(nmcli con show)" != *"external"* ]]; then
            sudo tee /etc/NetworkManager/system-connections/external.nmconnection <<EOF
[connection]
id=external
type=bridge
interface-name=external
autoconnect=true

[bridge]
stp=false

[ipv6]
addr-gen-mode=stable-privacy
method=ignore
EOF
            sudo chmod 600 /etc/NetworkManager/system-connections/external.nmconnection
            sudo nmcli con load /etc/NetworkManager/system-connections/external.nmconnection
        fi
    fi
    sudo nmcli connection up external

    # Add the internal interface to it if requests, this may also be the interface providing
    # external access so we need to make sure we maintain dhcp config if its available
    if [[ -n "${INT_IF}" ]]; then
        sudo tee /etc/NetworkManager/system-connections/"${INT_IF}".nmconnection <<EOF
[connection]
id=${INT_IF}
type=ethernet
interface-name=${INT_IF}
master=provisioning
slave-type=bridge
EOF

        sudo chmod 600 /etc/NetworkManager/system-connections/"${INT_IF}".nmconnection
        sudo nmcli con load /etc/NetworkManager/system-connections/"${INT_IF}".nmconnection
        if sudo nmap --script broadcast-dhcp-discover -e "${INT_IF}" | grep "IP Offered" ; then
            sudo nmcli connection modify external ipv4.method auto
        fi
        sudo nmcli connection up "${INT_IF}"
    fi

    # Restart the libvirt network so it applies an ip to the bridge
    if [[ "${MANAGE_EXT_BRIDGE}" == "y" ]]; then
        sudo virsh net-destroy external
        sudo virsh net-start external
        if [[ -n "${INT_IF}" ]]; then
            # Need to bring UP the NIC after destroying the libvirt network
            sudo nmcli connection up "${INT_IF}"
        fi
    fi
fi

ANSIBLE_FORCE_COLOR=true "${ANSIBLE}-playbook" \
    -e "use_firewalld=${USE_FIREWALLD}" \
    -i vm-setup/inventory.ini \
    -b vm-setup/firewall.yml

# FIXME(stbenjam): ansbile firewalld module doesn't seem to be doing the right thing
if [[ "${USE_FIREWALLD}" == "True" ]]; then
    sudo firewall-cmd --zone=libvirt --change-interface=provisioning
    sudo firewall-cmd --zone=libvirt --change-interface=external
fi

# Need to route traffic from the provisioning host.
if [[ -n "${EXT_IF}" ]]; then
    sudo iptables -t nat -A POSTROUTING --out-interface "${EXT_IF}" -j MASQUERADE
    sudo iptables -A FORWARD --in-interface external -j ACCEPT
fi

# Local registry for images
reg_state=$(sudo "${CONTAINER_RUNTIME}" inspect registry --format "{{.State.Status}}" || echo "error")

# ubuntu_install_requirements.sh script restarts docker daemon which causes local registry container to be in exited state.
if [[ "${reg_state}" == "exited" ]]; then
    sudo "${CONTAINER_RUNTIME}" start registry
elif [[ "${reg_state}" != "running" ]]; then
    sudo "${CONTAINER_RUNTIME}" rm registry -f || true
    sudo "${CONTAINER_RUNTIME}" run -d -p "${REGISTRY}":5000 --name registry "${DOCKER_REGISTRY_IMAGE}"
fi
sleep 5

detect_mismatch()
{
    local LOCAL_IMAGE="$1"
    local REPO_PATH="$2"
    if [[ -z "${LOCAL_IMAGE}" ]] || [[ "${LOCAL_IMAGE}" == "${REPO_PATH}" ]]; then
        echo "Local image: ${LOCAL_IMAGE} and repo path: ${REPO_PATH} are matching!"
    else
        echo "There is a mismatch between LOCAL_IMAGE:${LOCAL_IMAGE} and IMAGE_PATH:${REPO_PATH}"
        echo "The mismatch could cause difficult to debug errors, PLEASE FIX!"
        exit 1
    fi

}
# Clone all needed repositories (CAPI, CAPM3, BMO, IPAM)
# The repos cloned under M3PATH has two functions, building images and
# providing manifest generation functionality
mkdir -p "${M3PATH}"
# When building local images make sure FORCE_REPO_UPDATE is set to 'false'
# otherwise clone_repo will overwrite the content of whatever is at the end
# of the path
detect_mismatch "${BMO_LOCAL_IMAGE:-}" "${BMOPATH}"
clone_repo "${BMOREPO}" "${BMOBRANCH}" "${BMOPATH}" "${BMOCOMMIT}"

detect_mismatch "${CAPM3_LOCAL_IMAGE:-}" "${CAPM3PATH}"
clone_repo "${CAPM3REPO}" "${CAPM3BRANCH}" "${CAPM3PATH}" "${CAPM3COMMIT}"

detect_mismatch "${IPAM_LOCAL_IMAGE:-}" "${IPAMPATH}"
clone_repo "${IPAMREPO}" "${IPAMBRANCH}" "${IPAMPATH}" "${IPAMCOMMIT}"

detect_mismatch "${CAPI_LOCAL_IMAGE:-}" "${CAPIPATH}"
clone_repo "${CAPIREPO}" "${CAPIBRANCH}" "${CAPIPATH}" "${CAPICOMMIT}"

detect_mismatch "${IRSO_LOCAL_IMAGE:-}" "${IRSOPATH}"
clone_repo "${IRSOREPO}" "${IRSOBRANCH}" "${IRSOPATH}" "${IRSOCOMMIT}"

# MariaDB and Ironic source is not needed unless the images are built locally
# If the repo path does not match with the IMAGE location that means the image
# is built from a repo that is not under dev-env's control thus there is no
# need to clone the repo.
# There is no need to keep the PATH and the IMAGE vars in sync as there
# is no other use of the path variable than cloning
if [[ "${MARIADB_LOCAL_IMAGE:-}" == "${MARIADB_IMAGE_PATH}" ]]; then
    clone_repo "${MARIADB_IMAGE_REPO}" "${MARIADB_IMAGE_BRANCH}" "${MARIADB_IMAGE_PATH}" "${MARIADB_IMAGE_COMMIT}"
fi

if [[ "${IRONIC_LOCAL_IMAGE:-}" == "${IRONIC_IMAGE_PATH}" ]]; then
    clone_repo "${IRONIC_IMAGE_REPO}" "${IRONIC_IMAGE_BRANCH}" "${IRONIC_IMAGE_PATH}" "${IRONIC_IMAGE_COMMIT}"
fi

# Support for building local images
for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*"); do
    IMAGE_REPO_PATH="${!IMAGE_VAR}"
    cd "${IMAGE_REPO_PATH}" || exit

    IMAGE_DIR_NAME=$(basename "${IMAGE_REPO_PATH}")
    IMAGE_URL="${REGISTRY}/localimages/${IMAGE_DIR_NAME}"
    export "${IMAGE_VAR}"="${IMAGE_URL}"

    IMAGE_GIT_HASH="$(git rev-parse --short HEAD || echo "nogit")"
    # [year]_[day]_[hour][minute]
    IMAGE_DATE="$(date -u +%y_%j_%H%M)"

    # Support building ironic-image from source
    if [[ "${IMAGE_VAR/_LOCAL_IMAGE}" == "IRONIC" ]] && [[ ${IRONIC_FROM_SOURCE:-} == "true" ]]; then
        # NOTE(rpittau): to customize the source origin we need to copy the source code we
        # want to use into the sources directory under the ironic-image repository.
        for CODE_SOURCE_VAR in $(env | grep -E '^IRONIC_SOURCE=|^IRONIC_INSPECTOR_SOURCE=|^SUSHY_SOURCE=' | grep -o "^[^=]*"); do
            CODE_SOURCE="${!CODE_SOURCE_VAR}"
            SOURCE_DIR_DEST="${CODE_SOURCE##*/}"
            rm -rf "./sources/${SOURCE_DIR_DEST}"
            cp -a "${CODE_SOURCE}" "./sources/${SOURCE_DIR_DEST}"
            CUSTOM_SOURCE_ARGS+="--build-arg ${CODE_SOURCE_VAR}=${SOURCE_DIR_DEST} "
        done

        # shellcheck disable=SC2086
        sudo "${CONTAINER_RUNTIME}" build --build-arg INSTALL_TYPE=source ${CUSTOM_SOURCE_ARGS:-} \
            -t "${IMAGE_URL}:latest" -t "${IMAGE_URL}:${IMAGE_GIT_HASH}_${IMAGE_DATE}" . -f ./Dockerfile

    # TODO: Do we want to support CAPI in dev-env? CI just pulls it anyways ...
    elif [[ "${IMAGE_VAR/_LOCAL_IMAGE}" == "CAPI" ]]; then
        CAPI_GO_VERSION=$(grep "GO_VERSION ?= [0-9].*" Makefile | sed -e 's/GO_VERSION ?= //g')
        # shellcheck disable=SC2016
        CAPI_BASEIMAGE=$(grep "GO_CONTAINER_IMAGE ?=" Makefile | sed -e 's/GO_CONTAINER_IMAGE ?= //g' -e 's/$(GO_VERSION)//g')
        CAPI_TAGGED_BASE_IMAGE="${CAPI_BASEIMAGE}${CAPI_GO_VERSION}"
        sudo DOCKER_BUILDKIT=1 "${CONTAINER_RUNTIME}" build \
            --build-arg builder_image="${CAPI_TAGGED_BASE_IMAGE}" --build-arg ARCH="amd64" \
            -t "${IMAGE_URL}:latest" -t "${IMAGE_URL}:${IMAGE_GIT_HASH}_${IMAGE_DATE}" . -f ./Dockerfile

    else
        sudo "${CONTAINER_RUNTIME}" rmi "${IMAGE_URL}" || true
        sudo "${CONTAINER_RUNTIME}" build -t "${IMAGE_URL}" . -f ./Dockerfile
    fi

    cd - || exit
    if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
        sudo "${CONTAINER_RUNTIME}" push --tls-verify=false "${IMAGE_URL}"
    else
        sudo "${CONTAINER_RUNTIME}" push --platform="${LOCAL_CONTAINER_PLATFORM}" "${IMAGE_URL}"
    fi

    # store the locally built images to config, so they're passed to "make test"
    # and used in pivoting tests etc. Exports from environment are lost between
    # make && make test as make isolates the env
    cat <<EOF >>"${CI_CONFIG_FILE}"
export ${IMAGE_VAR/_LOCAL_IMAGE/_IMAGE}="${IMAGE_URL}"
EOF
done

# unset all *_IMAGE env vars that have a *_LOCAL_IMAGE counterpart to avoid
# tagging and pushing upstream images thus avoid creating duplicates
for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    NO_LOCAL_NAME="${IMAGE_VAR%_LOCAL_IMAGE}_IMAGE"
    unset -v "${NO_LOCAL_NAME}"
done

# IRONIC_IMAGE is also used in this script so when it is built locally and
# consequently unset, it has to be redefined for local use
if [[ "${BUILD_IRONIC_IMAGE_LOCALLY:-}" == "true" ]] || [[ -n "${IRONIC_LOCAL_IMAGE:-}" ]]; then
    IRONIC_IMAGE="${REGISTRY}/localimages/$(basename "${IRONIC_LOCAL_IMAGE}")"
    export IRONIC_IMAGE
fi
VBMC_IMAGE="${VBMC_LOCAL_IMAGE:-${VBMC_IMAGE}}"
SUSHY_TOOLS_IMAGE="${SUSHY_TOOLS_LOCAL_IMAGE:-${SUSHY_TOOLS_IMAGE}}"
FAKE_IPA_IMAGE="${FAKE_IPA_LOCAL_IMAGE:-${FAKE_IPA_IMAGE}}"
FKAS_IMAGE="${FKAS_LOCAL_IMAGE:-${FKAS_IMAGE}}"

# Pushing images to local registry
for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE="${!IMAGE_VAR}"
    # shellcheck disable=SC2086
    IMAGE_NAME="${IMAGE##*/}"
    # shellcheck disable=SC2086
    LOCAL_IMAGE="${REGISTRY}/localimages/${IMAGE_NAME%@*}"
    if [[ "${LOCAL_IMAGE}" != "${IMAGE}" ]]; then
        sudo "${CONTAINER_RUNTIME}" rmi "${LOCAL_IMAGE}" || true
    fi
    if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
        sudo "${CONTAINER_RUNTIME}" tag "${IMAGE}" "${LOCAL_IMAGE}"
        sudo "${CONTAINER_RUNTIME}" push --tls-verify=false "${LOCAL_IMAGE}"
    else
        sudo "${CONTAINER_RUNTIME}" run --rm --network host \
            -v "/${WORKING_DIR}/registries.conf:/etc/containers/registries.conf:ro" \
            quay.io/skopeo/stable:latest \
            copy \
            --dest-tls-verify=false \
            "docker://${IMAGE}" "docker://${LOCAL_IMAGE}"
    fi
done

# Start httpd-infra container
if [[ "${OS}" == "ubuntu" ]]; then
    # shellcheck disable=SC2086
    sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name httpd-infra ${POD_NAME_INFRA} \
        -v "${IRONIC_DATA_DIR}":/shared --entrypoint /bin/runhttpd \
        --env "PROVISIONING_INTERFACE=ironicendpoint" "${IRONIC_IMAGE}"
else
    # shellcheck disable=SC2086
    sudo "${CONTAINER_RUNTIME}" run -d --net host --name httpd-infra ${POD_NAME_INFRA} \
        -v "${IRONIC_DATA_DIR}":/shared --entrypoint /bin/runhttpd "${IRONIC_IMAGE}"
fi

# Start vbmc and sushy containers
# shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --name vbmc ${POD_NAME_INFRA} \
    -v "${WORKING_DIR}/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
    "${VBMC_IMAGE}"

# shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --name sushy-tools ${POD_NAME_INFRA} \
    -v "${WORKING_DIR}/virtualbmc/sushy-tools":/root/sushy -v "/root/.ssh":/root/ssh \
    "${SUSHY_TOOLS_IMAGE}"

# Installing the openstack/ironic clients on the host is optional
# if not installed, we copy a wrapper to OPENSTACKCLIENT_PATH which
# runs the clients in a container (metal3-io/ironic-client)
OPENSTACKCLIENT_PATH="${OPENSTACKCLIENT_PATH:-/usr/local/bin/openstack}"
if ! command -v openstack | grep -v "${OPENSTACKCLIENT_PATH}"; then
    sudo ln -sf "${SCRIPTDIR}/openstackclient.sh" "${OPENSTACKCLIENT_PATH}"
    sudo ln -sf "${SCRIPTDIR}/openstackclient.sh" "$(dirname "${OPENSTACKCLIENT_PATH}")/baremetal"
fi

# Same for the vbmc CLI when not locally installed
VBMC_PATH="${VBMC_PATH:-/usr/local/bin/vbmc}"
if ! command -v vbmc | grep -v "${VBMC_PATH}"; then
    sudo ln -sf "${SCRIPTDIR}/vbmc.sh" "${VBMC_PATH}"
fi
