#!/bin/bash

# Folder created for specific capi release when running
# ${CLUSTER_API_REPO}/cmd/clusterctl/hack/create-local-repository.py
# For CAPI release v0.3.12, the folder v0.3.8 is created

export UPGRADED_K8S_VERSION="v1.21.0"

export CAPIRELEASE_HARDCODED="v0.3.8"

export CAPM3RELEASE="v0.4.0"
export CAPM3_REL_TO_VERSION="v0.4.1"

export CAPIRELEASE="v0.3.12"
export CAPI_REL_TO_VERSION="v0.3.14"

export CAPI_API_VERSION="v1alpha3"
export CAPM3_API_VERSION="v1alpha4"
