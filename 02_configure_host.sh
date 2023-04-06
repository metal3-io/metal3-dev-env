#!/usr/bin/env bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh
# shellcheck disable=SC1091
source lib/releases.sh

# Root needs a private key to talk to libvirt
# See tripleo-quickstart-config/roles/virtbmc/tasks/configure-vbmc.yml
if sudo [ ! -f /root/.ssh/id_rsa_virt_power ]; then
  sudo ssh-keygen -f /root/.ssh/id_rsa_virt_power -P ""
  sudo cat /root/.ssh/id_rsa_virt_power.pub | sudo tee -a /root/.ssh/authorized_keys
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "num_nodes=$NUM_NODES" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "platform=$NODES_PLATFORM" \
    -e "libvirt_firmware=$LIBVIRT_FIRMWARE" \
    -e "libvirt_secure_boot=$LIBVIRT_SECURE_BOOT" \
    -e "libvirt_domain_type=$LIBVIRT_DOMAIN_TYPE" \
    -e "default_memory=$DEFAULT_HOSTS_MEMORY" \
    -e "manage_external=$MANAGE_EXT_BRIDGE" \
    -e "provisioning_url_host=$BARE_METAL_PROVISIONER_URL_HOST" \
    -e "nodes_file=$NODES_FILE" \
    -e "node_hostname_format=$NODE_HOSTNAME_FORMAT" \
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

if [[ $OS == ubuntu ]]; then
  # source ubuntu_bridge_network_configuration.sh
  # shellcheck disable=SC1091
  source ubuntu_bridge_network_configuration.sh
  # shellcheck disable=SC1091
  source disable_apparmor_driver_libvirtd.sh
else
  if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
      # Adding an IP address in the libvirt definition for this network results in
      # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
      # the IP address here
      if [ ! -e /etc/NetworkManager/system-connections/provisioning.nmconnection ] ; then
        if [[ "${BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY}" = "true" ]]; then
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
address1=$BARE_METAL_PROVISIONER_IP/$BARE_METAL_PROVISIONER_CIDR
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
address1=$BARE_METAL_PROVISIONER_IP/$BARE_METAL_PROVISIONER_CIDR
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled
EOF
     	  fi
        sudo chmod 600 /etc/NetworkManager/system-connections/provisioning.nmconnection
        sudo nmcli con load /etc/NetworkManager/system-connections/provisioning.nmconnection
      fi
      sudo nmcli con up provisioning

      # Need to pass the provision interface for bare metal
      if [ "$PRO_IF" ]; then
          sudo tee -a /etc/NetworkManager/system-connections/"$PRO_IF".nmconnection <<EOF
[connection]
id=$PRO_IF
type=ethernet
interface-name=$PRO_IF
master=provisioning
slave-type=bridge
EOF
          sudo chmod 600 /etc/NetworkManager/system-connections/"$PRO_IF".nmconnection
          sudo nmcli con load /etc/NetworkManager/system-connections/"$PRO_IF".nmconnection
          sudo nmcli con up "$PRO_IF"
      fi


  if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
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
      if [ "$INT_IF" ]; then
          sudo tee /etc/NetworkManager/system-connections/"$INT_IF".nmconnection <<EOF
[connection]
id=$INT_IF
type=ethernet
interface-name=$INT_IF
master=provisioning
slave-type=bridge
EOF

          sudo chmod 600 /etc/NetworkManager/system-connections/"$INT_IF".nmconnection
          sudo nmcli con load /etc/NetworkManager/system-connections/"$INT_IF".nmconnection
          if sudo nmap --script broadcast-dhcp-discover -e "$INT_IF" | grep "IP Offered" ; then
              sudo nmcli connection modify external ipv4.method auto
          fi
          sudo nmcli connection up "$INT_IF"
      fi
  fi

  # Restart the libvirt network so it applies an ip to the bridge
  if [ "$MANAGE_EXT_BRIDGE" == "y" ] ; then
      sudo virsh net-destroy external
      sudo virsh net-start external
      if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
          sudo nmcli connection up "$INT_IF"
      fi
  fi
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "use_firewalld=${USE_FIREWALLD}" \
    -i vm-setup/inventory.ini \
    -b vm-setup/firewall.yml

# FIXME(stbenjam): ansbile firewalld module doesn't seem to be doing the right thing
if [ "$USE_FIREWALLD" == "True" ]; then
  sudo firewall-cmd --zone=libvirt --change-interface=provisioning
  sudo firewall-cmd --zone=libvirt --change-interface=external
