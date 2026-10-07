#!/usr/bin/env bash

set -eux

# shellcheck disable=SC1091
source lib/common.sh

# Delete cluster
if [[ "${BOOTSTRAP_CLUSTER}" = "kind" ]] || [[ "${BOOTSTRAP_CLUSTER}" = "tilt" ]]; then
    sudo su -l -c "kind delete cluster  || true" "${USER}"
    # Remove the veth used to plumb the provisioning network into the kind node
    # (see connect_kind_provisioning_network in 03_launch_mgmt_cluster.sh). The
    # node-side end is destroyed with the kind node container; clean up the host
    # side and the netns symlink here. Both are no-ops if they don't exist.
    sudo ip link del kind-prov-host 2>/dev/null || true
    sudo rm -f /var/run/netns/kind-provisioning
    # Kill and remove the running ironic containers
    if [[ -x "${REMOVE_LOCAL_IRONIC_SCRIPT}" ]]; then
        "${REMOVE_LOCAL_IRONIC_SCRIPT}"
    fi
    if [[ "${BOOTSTRAP_CLUSTER}" = "tilt" ]]; then
        pushd "${CAPM3PATH}"
        pgrep tilt | xargs kill  || true
        make kind-reset
        popd
    fi
fi

if [[ "${BOOTSTRAP_CLUSTER}" = "minikube" ]]; then
    sudo su -l -c "minikube delete" "${USER}"
fi
