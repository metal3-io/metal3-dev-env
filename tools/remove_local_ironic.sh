#!/bin/bash

set -xe

# This script removes local ironic containers.
#
# NOTE: This script was moved from the baremetal-operator repo into
# metal3-dev-env. It is only used for local/development deployments of Ironic
# (i.e. when USE_IRSO=false and IRONIC_RUN_LOCAL=true).

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"

for name in ironic ironic-inspector dnsmasq httpd ipa-downloader ironic-endpoint-keepalived \
    ironic-log-watch ; do
    sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill "$name"
    sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm "$name" -f
done

# With Podman the containers live in the ironic-pod; remove it too so cleanup
# fully resets local Ironic state (the containers alone leave the pod behind).
if [[ "${CONTAINER_RUNTIME}" == "podman" ]] && sudo podman pod exists ironic-pod; then
    sudo podman pod rm --force ironic-pod
fi

set +xe
