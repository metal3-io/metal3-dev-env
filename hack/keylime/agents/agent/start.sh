#!/usr/bin/env bash
set -euo pipefail

# Start script for push model agent.
# In swtpm mode: starts swtpm daemon, expects pre-initialized state from init container.
# In hw TPM mode (TCTI=device:*): skips swtpm, uses hardware TPM directly.

TCTI="${TCTI:-swtpm:host=localhost,port=2321}"

if [[ "${TCTI}" != device:* ]]; then
    SWTPM_STATE_DIR="${SWTPM_STATE_DIR:-/var/lib/swtpm}"

    if [[ ! -f "${SWTPM_STATE_DIR}/tpm2-00.permall" ]]; then
        echo "ERROR: swtpm state not initialized (missing ${SWTPM_STATE_DIR}/tpm2-00.permall)"
        echo "The init container (swtpm-init.sh) must run first."
        exit 1
    fi

    echo "Starting swtpm..."
    swtpm socket --tpm2 \
        --tpmstate dir="${SWTPM_STATE_DIR}" \
        --flags startup-clear \
        --ctrl type=tcp,port=2322 \
        --server type=tcp,port=2321 \
        --daemon
    sleep 2
fi

REGISTRAR_IP="${KEYLIME_AGENT_REGISTRAR_IP:-127.0.0.1}"
REGISTRAR_PORT="${KEYLIME_AGENT_REGISTRAR_PORT:-30890}"
VERIFIER_URL="${KEYLIME_AGENT_VERIFIER_URL:?KEYLIME_AGENT_VERIFIER_URL must be set}"
CA_CERT="${KEYLIME_AGENT_TRUSTED_CLIENT_CA:-/var/lib/keylime/certs/cacert.crt}"
CLIENT_CERT="${KEYLIME_AGENT_SERVER_CERT:-/var/lib/keylime/certs/client-cert.crt}"
CLIENT_KEY="${KEYLIME_AGENT_SERVER_KEY:-/var/lib/keylime/certs/client-private.pem}"

echo "Starting keylime_push_model_agent..."
echo "Registrar: ${REGISTRAR_IP}:${REGISTRAR_PORT}"
echo "Verifier URL: ${VERIFIER_URL}"
echo "TCTI: ${TCTI}"

exec /bin/keylime_push_model_agent \
    --registrar-url "http://${REGISTRAR_IP}:${REGISTRAR_PORT}" \
    --verifier-url "${VERIFIER_URL}" \
    --ca-certificate "${CA_CERT}" \
    --certificate "${CLIENT_CERT}" \
    --key "${CLIENT_KEY}"
