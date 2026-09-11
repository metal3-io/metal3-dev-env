#!/bin/bash

set -xe

# This script removes local ironic containers.
#
# NOTE: This script was moved from the baremetal-operator repo into
# metal3-dev-env. It is only used for local/development deployments of Ironic
# (i.e. when USE_IRSO=false and IRONIC_RUN_LOCAL=true). CI deploys Ironic
# in-cluster via the ironic-standalone-operator (IRSO) by default.

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"

for name in ironic ironic-inspector dnsmasq httpd ipa-downloader ironic-endpoint-keepalived \
    ironic-log-watch ; do
    sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill "$name"
    sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm "$name" -f
done

set +xe
