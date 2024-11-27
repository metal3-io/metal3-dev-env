#!/usr/bin/env bash

set -eux

# shellcheck disable=SC1091
source lib/common.sh

# Delete cluster
if [[ "${EPHEMERAL_CLUSTER}" = "kind" ]] || [[ "${EPHEMERAL_CLUSTER}" = "tilt" ]]; then
    sudo su -l -c "kind delete cluster  || true" "${USER}"
    # Kill and remove the running ironic containers
    if [[ -x "${BMOPATH}/tools/remove_local_ironic.sh" ]]; then
        "${BMOPATH}"/tools/remove_local_ironic.sh
    fi
    if [[ "${EPHEMERAL_CLUSTER}" = "tilt" ]]; then
        pushd "${CAPM3PATH}"
        pgrep tilt | xargs kill  || true
        make kind-reset
        popd
    fi
fi

if [[ "${EPHEMERAL_CLUSTER}" = "minikube" ]]; then
    sudo su -l -c "minikube delete" "${USER}"
fi
