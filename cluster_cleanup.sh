#!/usr/bin/env bash
set -xe

# shellcheck disable=SC1091
source lib/common.sh


if [ "${EPHEMERAL_CLUSTER}" == "kind" ]; then
  sudo su -l -c "kind delete cluster  || true" "${USER}"
fi

if [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
  sudo su -l -c "minikube delete" "${USER}"
fi
