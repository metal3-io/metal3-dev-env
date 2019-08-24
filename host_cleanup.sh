#!/usr/bin/env bash
set -x

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

# Kill and remove the running ironic containers
for name in ironic ironic-inspector dnsmasq httpd mariadb; do
    sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill $name
    sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm $name -f
done

# Remove existing pod
if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  if  sudo "${CONTAINER_RUNTIME}" pod exists ironic-pod ; then
      sudo "${CONTAINER_RUNTIME}" pod rm ironic-pod -f
  fi
fi

# Kill the locally running operators
if [ "${BMO_RUN_LOCAL}" = true ]; then
  kill "$(pgrep "operator-sdk")" 2> /dev/null || true
fi
if [ "${CAPBM_RUN_LOCAL}" = true ]; then
  CAPBM_PARENT_PID="$(pgrep -f "go run ./cmd/manager/main.go")"
  if [[ "${CAPBM_PARENT_PID}" != "" ]]; then
    CAPBM_GO_PID="$(pgrep -P "${CAPBM_PARENT_PID}" )"
    kill "${CAPBM_GO_PID}"  2> /dev/null || true
  fi
fi


ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -i vm-setup/inventory.ini \
    -b -vvv vm-setup/teardown-playbook.yml

# There was a bug in this file, it may need to be recreated.
if [[ $OS == "centos" ]]; then
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
