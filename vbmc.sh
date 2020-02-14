#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib/common.sh
source "${DIR}/lib/common.sh"

sudo "${CONTAINER_RUNTIME}" exec -ti vbmc vbmc "$@"
