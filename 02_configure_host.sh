#!/usr/bin/env bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh

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
    -e "default_memory=$DEFAULT_HOSTS_MEMORY" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -e "provisioning_url_host=$PROVISIONING_URL_HOST" \
    -e "nodes_file=$NODES_FILE" \
    -e "node_hostname_format=$NODE_HOSTNAME_FORMAT" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/setup-playbook.yml

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
      if [ ! -e /etc/sysconfig/network-scripts/ifcfg-provisioning ] ; then
        if [[ "${PROVISIONING_IPV6}" == "true" ]]; then
          echo -e "DEVICE=provisioning\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no\nIPV6_AUTOCONF=no\nIPV6INIT=yes\nIPV6ADDR=$PROVISIONING_IP/$PROVISIONING_CIDR" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-provisioning
        else
          echo -e "DEVICE=provisioning\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no\nBOOTPROTO=static\nIPADDR=$PROVISIONING_IP\nNETMASK=$PROVISIONING_NETMASK" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-provisioning
     	  fi
      fi
      sudo ifdown provisioning || true
      sudo ifup provisioning

      # Need to pass the provision interface for bare metal
      if [ "$PRO_IF" ]; then
          echo -e "DEVICE=$PRO_IF\nTYPE=Ethernet\nONBOOT=yes\nNM_CONTROLLED=no\nBRIDGE=provisioning" | sudo dd of="/etc/sysconfig/network-scripts/ifcfg-$PRO_IF"
          sudo ifdown "$PRO_IF" || true
          sudo ifup "$PRO_IF"
      fi
  fi

  if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
      # Create the baremetal bridge
      if [ ! -e /etc/sysconfig/network-scripts/ifcfg-baremetal ] ; then
          echo -e "DEVICE=baremetal\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-baremetal
      fi
      sudo ifdown baremetal || true
      sudo ifup baremetal

      # Add the internal interface to it if requests, this may also be the interface providing
      # external access so we need to make sure we maintain dhcp config if its available
      if [ "$INT_IF" ]; then
          echo -e "DEVICE=$INT_IF\nTYPE=Ethernet\nONBOOT=yes\nNM_CONTROLLED=no\nBRIDGE=baremetal" | sudo dd of="/etc/sysconfig/network-scripts/ifcfg-$INT_IF"
          if sudo nmap --script broadcast-dhcp-discover -e "$INT_IF" | grep "IP Offered" ; then
              echo -e "\nBOOTPROTO=dhcp\n" | sudo tee -a /etc/sysconfig/network-scripts/ifcfg-baremetal
              sudo systemctl restart network
          else
             sudo systemctl restart network
          fi
      fi
  fi

  # Restart the libvirt network so it applies an ip to the bridge
  if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
      sudo virsh net-destroy baremetal
      sudo virsh net-start baremetal
      if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
          sudo ifup "$INT_IF"
      fi
  fi
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "{use_firewalld: $USE_FIREWALLD}" \
    -e "external_subnet_v4: ${EXTERNAL_SUBNET_V4}" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/firewall.yml

# FIXME(stbenjam): ansbile firewalld module doesn't seem to be doing the right thing
if [ "$USE_FIREWALLD" == "True" ]; then
  sudo firewall-cmd --zone=libvirt --change-interface=provisioning
  sudo firewall-cmd --zone=libvirt --change-interface=baremetal
fi

# Need to route traffic from the provisioning host.
if [ "$EXT_IF" ]; then
  sudo iptables -t nat -A POSTROUTING --out-interface "$EXT_IF" -j MASQUERADE
  sudo iptables -A FORWARD --in-interface baremetal -j ACCEPT
fi

# Local registry for images
reg_state=$(sudo "$CONTAINER_RUNTIME" inspect registry --format  "{{.State.Status}}" || echo "error")

# ubuntu_install_requirements.sh script restarts docker daemon which causes local registry container to be in exited state.
if [[ "$reg_state" == "exited" ]]; then
  sudo "${CONTAINER_RUNTIME}" start registry
elif [[ "$reg_state" != "running" ]]; then
  sudo "${CONTAINER_RUNTIME}" rm registry -f || true
  sudo "${CONTAINER_RUNTIME}" run -d -p "${REGISTRY_PORT}":5000 --name registry "$DOCKER_REGISTRY_IMAGE"
fi
sleep 5

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
  BRANCH_IMAGE_VAR="${IMAGE_VAR}_BRANCH"
  IMAGE="${!IMAGE_VAR}"
  BRANCH="${!BRANCH_IMAGE_VAR:-master}"

  # Is it a git repo?
  if [[ "$IMAGE" =~ "://" ]] ; then
    REPOPATH=~/${IMAGE##*/}
    # Clone to ~ if not there already
    if [ -e "${REPOPATH}" ]; then
       cd "${REPOPATH}" || exit
    else
      git clone "${IMAGE}" "${REPOPATH}"
      cd "${REPOPATH}" || exit
      [ "${BRANCH}" = "master" ] || git checkout "${BRANCH}"
    fi
  # Assume it is a path
  else
    cd "${IMAGE}" || exit
  fi

  #shellcheck disable=SC2086
  export $IMAGE_VAR="${IMAGE##*/}"
  #shellcheck disable=SC2086
  export $IMAGE_VAR="${REGISTRY}/localimages/${!IMAGE_VAR}"
  sudo "${CONTAINER_RUNTIME}" build -t "${!IMAGE_VAR}" . -f ./Dockerfile
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
  sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name httpd-infra ${POD_NAME_INFRA} \
      -v "$IRONIC_DATA_DIR":/shared --entrypoint /bin/runhttpd \
      "${IRONIC_IMAGE}"
fi

# Start vbmc and sushy containers
#shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name vbmc ${POD_NAME_INFRA} \
     -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
     "${VBMC_IMAGE}"

#shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name sushy-tools ${POD_NAME_INFRA} \
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
