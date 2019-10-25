#!/bin/bash

# shellcheck disable=SC1091
source lib/common.sh

BMHOST=$1
IMAGE_NAME=${2:-${IMAGE_NAME}}
IMAGE_URL=http://172.22.0.1/images/${IMAGE_NAME}
IMAGE_CHECKSUM=http://172.22.0.1/images/${IMAGE_NAME}.md5sum

if [ -z "${BMHOST}" ] ; then
    echo "Usage: provision_host.sh <BareMetalHost-name> [image-name]"
    exit 1
fi

if echo "${IMAGE_NAME}" | grep -qi centos 2>/dev/null ; then
    OS_TYPE=centos
else
    OS_TYPE=unknown
fi
./user_data.sh "${BMHOST}" ${OS_TYPE} | kubectl apply -n metal3 -f -

kubectl patch baremetalhost "${BMHOST}" -n metal3 --type merge \
    -p '{"spec":{"image":{"url":"'"${IMAGE_URL}"'","checksum":"'"${IMAGE_CHECKSUM}"'"},"userData":{"name":"'"${BMHOST}"'-user-data","namespace":"metal3"}}}'
