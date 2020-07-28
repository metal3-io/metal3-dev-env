#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib/common.sh
source "${DIR}/lib/common.sh"

if [ -d "${PWD}/_clouds_yaml" ]; then
  MOUNTDIR="${PWD}/_clouds_yaml"
else
  MOUNTDIR="${SCRIPTDIR}/_clouds_yaml"
fi


ENTRYPOINT=
# ironic client also provides a "baremetal" command
# use it if $0 is "baremetal" and linked to this script
if [ "$(basename "$0")" == "baremetal" ] ; then
  ENTRYPOINT="--entrypoint baremetal"
fi

# shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run --net=host \
  -v "${MOUNTDIR}:/etc/openstack" --rm \
  -e OS_CLOUD="${OS_CLOUD:-metal3}" $ENTRYPOINT "${IRONIC_CLIENT_IMAGE}" "$@"
