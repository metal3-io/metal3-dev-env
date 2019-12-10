#!/bin/bash
set -xe

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DIR}/lib/common.sh"

V1ALPHA1_SCRIPTS_PATH="$(dirname "$(readlink -f "${0}")")/"
USER_DATA_SCRIPT_NAME="user_data.sh"
SCRIPT_PATH="${V1ALPHA1_SCRIPTS_PATH}""${USER_DATA_SCRIPT_NAME}"

MACHINE_NAME=$1
IMAGE_NAME=${2:-${IMAGE_NAME}}

IMAGE_URL=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}
IMAGE_CHECKSUM=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}.md5sum

if [ -z "$MACHINE_NAME" ] ; then
    echo "Usage: create_machine.sh <machine name> [image name]"
    exit 1
fi

make_machine() {
cat << EOF
apiVersion: "cluster.k8s.io/v1alpha1"
kind: Machine
metadata:
  name: ${MACHINE_NAME}
  generateName: baremetal-machine-
spec:
  providerSpec:
    value:
      apiVersion: "baremetal.cluster.k8s.io/v1alpha1"
      kind: "BareMetalMachineProviderSpec"
      image:
        url: ${IMAGE_URL}
        checksum: ${IMAGE_CHECKSUM}
      userData:
        name: ${MACHINE_NAME}-user-data
        namespace: metal3
EOF
}

if echo "${IMAGE_NAME}" | grep -qi centos 2>/dev/null ; then
    OS_TYPE=centos
else
    OS_TYPE=unknown
fi

"${SCRIPT_PATH}" "${MACHINE_NAME}" "${OS_TYPE}" | kubectl apply -n metal3 -f -

make_machine | kubectl apply -n metal3 -f -
