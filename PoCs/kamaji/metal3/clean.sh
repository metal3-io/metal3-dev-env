#!/usr/bin/env bash

REPO_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
cd "${REPO_ROOT}" || exit 1

NUM_BMH=${NUM_BMH:-"5"}

kind delete cluster

docker rm -f dnsmasq
docker rm -f image-server-e2e
docker rm -f sushy-tools

for ((i=0; i<NUM_BMH; i++)); do
  virsh -c qemu:///system destroy --domain "bmo-e2e-${i}"
  virsh -c qemu:///system undefine --domain "bmo-e2e-${i}" --remove-all-storage
done

virsh -c qemu:///system net-destroy baremetal-e2e
virsh -c qemu:///system net-undefine baremetal-e2e
