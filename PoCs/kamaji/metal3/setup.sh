#!/usr/bin/env bash

set -eux

REPO_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
cd "${REPO_ROOT}" || exit 1

virsh -c qemu:///system net-define "${REPO_ROOT}/metal3/net.xml"
virsh -c qemu:///system net-start baremetal-e2e

# Create a kind cluster using the configuration from kind.yaml
kind create cluster --config "${REPO_ROOT}/metal3/kind.yaml"

# Start sushy-tools container to provide Redfish BMC emulation
docker run --name sushy-tools --rm --network host -d \
  -v /var/run/libvirt:/var/run/libvirt \
  -v "${REPO_ROOT}/metal3/sushy-tools.conf:/etc/sushy/sushy-emulator.conf" \
  -e SUSHY_EMULATOR_CONFIG=/etc/sushy/sushy-emulator.conf \
  quay.io/metal3-io/sushy-tools:latest sushy-emulator

# Image server variables
IMAGE_DIR="${REPO_ROOT}/metal3/images"

## Run the image server
mkdir -p "${IMAGE_DIR}"
docker run --name image-server-e2e -d \
  -p 80:8080 \
  -v "${IMAGE_DIR}:/usr/share/nginx/html" nginxinc/nginx-unprivileged

kubectl create namespace baremetal-operator-system

# If you want to use ClusterClasses
export CLUSTER_TOPOLOGY=true
# If you want to use ClusterResourceSets
export EXP_CLUSTER_RESOURCE_SET=true

clusterctl init --infrastructure=metal3
curl -Ls https://github.com/metal3-io/ip-address-manager/releases/latest/download/ipam-components.yaml |
  clusterctl generate yaml | kubectl apply -f -
kubectl apply -k "${REPO_ROOT}/metal3/ironic-bootstrap"
kubectl apply -k "${REPO_ROOT}/metal3/bmo-bootstrap"
