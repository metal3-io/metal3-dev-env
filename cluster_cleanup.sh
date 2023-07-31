#!/usr/bin/env bash
set -xe

# shellcheck disable=SC1091
source lib/common.sh

# Delete cluster
if [ "${EPHEMERAL_CLUSTER}" == "kind" ] ||  [ "${EPHEMERAL_CLUSTER}" == "tilt" ]; then
  sudo su -l -c "kind delete cluster  || true" "${USER}"
  # Kill and remove the running ironic containers
  if [ -f "$BMOPATH/tools/remove_local_ironic.sh" ]; then
    "$BMOPATH"/tools/remove_local_ironic.sh
  fi
  if [ "${EPHEMERAL_CLUSTER}" == "tilt" ]; then
    pushd "${CAPM3PATH}"
    pgrep tilt | xargs kill  || true
    make kind-reset
    popd
  fi
fi

if [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
  # TODO: remove this line once minikube delete hanging issue is resolved.
  # The issue started with minikube version v1.31.1 and is tracked here
  # https://github.com/metal3-io/metal3-dev-env/issues/1264
  sudo systemctl restart libvirtd.service
  sudo su -l -c "minikube delete" "${USER}"
fi
