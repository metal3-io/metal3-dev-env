#!/usr/bin/env bash
set -ex

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

sudo dnf install -y libselinux-utils
if selinuxenabled ; then
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
source /etc/os-release
# VERSION_ID can be "7" or "8.x" so strip the minor version
DISTRO="${ID}${VERSION_ID%.*}"
if [[ $DISTRO =~ "centos" ]]; then
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

sudo pip3 install ansible==2.9.8

if [[ $DISTRO == "centos7" ]]; then
  # Install pip since it is used by the k8s Ansible module
  sudo dnf -y install python-pip
  # Install tripleo-repos, used to get a recent version of python-jinja2
  # which is required for some ansible templates
  sudo dnf -y --repofrompath="current-tripleo,https://trunk.rdoproject.org/${DISTRO}-master/current-tripleo" install "python*-tripleo-repos" --nogpgcheck
  sudo tripleo-repos current-tripleo


  # There are some packages which are newer in the tripleo repos
  # FIXME(stbenjam): On CentOS 7, the version of oniguruma conflicts with
  # the version shipped in the tripleo repos. This needs further
  # investigation.
  sudo dnf -y upgrade --exclude=oniguruma
fi

# We need the network variables, but can only source lib/network.sh after
# installing and setting up python
# shellcheck disable=SC1091
source lib/network.sh

if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  sudo dnf -y install podman
  sudo sed -i "/^\[registries\.insecure\]$/,/^\[/ s/^registries =.*/registries = [\"${REGISTRY}\"]/g" /etc/containers/registries.conf
else
  if [[ $DISTRO == "centos7" ]]; then
    sudo dnf install -y dnf-utils \
      device-mapper-persistent-data \
      lvm2
    sudo dnf config-manager \
      --add-repo \
      https://download.docker.com/linux/centos/docker-ce.repo
      cat <<EOF > daemon.json
{
  "insecure-registries" : ["${REGISTRY}"]
}
EOF
    sudo chown root:root daemon.json
    sudo dnf install -y docker-ce docker-ce-cli containerd.io
    sudo mkdir -p /etc/docker
    sudo mv daemon.json /etc/docker/daemon.json
    sudo systemctl restart docker
    sudo usermod -aG docker "${USER}"
  else
    echo "Only Podman is supported in CentOS/RHEL8"
    exit 1
  fi
fi
