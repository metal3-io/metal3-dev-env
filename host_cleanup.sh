#!/usr/bin/env bash
set -x

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

# Kill and remove the running ironic containers
remove_ironic_containers

# Remove existing pod
if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  for pod in ironic-pod infra-pod; do
    if sudo "${CONTAINER_RUNTIME}" pod exists "${pod}"; then
      sudo "${CONTAINER_RUNTIME}" pod rm "${pod}" -f
    fi
  done
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
    -e "manage_external=$MANAGE_EXT_BRIDGE" \
    -e "nodes_file=$NODES_FILE" \
    -i vm-setup/inventory.ini \
    -b -v vm-setup/teardown-playbook.yml

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "use_firewalld=${USE_FIREWALLD}" \
    -e "firewall_rule_state=absent" \
    -i vm-setup/inventory.ini \
    -b -v vm-setup/firewall.yml

# There was a bug in this file, it may need to be recreated.
if [[ $OS == "centos" || $OS == "rhel" ]]; then
  sudo rm -rf /etc/NetworkManager/conf.d/dnsmasq.conf
  if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    sudo nmcli con delete provisioning
  fi
  # External net should have been cleaned already at this stage, but we double
  # check as leaving it around causes issues when the host is rebooted
  if [ "${MANAGE_EXT_BRIDGE}" == "y" ]; then
    sudo nmcli con delete external || true
  fi
fi

# Clean up any serial logs
sudo rm -rf /var/log/libvirt/qemu/*serial0.log*

# TODO(Sunnatillo): Remove first line after deprication of camp3 v1.4
rm -rf "${HOME}"/.cluster-api

if [[ -n "${XDG_CONFIG_HOME}" ]]; then
    rm -rf "${XDG_CONFIG_HOME}"/cluster-api
else
    rm -rf "${HOME}"/.config/cluster-api
fi

# clean metal3 related files from /opt folder
sudo rm -rf /opt/metal3/
sudo rm -rf /opt/metal3-dev-env/
