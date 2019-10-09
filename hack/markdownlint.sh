#!/bin/sh

set -eux

IS_CONTAINER=${IS_CONTAINER:-false}

if [ "${IS_CONTAINER}" != "false" ]; then
  TOP_DIR="${1:-.}"
  mdl --style all --warnings "${TOP_DIR}"
else
  podman run --rm \
    --env IS_CONTAINER=TRUE \
    --volume "${PWD}:/workdir:ro,z" \
    --entrypoint sh \
    --workdir /workdir \
    registry.hub.docker.com/pipelinecomponents/markdownlint:latest \
    /workdir/hack/markdownlint.sh "${@}"
fi;
