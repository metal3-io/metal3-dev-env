#!/bin/bash

# Image name and location
IMAGE_OS=${IMAGE_OS:-Centos}
if [[ "${IMAGE_OS}" == "Ubuntu" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-UBUNTU_20.04_NODE_IMAGE_K8S_v1.19.3.qcow2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://artifactory.nordix.org/artifactory/airship/images/k8s_v1.19.3/}
elif [[ "${IMAGE_OS}" == "FCOS" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-fedora-coreos-32.20200923.2.0-openstack.x86_64.qcow2.xz}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://builds.coreos.fedoraproject.org/prod/streams/testing/builds/32.20200923.2.0/x86_64/}
elif [[ "${IMAGE_OS}" == "FCOS-ISO" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-fedora-coreos-33.20201201.2.1-live.x86_64.iso}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://builds.coreos.fedoraproject.org/prod/streams/testing/builds/33.20201201.2.1/x86_64}
elif [[ "${IMAGE_OS}" == "Centos" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-CENTOS_8.2_NODE_IMAGE_K8S_v1.19.3.qcow2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://artifactory.nordix.org/artifactory/airship/images/k8s_v1.19.3}
elif [[ "${IMAGE_OS}" == "Flatcar" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-flatcar_production_qemu_image.img.bz2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://stable.release.flatcar-linux.net/amd64-usr/current/}
else
  export IMAGE_NAME=${IMAGE_NAME:-cirros-0.5.1-x86_64-disk.img}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-http://download.cirros-cloud.net/0.5.1}
fi

# Image url and checksum
export IMAGE_URL=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}
export IMAGE_CHECKSUM=http://$PROVISIONING_URL_HOST/images/${IMAGE_NAME}.md5sum

# Target node username
export IMAGE_USERNAME=${IMAGE_USERNAME:-metal3}

# Image basename and rawname
IMAGE_BASE_NAME="${IMAGE_NAME%.*}"
export IMAGE_RAW_NAME="${IMAGE_BASE_NAME}-raw.img"
