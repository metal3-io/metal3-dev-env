#!/bin/bash
set -eux

# Folder created for specific capi release when running
# ${CLUSTER_API_REPO}/cmd/clusterctl/hack/create-local-repository.py

export CAPIRELEASE_HARDCODED="v1.0.99"

export CAPIRELEASE="v1.0.0"
export CAPI_REL_TO_VERSION="v1.0.1"

export CAPM3RELEASE="v1.0.0"
export CAPM3_REL_TO_VERSION="v1.0.0"
export FROM_K8S_VERSION="v1.22.2"
export KUBERNETES_VERSION=${FROM_K8S_VERSION}
export UPGRADED_K8S_VERSION="v1.22.3"
export MAX_SURGE_VALUE="0"
export NUM_OF_CONTROLPLANE_REPLICAS="3"
export NUM_OF_WORKER_REPLICAS="1"
