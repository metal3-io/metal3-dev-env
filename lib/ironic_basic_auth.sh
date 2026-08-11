#!/bin/bash

# Create usernames and passwords and other files related to basic auth
IRONIC_AUTH_DIR="${IRONIC_AUTH_DIR:-"${IRONIC_DATA_DIR}/auth"}"
mkdir -p "${IRONIC_AUTH_DIR}"

IRONIC_USERNAME_FILE="${IRONIC_AUTH_DIR}/ironic-username"
IRONIC_PASSWORD_FILE="${IRONIC_AUTH_DIR}/ironic-password"

# If usernames and passwords are unset, read them from file or generate them
if [ -z "${IRONIC_USERNAME:-}" ]; then
    if [ ! -f "${IRONIC_USERNAME_FILE}" ]; then
        IRONIC_USERNAME="$(uuidgen)"
        echo -n "$IRONIC_USERNAME" > "${IRONIC_USERNAME_FILE}"
    else
        IRONIC_USERNAME="$(cat "${IRONIC_USERNAME_FILE}")"
    fi
fi
if [ -z "${IRONIC_PASSWORD:-}" ]; then
    if [ ! -f "${IRONIC_PASSWORD_FILE}" ]; then
        IRONIC_PASSWORD="$(uuidgen)"
        echo -n "$IRONIC_PASSWORD" > "${IRONIC_PASSWORD_FILE}"
        chmod 0600 "${IRONIC_PASSWORD_FILE}"
    else
        IRONIC_PASSWORD="$(cat "${IRONIC_PASSWORD_FILE}")"
    fi
fi

export IRONIC_USERNAME
export IRONIC_PASSWORD

unset IRONIC_NO_BASIC_AUTH
