#!/bin/bash

source lib/common.sh

sudo "${CONTAINER_RUNTIME}" exec -ti vbmc vbmc "$@"
