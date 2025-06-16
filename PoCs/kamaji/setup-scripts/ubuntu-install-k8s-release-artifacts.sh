#!/usr/bin/env bash

KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.33.0}"
# KUBERNETES_VERSION="$(curl -sSL https://dl.k8s.io/release/stable.txt)"

# Kubernetes release tooling
# See https://github.com/kubernetes/release/releases
RELEASE_VERSION="${RELEASE_VERSION:-v0.18.0}"

# https://github.com/kubernetes-sigs/cri-tools/releases
CRICTL_VERSION="v1.33.0"

# https://github.com/containernetworking/plugins/releases
CNI_PLUGINS_VERSION="v1.7.1"

ARCH=$(dpkg --print-architecture)

echo "Installing Kubernetes ${KUBERNETES_VERSION} on $${ARCH} architecture"
echo "Using release version ${RELEASE_VERSION}"
echo "Using CRI tools version ${CRICTL_VERSION}"
echo "Using CNI plugins version ${CNI_PLUGINS_VERSION}"

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install required packages
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Install crictl
curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" | sudo tar -C /usr/local/bin -xz

# Install CNI plugins
DEST="/opt/cni/bin"
sudo mkdir -p "${DEST}"
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | sudo tar -C "$DEST" -xz

# Install kube stuff
sudo curl -L --remote-name-all "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/{kubeadm,kubelet}"
sudo install kubeadm kubelet /usr/bin/

curl -L --output 10-kubeadm.conf "https://github.com/kubernetes/release/raw/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf"
sudo mkdir -p /usr/lib/systemd/system/kubelet.service.d
sudo mv 10-kubeadm.conf /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
curl -L --output kubelet.service "https://github.com/kubernetes/release/raw/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service"
sudo mv kubelet.service /usr/lib/systemd/system/kubelet.service

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Enable SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Enable device ownership from security context. Needed for kubevirt CDI block devices.
# See https://github.com/kubevirt/containerized-data-importer/blob/main/doc/block_cri_ownership_config.md
sudo sed -i 's/device_ownership_from_security_context = false/device_ownership_from_security_context = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Disable swap
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Load required modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure system settings for Kubernetes
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
