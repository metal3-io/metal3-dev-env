#!/bin/bash

# Create usernames and passwords and other files related to basic auth
IRONIC_AUTH_DIR="${IRONIC_AUTH_DIR:-"${IRONIC_DATA_DIR}/auth/"}"
mkdir -p "${IRONIC_AUTH_DIR}"

# If usernames and passwords are unset, read them from file or generate them
if [ -z "${IRONIC_USERNAME:-}" ]; then
    if [ ! -f "${IRONIC_AUTH_DIR}ironic-username" ]; then
        IRONIC_USERNAME="$(uuidgen)"
        echo -n "$IRONIC_USERNAME" > "${IRONIC_AUTH_DIR}ironic-username"
    else
        IRONIC_USERNAME="$(cat "${IRONIC_AUTH_DIR}ironic-username")"
    fi
fi
if [ -z "${IRONIC_PASSWORD:-}" ]; then
    if [ ! -f "${IRONIC_AUTH_DIR}ironic-password" ]; then
        IRONIC_PASSWORD="$(uuidgen)"
        echo -n "$IRONIC_PASSWORD" > "${IRONIC_AUTH_DIR}ironic-password"
    else
        IRONIC_PASSWORD="$(cat "${IRONIC_AUTH_DIR}ironic-password")"
    fi
fi

export IRONIC_USERNAME
export IRONIC_PASSWORD

unset IRONIC_NO_BASIC_AUTH
