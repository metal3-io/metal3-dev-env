#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib/common.sh
source "${DIR}/lib/common.sh"

sudo "${CONTAINER_RUNTIME}" run -ti --net=host \
  -v "${SCRIPTDIR}/_clouds_yaml/:/etc/openstack" \
  -e OS_CLOUD=metal3 "${IRONIC_CLIENT_IMAGE}" "$@"
