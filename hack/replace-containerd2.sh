#!/usr/bin/env bash

# This script install containerd 2.1.3, as it was the newest at the time of
# writing this.
#
# Ubuntu's version of Docker depends on containerd 1.7, but > 2.0 is needed for
# IPv6 support. This script replaces old containerd installation with
# containerd 2.1.3, as it was the newest at the time of writing this.
#
# You might need to install Docker before running this script. If Docker is not
# installed, dev env will install it and it might override the version. If
# Docker is already installed, dev env won't install it again and these changes
# will remain.

set -eux

sudo systemctl stop docker
sudo systemctl stop containerd

SAVE_DIR=${SAVE_DIR:-"/tmp"}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-"v2.1.3"}

containerd="containerd.tar.gz"
wget -O "${SAVE_DIR}"/"${containerd}" https://github.com/containerd/containerd/releases/download/"${CONTAINERD_VERSION}"/containerd-"${CONTAINERD_VERSION}"-linux-amd64.tar.gz

### Install containerd
# remove first old
if [[ -e /usr/local/bin/containerd ]]; then
    sudo mv /usr/local/bin/containerd /usr/local/bin/containerd.backup
    sudo mv /usr/local/bin/containerd-shim-runc-v2 /usr/local/bin/containerd-shim-runc-v2.backup
    sudo mv /usr/local/bin/ctr /usr/local/bin/ctr.backup
    sudo mv /usr/local/bin/containerd-stress /usr/local/bin/containerd-stress.backup
fi
# Install new
sudo tar Cxzvf /usr/local "${SAVE_DIR}"/"${containerd}"

# Restart stuff
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl start containerd
sudo systemctl start docker
