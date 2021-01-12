#!/usr/bin/env bash
set -ex

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

sudo dnf install -y libselinux-utils
if getenforce | grep Enforcing; then
    sudo setenforce permissive
    sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
fi

# Remove any previous tripleo-repos to avoid version conflicts
# (see FIXME re oniguruma below)
sudo dnf -y remove "python*-tripleo-repos"

# Update to latest packages first
sudo dnf -y upgrade

# Install additional repos as needed for each OS version
# shellcheck disable=SC1091
if [[ $DISTRO == "centos8" ]]; then
    sudo dnf -y install epel-release dnf --enablerepo=extras
elif [[ $DISTRO == "rhel8" ]]; then
    sudo subscription-manager repos --enable=ansible-2-for-rhel-8-x86_64-rpms
fi

if [[ $DISTRO == "rhel8" || $DISTRO == "centos8" ]]; then
    sudo dnf -y install python3
    sudo alternatives --set python /usr/bin/python3
fi

# Install required packages
sudo dnf -y install \
  redhat-lsb-core \
  python3-pip \
  wget

sudo pip3 install ansible

# We need the network variables, but can only source lib/network.sh after
# installing and setting up python
# shellcheck disable=SC1091
source lib/network.sh

if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  sudo dnf -y install podman
  sudo sed -i "/^\[registries\.insecure\]$/,/^\[/ s/^registries =.*/registries = [\"${REGISTRY}\"]/g" /etc/containers/registries.conf
else
    echo "Only Podman is supported in CentOS/RHEL8"
    exit 1
fi
