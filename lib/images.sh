#!/bin/bash

# Image name and location
IMAGE_OS="$(echo "${IMAGE_OS:-centos}" | tr '[:upper:]' '[:lower:]')"
export "${IMAGE_OS?}"
if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-UBUNTU_24.04_NODE_IMAGE_K8S_${KUBERNETES_VERSION}.qcow2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://artifactory.nordix.org/artifactory/metal3/images/k8s_${KUBERNETES_VERSION}}
elif [[ "${IMAGE_OS}" == "FCOS" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-fedora-coreos-32.20200923.2.0-openstack.x86_64.qcow2.xz}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://builds.coreos.fedoraproject.org/prod/streams/testing/builds/32.20200923.2.0/x86_64}
elif [[ "${IMAGE_OS}" == "FCOS-ISO" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-fedora-coreos-33.20201201.2.1-live.x86_64.iso}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://builds.coreos.fedoraproject.org/prod/streams/testing/builds/33.20201201.2.1/x86_64}
elif [[ "${IMAGE_OS}" == "centos" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-CENTOS_9_NODE_IMAGE_K8S_${KUBERNETES_VERSION}.qcow2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://artifactory.nordix.org/artifactory/metal3/images/k8s_${KUBERNETES_VERSION}}
elif [[ "${IMAGE_OS}" == "flatcar" ]]; then
  export IMAGE_NAME=${IMAGE_NAME:-flatcar_production_qemu_image.img.bz2}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-https://stable.release.flatcar-linux.net/amd64-usr/current/}
else
  export IMAGE_NAME=${IMAGE_NAME:-cirros-0.5.2-x86_64-disk.img}
  export IMAGE_LOCATION=${IMAGE_LOCATION:-http://download.cirros-cloud.net/0.5.2}
fi

# Image url and checksum
export IMAGE_URL="http://$BARE_METAL_PROVISIONER_URL_HOST/images/${IMAGE_NAME}"
export IMAGE_CHECKSUM=http://$BARE_METAL_PROVISIONER_URL_HOST/images/${IMAGE_NAME}.sha256sum

# Target node username
export IMAGE_USERNAME=${IMAGE_USERNAME:-metal3}

# Image basename and rawname
IMAGE_BASE_NAME="${IMAGE_NAME%.*}"
export IMAGE_RAW_NAME="${IMAGE_BASE_NAME}-raw.img"

# variables used for template parametrization in CAPM3
export IMAGE_RAW_URL="http://$BARE_METAL_PROVISIONER_URL_HOST/images/${IMAGE_RAW_NAME}"
export IMAGE_RAW_CHECKSUM="http://$BARE_METAL_PROVISIONER_URL_HOST/images/${IMAGE_RAW_NAME}.sha256sum"
