#!/usr/bin/env bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

if [[ $OS == ubuntu ]]; then
  # shellcheck disable=SC1091
  source ubuntu_install_requirements.sh
else
  # shellcheck disable=SC1091
  source centos_install_requirements.sh
fi

if ! which minikube 2>/dev/null ; then
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/.
fi

if ! which docker-machine-driver-kvm2 2>/dev/null ; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2
    chmod +x docker-machine-driver-kvm2
    sudo mv docker-machine-driver-kvm2 /usr/local/bin/.
fi

if ! which kubectl 2>/dev/null ; then
    curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/.
fi

if ! which kustomize 2>/dev/null ; then
    curl -Lo kustomize "$(curl --silent -L https://github.com/kubernetes-sigs/kustomize/releases/latest 2>&1 | awk -F'"' '/linux_amd64/ { print "https://github.com"$2; exit }')"
    chmod +x kustomize
    sudo mv kustomize /usr/local/bin/.
fi

# Download Ironic binary and Ironic inspector image

mkdir -p "$IRONIC_DATA_DIR/html/images"
pushd "$IRONIC_DATA_DIR/html/images"
if [ ! -f ironic-python-agent.initramfs ]; then
    curl --insecure --compressed -L https://images.rdoproject.org/master/rdo_trunk/current-tripleo-rdo/ironic-python-agent.tar | tar -xf -
fi

for IMAGE_VAR in IRONIC_IMAGE IRONIC_INSPECTOR_IMAGE ; do
    IMAGE=${!IMAGE_VAR}
    sudo "${CONTAINER_RUNTIME}" pull "$IMAGE"
done

## Download centos 7 qcow2 image

CENTOS_IMAGE=CentOS-7-x86_64-GenericCloud-1901.qcow2
if [ ! -f ${CENTOS_IMAGE} ] ; then
    curl --insecure --compressed -O -L http://cloud.centos.org/centos/7/images/${CENTOS_IMAGE}
    md5sum ${CENTOS_IMAGE} | awk '{print $1}' > ${CENTOS_IMAGE}.md5sum
fi
popd

ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -i vm-setup/inventory.ini \
  -b -vvv vm-setup/install-package-playbook.yml

sudo "${CONTAINER_RUNTIME}" pull "${VBMC_IMAGE}"
sudo "${CONTAINER_RUNTIME}" pull "${SUSHY_TOOLS_IMAGE}"

# Allow local non-root-user access to libvirt
# Restart libvirtd service to get the new group membership loaded
if ! id "$USER" | grep -q libvirt; then
  sudo usermod -a -G "libvirt" "$USER"
  sudo systemctl restart libvirtd
fi

function configure_minikube() {
    minikube config set vm-driver kvm2
}

function init_minikube() {
    # If the vm exists, it has already been initialized
    if [[ "$(sudo virsh list --all)" != *"minikube"* ]]; then
      sudo su -l -c "minikube start" "$USER"
      # The interface doesn't appear in the minikube VM with --live,
      # so just attach it and make it reboot. As long as the
      # 02_configure_host.sh script does not run, the provisioning network does
      # not exist. Attempting to start Minikube will fail until it is created.
      sudo virsh attach-interface --domain minikube \
          --model virtio --source provisioning \
          --type network --config
      sudo su -l -c "minikube stop" "$USER"
    fi
}

configure_minikube
init_minikube
