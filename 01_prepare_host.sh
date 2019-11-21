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

if ! command -v minikube 2>/dev/null ; then
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/.
fi

if ! command -v docker-machine-driver-kvm2 2>/dev/null ; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2
    chmod +x docker-machine-driver-kvm2
    sudo mv docker-machine-driver-kvm2 /usr/local/bin/.
fi

if ! command -v kubectl 2>/dev/null ; then
    curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/.
fi

if ! command -v kustomize 2>/dev/null ; then
    curl -Lo kustomize https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F"${KUSTOMIZE_VERSION}"/kustomize_kustomize."${KUSTOMIZE_VERSION}"_linux_amd64
    chmod +x kustomize
    sudo mv kustomize /usr/local/bin/.
fi

# Clean-up any old ironic containers
for name in ironic ironic-inspector dnsmasq httpd mariadb ipa-downloader; do
    sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" kill $name
    sudo "${CONTAINER_RUNTIME}" ps --all | grep -w "$name$" && sudo "${CONTAINER_RUNTIME}" rm $name -f
done

# Clean-up existing pod, if podman
case $CONTAINER_RUNTIME in
podman)
  if  sudo "${CONTAINER_RUNTIME}" pod exists ironic-pod ; then
      sudo "${CONTAINER_RUNTIME}" pod rm ironic-pod -f
  fi
  sudo "${CONTAINER_RUNTIME}" pod create -n ironic-pod
  ;;
esac

echo "TEST DNM test with new https://quay.io/repository/metal3-io/ironic"

# Pull images we'll need
for IMAGE_VAR in IRONIC_IMAGE IPA_DOWNLOADER_IMAGE VBMC_IMAGE SUSHY_TOOLS_IMAGE DOCKER_REGISTRY_IMAGE; do
    IMAGE=${!IMAGE_VAR}
    sudo "${CONTAINER_RUNTIME}" pull "$IMAGE"
done

# Download IPA and CentOS 7 Images
mkdir -p "$IRONIC_IMAGE_DIR"
pushd "$IRONIC_IMAGE_DIR"

if [ ! -f "${IMAGE_NAME}" ] ; then
    curl --insecure --compressed -O -L "${IMAGE_LOCATION}/${IMAGE_NAME}"
    md5sum "${IMAGE_NAME}" | awk '{print $1}' > "${IMAGE_NAME}.md5sum"
fi
popd

# Install requirements
ansible-galaxy install -r vm-setup/requirements.yml

ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "virthost=$HOSTNAME" \
  -i vm-setup/inventory.ini \
  -b -vvv vm-setup/install-package-playbook.yml

# Allow local non-root-user access to libvirt
# Restart libvirtd service to get the new group membership loaded
if ! id "$USER" | grep -q libvirt; then
  sudo usermod -a -G "libvirt" "$USER"
  sudo systemctl restart libvirtd
fi

# Start image downloader container
sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name ipa-downloader ${POD_NAME} \
     -v "$IRONIC_DATA_DIR":/shared "${IPA_DOWNLOADER_IMAGE}" /usr/local/bin/get-resource.sh

sudo "${CONTAINER_RUNTIME}" wait ipa-downloader

function configure_minikube() {
    minikube config set vm-driver kvm2
    minikube config set memory 4096
}

configure_minikube
init_minikube
