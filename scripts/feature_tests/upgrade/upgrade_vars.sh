#!/bin/bash
set -eux

# Folder created for specific capi release when running
# ${CLUSTER_API_REPO}/cmd/clusterctl/hack/create-local-repository.py


# CAPM3 release version which we upgrade from.
export CAPM3RELEASE="v0.5.0"
CAPM3_REL_TO_VERSION="v0.5.1"
# CAPM3 release version which we upgrade to.
export CAPM3_REL_TO_VERSION

# CAPI release version which we upgrade from.
export CAPIRELEASE_HARDCODED="v0.4.99"
export CAPIRELEASE="v0.4.1"
CAPI_REL_TO_VERSION="v0.4.2"
# CAPI release version which we upgrade to.
export CAPI_REL_TO_VERSION
export FROM_K8S_VERSION="v1.22.2"
export KUBERNETES_VERSION=${FROM_K8S_VERSION}
export UPGRADED_K8S_VERSION="v1.22.3"
export MAX_SURGE_VALUE="0"
export NUM_OF_MASTER_REPLICAS="3"
export NUM_OF_WORKER_REPLICAS="1"
