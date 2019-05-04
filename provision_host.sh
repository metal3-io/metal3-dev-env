#!/bin/bash

source utils/common.sh

BMHOST=$1
IMAGE_NAME=${2:-CentOS-7-x86_64-GenericCloud-1901.qcow2}
IMAGE_URL=http://172.22.0.1/images/${IMAGE_NAME}
IMAGE_CHECKSUM=http://172.22.0.1/images/${IMAGE_NAME}.md5sum

if [ -z "${BMHOST}" ] ; then
    echo "Usage: provision_host.sh <BareMetalHost-name> [image-name]"
    exit 1
fi

user_data_secret() {
    printf "#cloud-config\n\nssh_authorized_keys:\n  - " > .userdata.tmp
    cat ${SSH_PUB_KEY} >> .userdata.tmp
cat << EOF
apiVersion: v1
data:
  userData: $(base64 -w 0 .userdata.tmp)
kind: Secret
metadata:
  name: ${BMHOST}-user-data
  namespace: metal3
type: Opaque
EOF
rm .userdata.tmp
}
user_data_secret | kubectl apply -n metal3 -f -

kubectl patch baremetalhost ${BMHOST} -n metal3 --type merge \
    -p '{"spec":{"image":{"url":"'${IMAGE_URL}'","checksum":"'${IMAGE_CHECKSUM}'"},"userData":{"name":"'${BMHOST}'-user-data","namespace":"metal3"}}}'
