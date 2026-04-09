#!/usr/bin/env bash
set -euo pipefail

# Init container script for swtpm state initialization.
# Runs as root, prepares state directory for non-root main container.

SWTPM_STATE_DIR="${SWTPM_STATE_DIR:-/var/lib/swtpm}"
KEYLIME_UID="${KEYLIME_UID:-490}"
KEYLIME_GID="${KEYLIME_GID:-490}"

mkdir -p "${SWTPM_STATE_DIR}"

if [[ ! -f "${SWTPM_STATE_DIR}/tpm2-00.permall" ]]; then
    echo "Initializing swtpm state..."
    swtpm_setup --tpm2 \
        --tpmstate "${SWTPM_STATE_DIR}" \
        --createek --decryption --create-ek-cert \
        --create-platform-cert \
        --display || true
fi

chown -R "${KEYLIME_UID}:${KEYLIME_GID}" "${SWTPM_STATE_DIR}"
echo "swtpm state ready for uid ${KEYLIME_UID}"
