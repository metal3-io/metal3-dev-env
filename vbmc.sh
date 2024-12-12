#!/usr/bin/env bash

# shellcheck disable=SC2312
DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck disable=SC1091
. "${DIR}/lib/common.sh"

sudo "${CONTAINER_RUNTIME}" exec -ti vbmc vbmc "$@"
