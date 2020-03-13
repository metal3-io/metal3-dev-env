#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib/common.sh
source "${DIR}/lib/common.sh"

if [ -d "${PWD}/_clouds_yaml" ]; then
  MOUNTDIR="${PWD}/_clouds_yaml"
else
  MOUNTDIR="${SCRIPTDIR}/_clouds_yaml"
fi

sudo "${CONTAINER_RUNTIME}" run -ti --net=host \
  -v "${MOUNTDIR}:/etc/openstack" \
  -e OS_CLOUD="${OS_CLOUD:-metal3}" "${IRONIC_CLIENT_IMAGE}" "$@"
