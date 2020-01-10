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

# ansible uses default python2 (python-pip) to run on the local machine
sudo apt -y install \
  python3-pip \
  python-pip \
  python-setuptools \
  zlib1g-dev \
  libssl1.0-dev \
  wget

# There are some packages which are newer in the tripleo repos

# Setup yarn and nodejs repositories
#sudo curl -sL https://dl.yarnpkg.com/rpm/yarn.repo -o /etc/yum.repos.d/yarn.repo
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
#curl -sL https://rpm.nodesource.com/setup_10.x | sudo bash -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

# Add this repository to install podman
sudo add-apt-repository -y ppa:projectatomic/ppa
# Add this repository to install Golang 1.12
sudo add-apt-repository -y ppa:longsleep/golang-backports

# Update some packages from new repos
sudo apt -y update

# make sure additional requirments are installed

##No bind-utils. It is for host, nslookop,..., no need in ubuntu

if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  sudo apt -y install podman
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
  "insecure-registries" : ["192.168.111.1:5000"]
}
EOF
  sudo chown root:root daemon.json
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  sudo mv daemon.json /etc/docker
  sudo systemctl start docker
fi

# Install python packages not included as rpms
sudo pip3 install \
  ansible==2.8.2 \
  python-apt
