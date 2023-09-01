#!/usr/bin/env bash
# This is a helper for verifying/printing digests of downloaded, pinned
# dependencies.

set -eu

METAL3_DEV_ENV_DIR="$(dirname "$(readlink -f "${0}")")/.."

# shellcheck disable=SC1091
. "${METAL3_DEV_ENV_DIR}/lib/common.sh"
# shellcheck disable=SC1091
. "${METAL3_DEV_ENV_DIR}/lib/download.sh"

# this downloads and prints sha256 digests for all pinned dependencies
_download_and_print_checksums