fi

# Need to route traffic from the provisioning host.
if [ "$EXT_IF" ]; then
  sudo iptables -t nat -A POSTROUTING --out-interface "$EXT_IF" -j MASQUERADE
  sudo iptables -A FORWARD --in-interface external -j ACCEPT
fi

# Local registry for images
reg_state=$(sudo "$CONTAINER_RUNTIME" inspect registry --format  "{{.State.Status}}" || echo "error")

# ubuntu_install_requirements.sh script restarts docker daemon which causes local registry container to be in exited state.
if [[ "$reg_state" == "exited" ]]; then
  sudo "${CONTAINER_RUNTIME}" start registry
elif [[ "$reg_state" != "running" ]]; then
  sudo "${CONTAINER_RUNTIME}" rm registry -f || true
  sudo "${CONTAINER_RUNTIME}" run -d -p "${REGISTRY}":5000 --name registry "$DOCKER_REGISTRY_IMAGE"
fi
sleep 5


# Clone all needed repositories (CAPI, CAPM3, BMO, IPAM)
mkdir -p "${M3PATH}"
clone_repo "${BMOREPO}" "${BMOBRANCH}" "${BMOPATH}" "${BMOCOMMIT}"
clone_repo "${CAPM3REPO}" "${CAPM3BRANCH}" "${CAPM3PATH}" "${CAPM3COMMIT}"
clone_repo "${IPAMREPO}" "${IPAMBRANCH}" "${IPAMPATH}" "${IPAMCOMMIT}"
clone_repo "${CAPIREPO}" "${CAPIBRANCH}" "${CAPIPATH}" "${CAPICOMMIT}"
if [[ "${BUILD_MARIADB_IMAGE_LOCALLY:-}" == "true" ]]; then
  clone_repo "${MARIADB_IMAGE_REPO}" "${MARIADB_IMAGE_BRANCH}" "${MARIADB_IMAGE_PATH}" "${MARIADB_IMAGE_COMMIT}"
fi
if [[ ${IRONIC_FROM_SOURCE:-} == "true" || ${BUILD_IRONIC_IMAGE_LOCALLY:-} == "true" ]]; then
    clone_repo "${IRONIC_IMAGE_REPO}" "${IRONIC_IMAGE_BRANCH}" "${IRONIC_IMAGE_PATH}" "${IRONIC_IMAGE_COMMIT}"
fi

# Pushing images to local registry
for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
  IMAGE="${!IMAGE_VAR}"
  #shellcheck disable=SC2086
  IMAGE_NAME="${IMAGE##*/}"
  #shellcheck disable=SC2086
  LOCAL_IMAGE="${REGISTRY}/localimages/${IMAGE_NAME}"
  sudo "${CONTAINER_RUNTIME}" tag "${IMAGE}" "${LOCAL_IMAGE}"

  if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
    sudo "${CONTAINER_RUNTIME}" push --tls-verify=false "${LOCAL_IMAGE}"
  else
    sudo "${CONTAINER_RUNTIME}" push "${LOCAL_IMAGE}"
  fi
done

