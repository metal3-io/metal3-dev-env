#!/usr/bin/env bash

set -eux

# shellcheck disable=SC1091
. lib/logging.sh
# shellcheck disable=SC1091
. lib/common.sh
# shellcheck disable=SC1091
. lib/network.sh

# Kill and remove the running ironic containers
remove_ironic_containers

# Kill and remove fake-ipa container if it exists
sudo "${CONTAINER_RUNTIME}" rm -f fake-ipa 2>/dev/null

# Remove existing pod
if [[ "${CONTAINER_RUNTIME}" = "podman" ]]; then
    for pod in ironic-pod infra-pod; do
        if sudo "${CONTAINER_RUNTIME}" pod exists "${pod}"; then
            sudo "${CONTAINER_RUNTIME}" pod rm "${pod}" -f
        fi
    done
fi

# Kill the locally running operators
if [[ "${BMO_RUN_LOCAL}" = true ]]; then
    kill "$(pgrep "run-bmo-loop.sh")" 2> /dev/null || true
    kill "$(pgrep "operator-sdk")" 2> /dev/null || true
fi

if [[ "${CAPM3_RUN_LOCAL}" = true ]]; then
    CAPM3_PARENT_PID="$(pgrep -f "go run ./cmd/manager/main.go")"
    if [[ "${CAPM3_PARENT_PID}" != "" ]]; then
        CAPM3_GO_PID="$(pgrep -P "${CAPM3_PARENT_PID}" )"
        kill "${CAPM3_GO_PID}"  2> /dev/null || true
    fi
fi

ANSIBLE_FORCE_COLOR=true "${ANSIBLE}-playbook" \
    -e "working_dir=${WORKING_DIR}" \
    -e "num_nodes=${NUM_NODES}" \
    -e "vm_platform=${NODES_PLATFORM}" \
    -e "extradisks=${VM_EXTRADISKS}" \
    -e "virthost=${HOSTNAME}" \
    -e "manage_external=${MANAGE_EXT_BRIDGE}" \
    -e "nodes_file=${NODES_FILE}" \
    -i vm-setup/inventory.ini \
    -b -v vm-setup/teardown-playbook.yml

ANSIBLE_FORCE_COLOR=true "${ANSIBLE}-playbook" \
    -e "use_firewalld=${USE_FIREWALLD}" \
    -e "firewall_rule_state=absent" \
    -i vm-setup/inventory.ini \
    -b -v vm-setup/firewall.yml

# There was a bug in this file, it may need to be recreated.
if [[ "${OS}" = "centos" ]] || [[ "${OS}" = "rhel" ]]; then
    sudo rm -rf /etc/NetworkManager/conf.d/dnsmasq.conf
    if [[  "${MANAGE_PRO_BRIDGE}" = "y" ]]; then
        sudo nmcli con delete ironic-peer
        sudo nmcli con delete "${BARE_METAL_PROVISIONER_INTERFACE}"
        sudo nmcli con delete provisioning
    fi
    # External net should have been cleaned already at this stage, but we double
    # check as leaving it around causes issues when the host is rebooted
    if [[ "${MANAGE_EXT_BRIDGE}" = "y" ]]; then
        sudo nmcli con delete external || true
    fi
else
    if [[ "${MANAGE_PRO_BRIDGE}" = "y" ]]; then
        sudo ip link delete ironic-peer
        sudo ip link delete "${BARE_METAL_PROVISIONER_INTERFACE}"
        sudo ip link delete provisioning
    fi
    if [[ "${MANAGE_EXT_BRIDGE}" = "y" ]]; then
        sudo ip link delete external || true
    fi
fi

# Clean up any serial logs
sudo rm -rf /var/log/libvirt/qemu/*serial0.log*

# Clean up BMH CRs
sudo rm -rf "${WORKING_DIR}"/bmhosts_crs.yaml
sudo rm -rf "${WORKING_DIR}"/bmhs

if [[ -n "${XDG_CONFIG_HOME}" ]]; then
    rm -rf "${XDG_CONFIG_HOME}"/cluster-api
else
    rm -rf "${HOME}"/.config/cluster-api
fi
