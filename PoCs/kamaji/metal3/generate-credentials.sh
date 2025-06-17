#!/usr/bin/env bash

set -eu

IRONIC_USERNAME="$(uuidgen)"
IRONIC_PASSWORD="$(uuidgen)"
echo "${IRONIC_USERNAME}" > metal3/bmo-bootstrap/ironic-username
echo "${IRONIC_PASSWORD}" > metal3/bmo-bootstrap/ironic-password
echo "IRONIC_HTPASSWD=$(htpasswd -n -b -B "${IRONIC_USERNAME}" "${IRONIC_PASSWORD}")" > metal3/ironic-bootstrap/ironic-htpasswd
