#!/bin/bash

# shellcheck disable=SC1091
source ../../lib/common.sh

# Cluster.
CLUSTER_YAML=cluster.yaml


make_cluster() {
  envsubst < "${V1ALPHA2_CR_PATH}${CLUSTER_YAML}"
}
make_cluster | kubectl apply -n metal3 -f -
