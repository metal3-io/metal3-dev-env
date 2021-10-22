#!/bin/bash
set -eux

# Folder created for specific capi release when running
# ${CLUSTER_API_REPO}/cmd/clusterctl/hack/create-local-repository.py

export CAPIRELEASE_HARDCODED="v0.4.99"

function get_latest_capm3_release() {
    clusterctl upgrade plan | grep infrastructure-metal3 | awk 'NR == 1 {print $5}'
}

# CAPM3 release version which we upgrade from.
export CAPM3RELEASE="v0.5.0"
CAPM3_REL_TO_VERSION="$(get_latest_capm3_release)" || true
# CAPM3 release version which we upgrade to.
export CAPM3_REL_TO_VERSION

# Fetch latest release version of CAPI from the output of clusterctl command.
function get_latest_capi_release() {
    clusterctl upgrade plan | grep cluster-api | awk 'NR == 1 {print $5}'
}

# CAPI release version which we upgrade from.
export CAPIRELEASE="v0.4.1"
CAPI_REL_TO_VERSION="$(get_latest_capi_release)" || true
# CAPI release version which we upgrade to.
export CAPI_REL_TO_VERSION
export FROM_K8S_VERSION="v1.22.1"
export KUBERNETES_VERSION=${FROM_K8S_VERSION}
export UPGRADED_K8S_VERSION="v1.22.2"
export MAX_SURGE_VALUE="0"
export NUM_OF_MASTER_REPLICAS="3"
export NUM_OF_WORKER_REPLICAS="1"
