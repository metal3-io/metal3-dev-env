#!/bin/bash

CA_ISSUER="ca-issuer"
CLIENT_NAME="openstack-cli"
CLIENT_SECRET="openstack-cli-mtls"

DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib/common.sh
source "${DIR}/lib/common.sh"
# shellcheck source=lib/network.sh
source "${DIR}/lib/network.sh"

if [ -d "${PWD}/_clouds_yaml" ]; then
  MOUNTDIR="${PWD}/_clouds_yaml"
else
  MOUNTDIR="${SCRIPTDIR}/_clouds_yaml"
fi

cat <<EOF | kubectl apply -f - || exit 1
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: ${CLIENT_NAME}
  namespace: metal3
spec:
  secretName: ${CLIENT_SECRET}
  duration: 7200h # 30d
  renewBefore: 120h # 5d
  commonName: ${CLIENT_NAME}
  isCA: false
  keySize: 2048
  keyAlgorithm: rsa
  keyEncoding: pkcs1
  usages:
    - client auth
  ipAddresses:
    - ${CLUSTER_URL_HOST}
  issuerRef:
    name: ${CA_ISSUER}
    kind: Issuer
EOF
kubectl wait -n metal3 "certificates/${CLIENT_NAME}" --for condition=Ready || exit 1
kubectl get secret -n metal3 "${CLIENT_SECRET}" --template='{{index .data "ca.crt" | base64decode}}' > "${MOUNTDIR}/ca.crt"
kubectl get secret -n metal3 "${CLIENT_SECRET}" --template='{{index .data "tls.crt" | base64decode}}' > "${MOUNTDIR}/client.crt"
kubectl get secret -n metal3 "${CLIENT_SECRET}" --template='{{index .data "tls.key" | base64decode}}' > "${MOUNTDIR}/client.key"

sudo "${CONTAINER_RUNTIME}" run --net=host \
  -v "${MOUNTDIR}:/etc/openstack" --rm \
  -e OS_CLOUD="${OS_CLOUD:-metal3}" "${IRONIC_CLIENT_IMAGE}" "$@"
