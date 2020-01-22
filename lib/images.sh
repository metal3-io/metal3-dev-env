#!/bin/bash

# Image url and checksum
IMAGE_OS=${IMAGE_OS:-Centos}
if [[ "${IMAGE_OS}" == "Ubuntu" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-bionic-server-cloudimg-amd64.img}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://cloud-images.ubuntu.com/bionic/current}
  export IMAGE_USERNAME=${IMAGE_USERNAME:-ubuntu}
elif [[ "${IMAGE_OS}" == "FCOS" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-fedora-coreos-30.20191014.0-openstack.x86_64.qcow2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://builds.coreos.fedoraproject.org/prod/streams/testing/builds/30.20191014.0/x86_64/}
  export IMAGE_USERNAME=${IMAGE_USERNAME:-core}
elif [[ "${IMAGE_OS}" == "Centos" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-CentOS-7-x86_64-GenericCloud-1907.qcow2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-http://cloud.centos.org/centos/7/images}
  export IMAGE_USERNAME=${IMAGE_USERNAME:-centos}
else
  export IMAGE_NAME=${IMAGE_NAME:-cirros-0.4.0-x86_64-disk.img}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-http://download.cirros-cloud.net/0.4.0}
  export IMAGE_USERNAME=${IMAGE_USERNAME:-cirros}
fi
export IMAGE_URL=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}
export IMAGE_CHECKSUM=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}.md5sum

# Target node username
export NODE_USERNAME=${IMAGE_USERNAME}
