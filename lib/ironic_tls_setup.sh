#!/bin/bash

# Create certificates and related files for TLS
if [ "${IRONIC_TLS_SETUP}" == "true" ]; then
    pushd "${WORKING_DIR}" || exit
    mkdir -p "${WORKING_DIR}/certs"
    pushd "${WORKING_DIR}/certs" || exit

    export IRONIC_BASE_URL="https://${CLUSTER_BARE_METAL_PROVISIONER_HOST}"

    export IRONIC_CACERT_FILE="${IRONIC_CACERT_FILE:-"${WORKING_DIR}/certs/ironic-ca.pem"}"
    export IRONIC_CAKEY_FILE="${IRONIC_CAKEY_FILE:-"${WORKING_DIR}/certs/ironic-ca.key"}"
    export IRONIC_CERT_FILE="${IRONIC_CERT_FILE:-"${WORKING_DIR}/certs/ironic.crt"}"
    export IRONIC_KEY_FILE="${IRONIC_KEY_FILE:-"${WORKING_DIR}/certs/ironic.key"}"

    export IRONIC_INSPECTOR_CACERT_FILE="${IRONIC_INSPECTOR_CACERT_FILE:-"${WORKING_DIR}/certs/ironic-ca.pem"}"
    export IRONIC_INSPECTOR_CAKEY_FILE="${IRONIC_INSPECTOR_CAKEY_FILE:-"${WORKING_DIR}/certs/ironic-ca.key"}"
    export IRONIC_INSPECTOR_CERT_FILE="${IRONIC_INSPECTOR_CERT_FILE:-"${WORKING_DIR}/certs/ironic-inspector.crt"}"
    export IRONIC_INSPECTOR_KEY_FILE="${IRONIC_INSPECTOR_KEY_FILE:-"${WORKING_DIR}/certs/ironic-inspector.key"}"

    export MARIADB_CACERT_FILE="${MARIADB_CACERT_FILE:-"${WORKING_DIR}/certs/ironic-ca.pem"}"
    export MARIADB_CAKEY_FILE="${IRONIC_CAKEY_FILE:-"${WORKING_DIR}/certs/ironic-ca.key"}"
    export MARIADB_CERT_FILE="${MARIADB_CERT_FILE:-"${WORKING_DIR}/certs/mariadb.crt"}"
    export MARIADB_KEY_FILE="${MARIADB_KEY_FILE:-"${WORKING_DIR}/certs/mariadb.key"}"

    export IPXE_CACERT_FILE="${IPXE_CACERT_FILE:-"${WORKING_DIR}/certs/ipxe-ca.pem"}"
    export IPXE_CAKEY_FILE="${IPXE_CAKEY_FILE:-"${WORKING_DIR}/certs/ipxe-ca.key"}"
    export IPXE_CERT_FILE="${IPXE_CERT_FILE:-"${WORKING_DIR}/certs/ipxe.crt"}"
    export IPXE_KEY_FILE="${IPXE_KEY_FILE:-"${WORKING_DIR}/certs/ipxe.key"}"

    # Generate CA Key files
    if [ ! -f "${IRONIC_CAKEY_FILE}" ]; then
        openssl genrsa -out "${IRONIC_CAKEY_FILE}" 2048
    fi
    if [ ! -f "${IRONIC_INSPECTOR_CAKEY_FILE}" ]; then
        openssl genrsa -out "${IRONIC_INSPECTOR_CAKEY_FILE}" 2048
    fi
    if [ ! -f "${MARIADB_CAKEY_FILE}" ]; then
        openssl genrsa -out "${MARIADB_CAKEY_FILE}" 2048
    fi
    if [ ! -f "${IPXE_CAKEY_FILE}" ]; then
        openssl genrsa -out "${IPXE_CAKEY_FILE}" 2048
    fi

    # Generate CA cert files
    if [ ! -f "${IRONIC_CACERT_FILE}" ]; then
        openssl req -x509 -new -nodes -key "${IRONIC_CAKEY_FILE}" -sha256 -days 1825 -out "${IRONIC_CACERT_FILE}" -subj /CN="ironic CA"/
    fi
    if [ ! -f "${IRONIC_INSPECTOR_CACERT_FILE}" ]; then
        openssl req -x509 -new -nodes -key "${IRONIC_INSPECTOR_CAKEY_FILE}" -sha256 -days 1825 -out "${IRONIC_INSPECTOR_CACERT_FILE}" -subj /CN="ironic inspector CA"/
    fi
    if [ ! -f "${MARIADB_CACERT_FILE}" ]; then
        openssl req -x509 -new -nodes -key "${MARIADB_CAKEY_FILE}" -sha256 -days 1825 -out "${MARIADB_CACERT_FILE}" -subj /CN="mariadb CA"/
    fi
    if [ ! -f "${IPXE_CACERT_FILE}" ]; then
        openssl req -x509 -new -nodes -key "${IPXE_CAKEY_FILE}" -sha256 -days 1825 -out "${IPXE_CACERT_FILE}" -subj /CN="ipxe CA"/
    fi

    # Generate Key files
    if [ ! -f "${IRONIC_KEY_FILE}" ]; then
        openssl genrsa -out "${IRONIC_KEY_FILE}" 2048
    fi
    if [ ! -f "${IRONIC_INSPECTOR_KEY_FILE}" ]; then
        openssl genrsa -out "${IRONIC_INSPECTOR_KEY_FILE}" 2048
    fi
    if [ ! -f "${MARIADB_KEY_FILE}" ]; then
        openssl genrsa -out "${MARIADB_KEY_FILE}" 2048
    fi
    if [ ! -f "${IPXE_KEY_FILE}" ]; then
        openssl genrsa -out "${IPXE_KEY_FILE}" 2048
    fi

    # Generate CSR and certificate files
    if [ ! -f "${IRONIC_CERT_FILE}" ]; then
        openssl req -new -key "${IRONIC_KEY_FILE}" -out /tmp/ironic.csr -subj /CN="${IRONIC_HOST}"/
        openssl x509 -req -in /tmp/ironic.csr -CA "${IRONIC_CACERT_FILE}" -CAkey "${IRONIC_CAKEY_FILE}" -CAcreateserial -out "${IRONIC_CERT_FILE}" -days 825 -sha256 -extfile <(printf "subjectAltName=IP:%s" "${IRONIC_HOST_IP}")
    fi
    if [ ! -f "${IRONIC_INSPECTOR_CERT_FILE}" ]; then
        openssl req -new -key "${IRONIC_INSPECTOR_KEY_FILE}" -out /tmp/ironic.csr -subj /CN="${IRONIC_HOST}"/
        openssl x509 -req -in /tmp/ironic.csr -CA "${IRONIC_INSPECTOR_CACERT_FILE}" -CAkey "${IRONIC_INSPECTOR_CAKEY_FILE}" -CAcreateserial -out "${IRONIC_INSPECTOR_CERT_FILE}" -days 825 -sha256 -extfile <(printf "subjectAltName=IP:%s" "${IRONIC_HOST_IP}")
    fi

    if [ ! -f "${MARIADB_CERT_FILE}" ]; then
        openssl req -new -key "${MARIADB_KEY_FILE}" -out /tmp/mariadb.csr -subj /CN="${MARIADB_HOST}"/
        openssl x509 -req -in /tmp/mariadb.csr -CA "${MARIADB_CACERT_FILE}" -CAkey "${MARIADB_CAKEY_FILE}" -CAcreateserial -out "${MARIADB_CERT_FILE}" -days 825 -sha256 -extfile <(printf "subjectAltName=IP:%s" "${MARIADB_HOST_IP}")
    fi
    if [ ! -f "${IPXE_CERT_FILE}" ]; then
        openssl req -new -key "${IPXE_KEY_FILE}" -out /tmp/ipxe.csr -subj /CN="${IRONIC_HOST}"/
        openssl x509 -req -in /tmp/ipxe.csr -CA "${IPXE_CACERT_FILE}" -CAkey "${IPXE_CAKEY_FILE}" -CAcreateserial -out "${IPXE_CERT_FILE}" -days 825 -sha256 -extfile <(printf "subjectAltName=IP:%s" "${IRONIC_HOST_IP}")
    fi

    #Populate the CA certificate B64 variable
    if [ "${IRONIC_CACERT_FILE}" == "${IRONIC_INSPECTOR_CACERT_FILE}" ]; then
        IRONIC_CA_CERT_B64="${IRONIC_CA_CERT_B64:-"$(base64 -w 0 < "${IRONIC_CACERT_FILE}")"}"
    else
        IRONIC_CA_CERT_B64="${IRONIC_CA_CERT_B64:-"$(base64 -w 0 < "${IRONIC_CACERT_FILE}")$(base64 -w 0 < "${IRONIC_INSPECTOR_CACERT_FILE}")"}"
    fi
    export IRONIC_CA_CERT_B64

    popd || exit
    popd || exit
    unset IRONIC_NO_CA_CERT
else
    export IRONIC_BASE_URL="http://${CLUSTER_BARE_METAL_PROVISIONER_HOST}"
    export IRONIC_NO_CA_CERT="true"

    # Unset all TLS related variables to prevent a TLS deployment
    unset IRONIC_CA_CERT_B64
    unset IRONIC_CACERT_FILE
    unset IRONIC_CERT_FILE
    unset IRONIC_KEY_FILE
    unset IRONIC_INSPECTOR_CACERT_FILE
    unset IRONIC_INSPECTOR_CERT_FILE
    unset IRONIC_INSPECTOR_KEY_FILE
    unset MARIADB_CACERT_FILE
    unset MARIADB_CERT_FILE
    unset MARIADB_KEY_FILE
    unset IPXE_CACERT_FILE
    unset IPXE_CERT_FILE
    unset IPXE_KEY_FILE
fi
