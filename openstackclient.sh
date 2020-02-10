#!/bin/bash

source lib/common.sh

sudo "${CONTAINER_RUNTIME}" run -ti --net=host \
  -v "${SCRIPTDIR}/_clouds_yaml/:/etc/openstack" \
  -e OS_CLOUD=metal3 "${IRONIC_CLIENT_IMAGE}" "$@"
