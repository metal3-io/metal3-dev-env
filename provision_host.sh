#!/bin/bash

# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh
# shellcheck disable=SC1091
source lib/images.sh

BMHOST=$1
IMAGE_NAME=${2:-${IMAGE_NAME}}
IMAGE_URL=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}
IMAGE_CHECKSUM=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}.md5sum

if [ -z "${BMHOST}" ] ; then
    echo "Usage: provision_host.sh <BareMetalHost-name> [image-name]"
    exit 1
fi

if echo "${IMAGE_NAME}" | grep -qi centos 2>/dev/null ; then
    OS_TYPE=centos
else
    OS_TYPE=unknown
fi

if [ "${CAPI_VERSION}" == "v1alpha3" ]; then
  ./scripts/v1alpha3/user_data.sh "${BMHOST}" ${OS_TYPE} | kubectl apply -f -
  kubectl patch baremetalhost "${BMHOST}" -n metal3 --type merge \
      -p '{"spec":{"image":{"url":"'"${IMAGE_URL}"'","checksum":"'"${IMAGE_CHECKSUM}"'"},"userData":{"name":"'"${BMHOST}"'-user-data"}}}'
else
  ./scripts/v1alpha1/user_data.sh "${BMHOST}" ${OS_TYPE} | kubectl apply -n metal3 -f -
  kubectl patch baremetalhost "${BMHOST}" -n metal3 --type merge \
      -p '{"spec":{"image":{"url":"'"${IMAGE_URL}"'","checksum":"'"${IMAGE_CHECKSUM}"'"},"userData":{"name":"'"${BMHOST}"'-user-data","namespace":"metal3"}}}'
fi
