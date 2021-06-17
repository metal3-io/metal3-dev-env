#!/bin/bash
set -eux

# Folder created for specific capi release when running
# ${CLUSTER_API_REPO}/cmd/clusterctl/hack/create-local-repository.py
# For CAPI release v0.3.12, the folder v0.3.8 is created

export CAPIRELEASE_HARDCODED="v0.3.8"

function get_capm3_latest() {
    clusterctl upgrade plan | grep infrastructure-metal3 | awk 'NR == 1 {print $5}'
}

export CAPM3RELEASE="v0.4.0"
CAPM3_REL_TO_VERSION="$(get_capm3_latest)" || true
export CAPM3_REL_TO_VERSION

export CAPIRELEASE="v0.3.15"
export CAPI_REL_TO_VERSION="v0.3.16"

export CAPI_API_VERSION="v1alpha3"
export CAPM3_API_VERSION="v1alpha4"

export KUBERNETES_VERSION="v1.21.1"
export UPGRADED_K8S_VERSION="v1.21.2"
