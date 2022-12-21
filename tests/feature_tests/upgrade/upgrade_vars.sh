#!/bin/bash
set -eux

# Folder created for specific capi release when running
# ${CLUSTER_API_REPO}/cmd/clusterctl/hack/create-local-repository.py
export CAPIRELEASE_HARDCODED="v1.2.99"

export CAPI_VERSION="${CAPI_VERSION:-v1alpha4}"
export CAPI_REL_TO_VERSION="v1.2.2"

export CAPM3_VERSION="${CAPM3_VERSION:-v1alpha5}"
export CAPM3_REL_TO_VERSION="v1.2.0"
export UPGRADED_CAPM3_VERSION="v1beta1"

# Set the container tag for Ironic and BMO to start from.
# They will then upgrade to main/latest
export IRONIC_TAG="capm3-v0.5.5"
export BAREMETAL_OPERATOR_TAG="capm3-v0.5.5"

# Ubuntu is hard coded in the upgrade tests. Make sure we use it throughout.
export IMAGE_OS="ubuntu"
export FROM_K8S_VERSION="v1.23.8"
export KUBERNETES_VERSION=${FROM_K8S_VERSION}
export UPGRADED_K8S_VERSION="v1.26.0"
export MAX_SURGE_VALUE="0"
export CONTROL_PLANE_MACHINE_COUNT="3"
export WORKER_MACHINE_COUNT="1"
