#!/bin/bash

# shellcheck disable=SC1091
source ../../lib/common.sh

MACHINE_NAME=$1
IMAGE_NAME=${2:-CentOS-7-x86_64-GenericCloud-1901.qcow2}
IMAGE_URL=http://172.22.0.1/images/${IMAGE_NAME}
IMAGE_CHECKSUM=http://172.22.0.1/images/${IMAGE_NAME}.md5sum

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
./user_data.sh "${MACHINE_NAME}" "${OS_TYPE}" | kubectl apply -n metal3 -f -

make_machine | kubectl apply -n metal3 -f -
