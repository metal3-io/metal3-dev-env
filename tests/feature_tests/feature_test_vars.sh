#!/bin/bash

export NUM_OF_CONTROLPLANE_REPLICAS="3"
export NUM_OF_WORKER_REPLICAS="1"
if [ "${CAPM3RELEASEBRANCH}" == "release-0.5" ];
then
  export FROM_K8S_VERSION="v1.23.5"
else
  export FROM_K8S_VERSION="v1.24.1"
fi
export KUBERNETES_VERSION="${FROM_K8S_VERSION}"
