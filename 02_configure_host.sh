#!/usr/bin/env bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

# Generate user ssh key
if [ ! -f "$HOME/.ssh/id_rsa.pub" ]; then
    ssh-keygen -f ~/.ssh/id_rsa -P ""
fi

# root needs a private key to talk to libvirt
# See tripleo-quickstart-config/roles/virtbmc/tasks/configure-vbmc.yml
if sudo [ ! -f /root/.ssh/id_rsa_virt_power ]; then
  sudo ssh-keygen -f /root/.ssh/id_rsa_virt_power -P ""
  sudo cat /root/.ssh/id_rsa_virt_power.pub | sudo tee -a /root/.ssh/authorized_keys
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "platform=$NODES_PLATFORM" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/setup-playbook.yml

# Allow local non-root-user access to libvirt
# Restart libvirtd service to get the new group membership loaded
if ! id "$USER" | grep -q libvirt; then
  sudo usermod -a -G "libvirt" "$USER"
  sudo systemctl restart libvirtd
fi
# Usually virt-manager/virt-install creates this: https://www.redhat.com/archives/libvir-list/2008-August/msg00179.html
if ! virsh pool-uuid default > /dev/null 2>&1 ; then
    virsh pool-define /dev/stdin <<EOF
<pool type='dir'>
  <name>default</name>
  <target>
    <path>/var/lib/libvirt/images</path>
  </target>
</pool>
EOF
    virsh pool-start default
    virsh pool-autostart default
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
          echo -e "DEVICE=provisioning\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no\nBOOTPROTO=static\nIPADDR=172.22.0.1\nNETMASK=255.255.255.0" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-provisioning
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

  # restart the libvirt network so it applies an ip to the bridge
  if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
      sudo virsh net-destroy baremetal
      sudo virsh net-start baremetal
      if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
          sudo ifup "$INT_IF"
      fi
  fi
fi

# Add firewall rules to ensure the IPA ramdisk can reach httpd, Ironic and the Inspector API on the host
for port in 80 5050 6385 ; do
    if ! sudo iptables -C INPUT -i provisioning -p tcp -m tcp --dport $port -j ACCEPT > /dev/null 2>&1; then
        sudo iptables -I INPUT -i provisioning -p tcp -m tcp --dport $port -j ACCEPT
    fi
done

# Allow ipmi to the virtual bmc processes that we just started
if ! sudo iptables -C INPUT -i baremetal -p udp -m udp --dport 6230:6235 -j ACCEPT 2>/dev/null ; then
    sudo iptables -I INPUT -i baremetal -p udp -m udp --dport 6230:6235 -j ACCEPT
fi

#Allow access to dhcp and tftp server for pxeboot
for port in 67 69 ; do
    if ! sudo iptables -C INPUT -i provisioning -p udp --dport $port -j ACCEPT 2>/dev/null ; then
        sudo iptables -I INPUT -i provisioning -p udp --dport $port -j ACCEPT
    fi
done

# Need to route traffic from the provisioning host.
if [ "$EXT_IF" ]; then
  sudo iptables -t nat -A POSTROUTING --out-interface "$EXT_IF" -j MASQUERADE
  sudo iptables -A FORWARD --in-interface baremetal -j ACCEPT
fi

# Switch NetworkManager to internal DNS

if [[ "$MANAGE_BR_BRIDGE" == "y" && $OS == "centos" ]] ; then
  sudo mkdir -p /etc/NetworkManager/conf.d/
  sudo crudini --set /etc/NetworkManager/conf.d/dnsmasq.conf main dns dnsmasq
  if [ "$ADDN_DNS" ] ; then
    echo "server=$ADDN_DNS" | sudo tee /etc/NetworkManager/dnsmasq.d/upstream.conf
  fi
  if systemctl is-active --quiet NetworkManager; then
    sudo systemctl reload NetworkManager
  else
    sudo systemctl restart NetworkManager
  fi
fi

for name in ironic ironic-inspector dnsmasq httpd mariadb; do
    sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill $name
    sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm $name -f
done

# set password for mariadb
mariadb_password="$(echo "$(date;hostname)"|sha256sum |cut -c-20)"


if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  # Remove existing pod
  if  sudo "${CONTAINER_RUNTIME}" pod exists ironic-pod ; then
      sudo "${CONTAINER_RUNTIME}" pod rm ironic-pod -f
  fi
  # Create pod
  sudo "${CONTAINER_RUNTIME}" pod create -n ironic-pod
  POD_NAME="--pod ironic-pod"
else
  POD_NAME=""
fi

mkdir -p "$IRONIC_DATA_DIR"

# Start dnsmasq, http, mariadb, and ironic containers using same image
sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name dnsmasq  ${POD_NAME} \
     -v "$IRONIC_DATA_DIR":/shared --entrypoint /bin/rundnsmasq "${IRONIC_IMAGE}"

sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name httpd ${POD_NAME} \
     -v "$IRONIC_DATA_DIR":/shared --entrypoint /bin/runhttpd "${IRONIC_IMAGE}"

sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name mariadb ${POD_NAME} \
     -v "$IRONIC_DATA_DIR":/shared --entrypoint /bin/runmariadb \
     --env MARIADB_PASSWORD="$mariadb_password" "${IRONIC_IMAGE}"

sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name ironic ${POD_NAME} \
     --env MARIADB_PASSWORD="$mariadb_password" \
     -v "$IRONIC_DATA_DIR":/shared "${IRONIC_IMAGE}"

# Start Ironic Inspector
sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name ironic-inspector ${POD_NAME} "${IRONIC_INSPECTOR_IMAGE}"
