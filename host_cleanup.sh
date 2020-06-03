#!/usr/bin/env bash
set -x

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

# Kill and remove the running ironic containers
for name in ipa-downloader ironic ironic-inspector ironic-endpoint-keepalived dnsmasq httpd mariadb vbmc sushy-tools httpd-infra; do
    sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill $name
    sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm $name -f
done

# Remove existing pod
if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  if  sudo "${CONTAINER_RUNTIME}" pod exists ironic-pod ; then
      sudo "${CONTAINER_RUNTIME}" pod rm ironic-pod -f
  fi
  if  sudo "${CONTAINER_RUNTIME}" pod exists infra-pod ; then
      sudo "${CONTAINER_RUNTIME}" pod rm infra-pod -f
  fi
fi

# Kill the locally running operators
if [ "${BMO_RUN_LOCAL}" = true ]; then
  kill "$(pgrep "run-bmo-loop.sh")" 2> /dev/null || true
  kill "$(pgrep "operator-sdk")" 2> /dev/null || true
fi
if [ "${CAPM3_RUN_LOCAL}" = true ]; then
  CAPM3_PARENT_PID="$(pgrep -f "go run ./cmd/manager/main.go")"
  if [[ "${CAPM3_PARENT_PID}" != "" ]]; then
    CAPM3_GO_PID="$(pgrep -P "${CAPM3_PARENT_PID}" )"
    kill "${CAPM3_GO_PID}"  2> /dev/null || true
  fi
fi


ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "num_nodes=$NUM_NODES" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -e "nodes_file=$NODES_FILE" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/teardown-playbook.yml

if [ "$USE_FIREWALLD" == "False" ]; then
 ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "{use_firewalld: $USE_FIREWALLD}" \
    -e "external_subnet_v4: ${EXTERNAL_SUBNET_V4}" \
    -e "firewall_rule_state=absent" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/firewall.yml
fi

# There was a bug in this file, it may need to be recreated.
if [[ $OS == "centos" || $OS == "rhel" ]]; then
  sudo rm -rf /etc/NetworkManager/conf.d/dnsmasq.conf
  if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
      sudo ifdown provisioning || true
      sudo rm -f /etc/sysconfig/network-scripts/ifcfg-provisioning || true
  fi
  # Leaving this around causes issues when the host is rebooted
  if [ "$MANAGE_BR_BRIDGE" == "y" ]; then
      sudo ifdown baremetal || true
      sudo rm -f /etc/sysconfig/network-scripts/ifcfg-baremetal || true
  fi
fi

# Clean up any serial logs
sudo rm -rf /var/log/libvirt/qemu/\*serial0.log

rm -rf  "${HOME}"/.cluster-api
