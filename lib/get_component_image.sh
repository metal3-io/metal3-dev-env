#!/usr/bin/env bash
#
# Usage: get_component_image.sh <image>
#
# Given an upstream image (optionally with a tag and/or digest), print the
# corresponding image in the local registry as
# "${REGISTRY}/localimages/<name>:<tag>".
set -eux

orig_image="${1:?usage: get_component_image.sh <image>}"

# Split the image name and tag.
tmp_image="${orig_image##*/}"
tmp_image="${tmp_image%@*}"
tmp_image_name="${tmp_image%%:*}"
tmp_image_tag="${tmp_image##*:}"

# Assign the image tag to latest if there is no tag in the image.
if [[ "${tmp_image_name}" = "${tmp_image_tag}" ]]; then
    tmp_image_tag="latest"
fi

echo "${REGISTRY}/localimages/${tmp_image_name}:${tmp_image_tag}"
