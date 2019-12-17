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
# shellcheck disable=SC1091
source /etc/os-release
# VERSION_ID can be "7" or "8.x" so strip the minor version
DISTRO="${ID}${VERSION_ID%.*}"

if [[ $DISTRO == "centos7" ]]; then
  sudo yum -y install epel-release dnf --enablerepo=extras
  # Install tripleo-repos, used to get a more recent version of some packages on CentOS7
  sudo dnf -y --repofrompath="current-tripleo,https://trunk.rdoproject.org/${DISTRO}-master/current-tripleo" install "python*-tripleo-repos" --nogpgcheck
  sudo tripleo-repos current-tripleo
  # There are some packages which are newer in the tripleo repos
  sudo yum -y update
fi

if [[ $DISTRO == "rhel8" ]]; then
  sudo subscription-manager repos --enable=ansible-2-for-rhel-8-x86_64-rpms
elif [[ $DISTRO == "centos8" ]]; then
  sudo dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  sudo dnf -y install epel-release
fi

if [[ $DISTRO == "rhel8" ]] || [[ $DISTRO == "centos8" ]]; then
  sudo dnf -y install python3
  sudo alternatives --set python /usr/bin/python3
fi

# Install required packages
sudo yum -y install \
  ansible \
  redhat-lsb-core \
  wget

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