# Support for building local images
for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
  IMAGE="${!IMAGE_VAR}"
  cd "${IMAGE}" || exit

  #shellcheck disable=SC2086
  export $IMAGE_VAR="${IMAGE##*/}"
  #shellcheck disable=SC2086
  export $IMAGE_VAR="${REGISTRY}/localimages/${!IMAGE_VAR}"
  IMAGE_GIT_HASH="$(git rev-parse --short HEAD || echo "nogit")"
  # [year]_[day]_[hour][minute]
  IMAGE_DATE="$(date -u +%y_%j_%H%M)"

  # Support building ironic-image from source
  if [[ "${IMAGE}" =~ "ironic" ]] && [[ ${IRONIC_FROM_SOURCE:-} == "true" ]]; then
    # NOTE(rpittau): to customize the source origin we need to copy the source code we
    # want to use into the sources directory under the ironic-image repository.
    for CODE_SOURCE_VAR in $(env | grep -E '^IRONIC_SOURCE=|^IRONIC_INSPECTOR_SOURCE=|^SUSHY_SOURCE=' | grep -o "^[^=]*"); do
      CODE_SOURCE="${!CODE_SOURCE_VAR}"
      SOURCE_DIR_DEST="${CODE_SOURCE##*/}"
      cp -a "${CODE_SOURCE}" "./sources/${SOURCE_DIR_DEST}"
      CUSTOM_SOURCE_ARGS+="--build-arg ${CODE_SOURCE_VAR}=${SOURCE_DIR_DEST} "
    done
    #shellcheck disable=SC2086
    sudo "${CONTAINER_RUNTIME}" build --build-arg INSTALL_TYPE=source ${CUSTOM_SOURCE_ARGS:-} -t "${!IMAGE_VAR}:latest" -t "${!IMAGE_VAR}:${IMAGE_GIT_HASH}_${IMAGE_DATE}" . -f ./Dockerfile
  elif [[ "${IMAGE}" =~ "cluster-api" ]]; then
    CAPI_GO_VERSION=$(grep "GO_VERSION ?= [0-9].*" Makefile | sed -e 's/GO_VERSION ?= //g')
    #shellcheck disable=SC2016
    CAPI_BASEIMAGE=$(grep "GO_CONTAINER_IMAGE ?=" Makefile | sed -e 's/GO_CONTAINER_IMAGE ?= //g' -e 's/$(GO_VERSION)//g')
    CAPI_TAGGED_BASE_IMAGE="$CAPI_BASEIMAGE$CAPI_GO_VERSION"
    sudo DOCKER_BUILDKIT=1 "${CONTAINER_RUNTIME}" build --build-arg builder_image="$CAPI_TAGGED_BASE_IMAGE" --build-arg ARCH="amd64" \
        -t "${!IMAGE_VAR}:latest" -t "${!IMAGE_VAR}:${IMAGE_GIT_HASH}_${IMAGE_DATE}" . -f ./Dockerfile
  else
    sudo "${CONTAINER_RUNTIME}" build -t "${!IMAGE_VAR}" . -f ./Dockerfile
  fi

  cd - || exit
  if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
    sudo "${CONTAINER_RUNTIME}" push --tls-verify=false "${!IMAGE_VAR}"
  else
    sudo "${CONTAINER_RUNTIME}" push "${!IMAGE_VAR}"
  fi
done

IRONIC_IMAGE=${IRONIC_LOCAL_IMAGE:-$IRONIC_IMAGE}
VBMC_IMAGE=${VBMC_LOCAL_IMAGE:-$VBMC_IMAGE}
SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_LOCAL_IMAGE:-$SUSHY_TOOLS_IMAGE}

# Start httpd container
if [[ $OS == ubuntu ]]; then
  #shellcheck disable=SC2086
  sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name httpd-infra ${POD_NAME_INFRA} \
      -v "$IRONIC_DATA_DIR":/shared --entrypoint /bin/runhttpd \
      --env "PROVISIONING_INTERFACE=ironicendpoint" "${IRONIC_IMAGE}"
else
  #shellcheck disable=SC2086
  sudo "${CONTAINER_RUNTIME}" run -d --net host --name httpd-infra ${POD_NAME_INFRA} \
      -v "$IRONIC_DATA_DIR":/shared --entrypoint /bin/runhttpd \
      "${IRONIC_IMAGE}"
fi

# Start vbmc and sushy containers
#shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --name vbmc ${POD_NAME_INFRA} \
     -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
     "${VBMC_IMAGE}"

#shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --name sushy-tools ${POD_NAME_INFRA} \
     -v "$WORKING_DIR/virtualbmc/sushy-tools":/root/sushy -v "/root/.ssh":/root/ssh \
     "${SUSHY_TOOLS_IMAGE}"

# Installing the openstack/ironic clients on the host is optional
# if not installed, we copy a wrapper to OPENSTACKCLIENT_PATH which
# runs the clients in a container (metal3-io/ironic-client)
OPENSTACKCLIENT_PATH="${OPENSTACKCLIENT_PATH:-/usr/local/bin/openstack}"
if ! command -v openstack | grep -v "${OPENSTACKCLIENT_PATH}"; then
  sudo ln -sf "${SCRIPTDIR}/openstackclient.sh" "${OPENSTACKCLIENT_PATH}"
  sudo ln -sf "${SCRIPTDIR}/openstackclient.sh" "$(dirname "$OPENSTACKCLIENT_PATH")/baremetal"
fi

# Same for the vbmc CLI when not locally installed
VBMC_PATH="${VBMC_PATH:-/usr/local/bin/vbmc}"
if ! command -v vbmc | grep -v "${VBMC_PATH}"; then
  sudo ln -sf "${SCRIPTDIR}/vbmc.sh" "${VBMC_PATH}"
fi
