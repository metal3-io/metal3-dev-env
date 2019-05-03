#!/bin/bash

BMHOST=$1
IMAGE_NAME=${2:-CentOS-7-x86_64-GenericCloud-1901.qcow2}

if [ -z "${BMHOST}" ] ; then
    echo "Usage: provision_host.sh <BareMetalHost Name>"
    exit 1
fi
IMAGE_URL=http://172.22.0.1/images/${IMAGE_NAME}
IMAGE_CHECKSUM=http://172.22.0.1/images/${IMAGE_NAME}.md5sum

kubectl patch baremetalhost ${BMHOST} -n metal3 --type merge \
    -p '{"spec":{"image":{"url":"'${IMAGE_URL}'","checksum":"'${IMAGE_CHECKSUM}'"}}}'
