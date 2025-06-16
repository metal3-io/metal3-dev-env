#!/usr/bin/env bash

set -ux

NUM_BMH=${NUM_BMH:-"5"}

REPO_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
cd "${REPO_ROOT}" || exit 1

# Delete all BMHs
for ((i=0; i<NUM_BMH; i++)); do
  VM_NAME="bmo-e2e-${i}"
  kubectl delete bmh "${VM_NAME}"
done

# Delete all VMs
for ((i=0; i<NUM_BMH; i++)); do
  VM_NAME="bmo-e2e-${i}"
  # Stop the VM if it's running
  virsh -c qemu:///system destroy --domain "${VM_NAME}"
  # Delete the VM and its storage
  virsh -c qemu:///system undefine --domain "${VM_NAME}" --remove-all-storage
done
