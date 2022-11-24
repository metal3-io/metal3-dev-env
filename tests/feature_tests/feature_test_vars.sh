#!/bin/bash

export CONTROL_PLANE_MACHINE_COUNT="3"
export WORKER_MACHINE_COUNT="1"
if [ "${CAPM3RELEASEBRANCH}" == "release-0.5" ];
then
  export FROM_K8S_VERSION="v1.23.5"
else
  export FROM_K8S_VERSION="v1.24.1"
fi
export KUBERNETES_VERSION="${FROM_K8S_VERSION}"
