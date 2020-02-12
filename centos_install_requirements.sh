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

# Remove any previous tripleo-repos to avoid version conflicts
# (see FIXME re oniguruma below)
sudo yum -y erase "python*-tripleo-repos"

# Update to latest packages first
sudo yum -y update

# Install additional repos as needed for each OS version
# shellcheck disable=SC1091
source /etc/os-release
# VERSION_ID can be "7" or "8.x" so strip the minor version
DISTRO="${ID}${VERSION_ID%.*}"
if [ ! -f /etc/yum.repos.d/epel.repo ] ; then
    if [[ $DISTRO == "rhel7" ]]; then
        sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    elif [[ $DISTRO == "centos7" ]]; then
        sudo yum -y install epel-release --enablerepo=extras
    fi
fi

if [[ $DISTRO == "centos7" ]]; then
    sudo yum -y install epel-release dnf --enablerepo=extras
fi

if [[ $DISTRO == "rhel8" ]]; then
    sudo subscription-manager repos --enable=ansible-2-for-rhel-8-x86_64-rpms
    sudo yum -y install python3
    sudo alternatives --set python /usr/bin/python3
fi

# Install required packages
# python-{requests,setuptools} required for tripleo-repos install
sudo yum -y install \
  ansible \
  redhat-lsb-core \
  python3-pip \
  wget

# Install tripleo-repos, used to get a recent version of python-virtualbmc
sudo dnf -y --repofrompath="current-tripleo,https://trunk.rdoproject.org/${DISTRO}-master/current-tripleo" install "python*-tripleo-repos" --nogpgcheck
sudo tripleo-repos current-tripleo


# There are some packages which are newer in the tripleo repos
# FIXME(stbenjam): On CentOS 7, the version of oniguruma conflicts with
# the version shipped in the tripleo repos. This needs further
# investigation.
sudo yum -y update --exclude=oniguruma

if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  sudo yum -y install podman
else
  sudo yum install -y yum-utils \
    device-mapper-persistent-data \
    lvm2
  sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
    cat <<EOF > daemon.json
{
  "insecure-registries" : ["192.168.111.1:5000"]
}
EOF
  sudo chown root:root daemon.json
  sudo yum install -y docker-ce docker-ce-cli containerd.io
  sudo mkdir -p /etc/docker
  sudo mv daemon.json /etc/docker/daemon.json
  sudo systemctl restart docker
fi
