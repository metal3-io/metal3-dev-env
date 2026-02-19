#!/usr/bin/env bash

set -eux

# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh
# shellcheck disable=SC1091
source lib/images.sh

mkdir -p "${IRONIC_IMAGE_DIR}"
pushd "${IRONIC_IMAGE_DIR}"

# Download and prepare node images (unless skipped)
if [[ ! -f "${IMAGE_NAME}" ]]; then
    if [[ -f "${IMAGE_LOCATION}/${IMAGE_NAME}" ]]; then
      # Copy local image  
      cp "${IMAGE_LOCATION}/${IMAGE_NAME}" .
    elif [[ "${IMAGE_LOCATION}" =~ ^http.* ]]; then
      if [[ "${SKIP_NODE_IMAGE_PREPULL}" = "true" ]]; then
          echo "Skipping node image download (SKIP_NODE_IMAGE_PREPULL is set to true)"
      else
          # Downloading image if it does not exist locally
          wget --no-verbose --no-check-certificate "${IMAGE_LOCATION}/${IMAGE_NAME}"
      fi
    else
      echo "Image not found at ${IMAGE_LOCATION}/${IMAGE_NAME}"
      exit 1
    fi
fi

# Prepare the image if it exists
if [[ -f "${IMAGE_NAME}" ]]; then
    IMAGE_SUFFIX="${IMAGE_NAME##*.}"
    if [[ "${IMAGE_SUFFIX}" = "xz" ]]; then
      unxz -v "${IMAGE_NAME}"
      IMAGE_NAME="$(basename "${IMAGE_NAME}" .xz)"
      export IMAGE_NAME
      IMAGE_BASE_NAME="${IMAGE_NAME%.*}"
      export IMAGE_RAW_NAME="${IMAGE_BASE_NAME}-raw.img"
    fi
    if [[ "${IMAGE_SUFFIX}" = "bz2" ]]; then
        bunzip2 "${IMAGE_NAME}"
        IMAGE_NAME="$(basename "${IMAGE_NAME}" .bz2)"
        export IMAGE_NAME
        IMAGE_BASE_NAME="${IMAGE_NAME%.*}"
        export IMAGE_RAW_NAME="${IMAGE_BASE_NAME}-raw.img"
    fi
    if [[ "${IMAGE_SUFFIX}" != "iso" ]]; then
        qemu-img convert -O raw "${IMAGE_NAME}" "${IMAGE_RAW_NAME}"
    fi
    # Generating image checksum if right checksum does not exist locally
    if [[ ! -f "${IMAGE_RAW_NAME}.${IMAGE_RAW_CHECKSUM##*.}" ]]; then
        IMAGE_SUFFIX="${IMAGE_NAME##*.}"
        if [[ "${IMAGE_SUFFIX}" != "iso" ]]; then
            sha256sum "${IMAGE_RAW_NAME}" | awk '{print $1}' > "${IMAGE_RAW_NAME}.sha256sum"
        fi
    fi
fi

popd

# NOTE(elfosardo): workaround for https://github.com/moby/moby/issues/44970
# should be fixed in docker-ce 23.0.2
if [[ "${OS}" = "ubuntu" ]]; then
  sudo systemctl restart docker
fi

# Pulling all the images except any local image.
for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
  IMAGE="${!IMAGE_VAR}"
  if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
    sudo "${CONTAINER_RUNTIME}" pull --platform="${LOCAL_CONTAINER_PLATFORM}" "${IMAGE}"
  else
    sudo "${CONTAINER_RUNTIME}" pull "${IMAGE}"
  fi
 done
