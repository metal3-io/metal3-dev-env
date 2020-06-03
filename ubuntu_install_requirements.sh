#!/usr/bin/env bash
set -ex

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

# sudo apt install -y libselinux-utils
# if selinuxenabled ; then
#     sudo setenforce permissive
#     sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
# fi

# Update to latest packages first
sudo apt -y update

# Install required packages

sudo apt -y install \
  python3-pip \
  python3-setuptools \
  zlib1g-dev \
  libssl1.0-dev \
  openssh-server \
  wget

# There are some packages which are newer in the tripleo repos

# Setup yarn and nodejs repositories
#sudo curl -sL https://dl.yarnpkg.com/rpm/yarn.repo -o /etc/yum.repos.d/yarn.repo
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
#curl -sL https://rpm.nodesource.com/setup_10.x | sudo bash -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

# Add this repository to install podman
sudo add-apt-repository -y ppa:projectatomic/ppa
# Add this repository to install latest stable Golang
sudo add-apt-repository -y ppa:longsleep/golang-backports

# Update some packages from new repos
sudo apt -y update

# Install python packages not included as rpms
sudo pip3 install \
  ansible==2.9.1 \
  python-apt \
  openshift \
  pyYAML

# Set update-alternatives to python3
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.6 1

# make sure additional requirments are installed

##No bind-utils. It is for host, nslookop,..., no need in ubuntu

# We need the network variables, but can only source lib/network.sh after
# installing and setting up python
# shellcheck disable=SC1091
source lib/network.sh

if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  sudo apt -y install podman
  sudo sed -i "/^\[registries\.insecure\]$/,/^\[/ s/^registries =.*/registries = [\"${REGISTRY}\"]/g" /etc/containers/registries.conf
else
  sudo apt -y install \
    apt-transport-https \
    ca-certificates \
    gnupg-agent \
    software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
  sudo apt update
  cat <<EOF > daemon.json
{
  "insecure-registries" : ["${REGISTRY}"]
}
EOF
  sudo chown root:root daemon.json
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  sudo mkdir -p /etc/docker
  sudo mv daemon.json /etc/docker/daemon.json
  sudo systemctl restart docker
  sudo usermod -aG docker "${USER}"
fi
