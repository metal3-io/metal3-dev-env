#!/usr/bin/env bash
set -ex

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

sudo yum install -y libselinux-utils
if selinuxenabled ; then
    sudo setenforce permissive
    sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
fi

# Update to latest packages first
sudo yum -y update

# Install additional repos as needed for each OS version
if [ ! -f /etc/yum.repos.d/epel.repo ] ; then
    if grep -q "Red Hat Enterprise Linux release 7" /etc/redhat-release ; then
        sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    elif grep -q "Red Hat Enterprise Linux release 8" /etc/redhat-release ; then
        sudo subscription-manager repos --enable=ansible-2-for-rhel-8-x86_64-rpms
        sudo alternatives --set python /usr/bin/python3
    else
        sudo yum -y install epel-release --enablerepo=extras
    fi
fi

# Install required packages
# python-{requests,setuptools} required for tripleo-repos install
sudo yum -y install \
  ansible \
  redhat-lsb-core \
  wget

# We're reusing some tripleo pieces for this setup so clone them here
pushd $HOME
if [ ! -d tripleo-repos ]; then
  git clone https://git.openstack.org/openstack/tripleo-repos
fi
pushd tripleo-repos
sudo python setup.py install
popd
popd

# Needed to get a recent python-virtualbmc package
# Use the explicit path because on RHEL8 it gets installed
# to /usr/local/bin which isn't in the path for the sudo'd shell
TRIPLEO_REPOS=$(which tripleo-repos)
sudo $TRIPLEO_REPOS current-tripleo

# There are some packages which are newer in the tripleo repos
sudo yum -y update


if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  sudo yum -y install podman
else
  sudo yum install -y yum-utils \
    device-mapper-persistent-data \
    lvm2
  sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum install -y docker-ce docker-ce-cli containerd.io
  sudo systemctl start docker
fi
