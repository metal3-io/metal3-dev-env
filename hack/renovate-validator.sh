#!/bin/sh
# Validates renovate.json configuration using renovate-config-validator.
# Requires Node.js 22+ for Renovate v40.

set -eux

IS_CONTAINER="${IS_CONTAINER:-false}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"
WORKDIR="${WORKDIR:-/workdir}"

if [ "${IS_CONTAINER}" != "false" ]; then
    npx --yes -p renovate renovate-config-validator
else
    "${CONTAINER_RUNTIME}" run --rm \
        --env IS_CONTAINER=TRUE \
        --volume "${PWD}:${WORKDIR}:ro,z" \
        --entrypoint sh \
        --workdir "${WORKDIR}" \
        docker.io/node:24-alpine \
        "${WORKDIR}"/hack/renovate-validator.sh "$@"
fi
