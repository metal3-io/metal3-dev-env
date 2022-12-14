#!/usr/bin/env bash
set -xe

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

if [[ $(id -u) == 0 ]]; then
  echo "Please run 'make' as a non-root user"
  exit 1
fi

if [[ $OS == ubuntu ]]; then
  sudo apt-get update
  sudo apt -y install python3-pip jq curl wget

  # Set update-alternatives to python3
  if [[ ${DISTRO} == "ubuntu18" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.6 1
  elif [[ ${DISTRO} == "ubuntu20" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  elif [[ ${DISTRO} == "ubuntu22" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
    # (workaround) disable tdp_mmu to avoid
    # kernel crashes with  NULL pointer dereference
    sudo modprobe -r -a kvm_intel kvm
    sudo modprobe kvm tdp_mmu=0
    sudo modprobe -a kvm kvm_intel
  fi
elif [[ $OS == "centos" || $OS == "rhel" ]]; then
  sudo dnf upgrade -y
  case $VERSION_ID in
    8)
      sudo dnf config-manager --set-enabled powertools
      sudo dnf install -y epel-release
      ;;
    9)
      sudo dnf config-manager --set-enabled crb
      sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
      ;;
    *)
      echo -n "CentOS or RHEL version not supported"
      exit 1
      ;;
  esac
  sudo dnf -y install python3-pip jq curl wget
  sudo ln -s /usr/bin/python3 /usr/bin/python || true
fi

sudo python -m pip install ansible=="${ANSIBLE_VERSION}"

# NOTE(fmuyassarov) Make sure to source before runnig install-package-playbook.yml
# because there are some vars exported in network.sh and used by
# install-package-playbook.yml.
# shellcheck disable=SC1091
source lib/network.sh

# Install requirements
ansible-galaxy install -r vm-setup/requirements.yml

# Install required packages
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -e "working_dir=$WORKING_DIR" \
  -e "metal3_dir=$SCRIPTDIR" \
  -e "virthost=$HOSTNAME" \
  -i vm-setup/inventory.ini \
  -b vm-setup/install-package-playbook.yml

# Workaround on centos network manager versions higher than 1.40.0-1.el9 are failing after creating a bridge e.g running:

# tee -a /etc/NetworkManager/system-connections/provisioning-1.nmconnection <<EOF
# [connection]
# id=provisioning-1
# type=bridge
# interface-name=provisioning-1
# [bridge]
# stp=false
# [ipv4]
# address1=172.22.0.1/24
# method=manual
# [ipv6]
# addr-gen-mode=eui64
# method=disabled
# EOF
# chmod 600 /etc/NetworkManager/system-connections/provisioning-1.nmconnection
# nmcli con load /etc/NetworkManager/system-connections/provisioning-1.nmconnection
# nmcli con up provisioning-1

# After those commands ssh connection will be lost
# This workaround downgrade NetworkManager version to NetworkManager-1.40.0-1.el9
if [[ $OS == "centos" || $OS == "rhel" ]]; then
  sudo yum downgrade -y NetworkManager-1.40.0-1.el9
  sudo systemctl restart NetworkManager
fi

# shellcheck disable=SC1091
source lib/network.sh
# shellcheck disable=SC1091
source lib/images.sh

# Add usr/local/go/bin to the PATH environment variable
GOBINARY="/usr/local/go/bin"
if [[ ":$PATH:" != *":$GOBINARY:"* ]]; then
  echo export PATH="$PATH":/usr/local/go/bin >> ~/.bashrc
  # shellcheck disable=SC1090
  source ~/.bashrc
fi

# shellcheck disable=SC1091
source lib/releases.sh

## Install krew
if ! kubectl krew > /dev/null 2>&1; then
  cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  rm -f "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
  # Add krew to PATH by appending this line to .bashrc
  krew_path_bashrc="export PATH=${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
  # Add the line if it is not already there
  grep -qxF "${krew_path_bashrc}" ~/.bashrc || echo "${krew_path_bashrc}" >> ~/.bashrc
fi

# Allow local non-root-user access to libvirt
# Restart libvirtd service to get the new group membership loaded
if ! id "$USER" | grep -q libvirt; then
  sudo usermod -a -G "libvirt" "$USER"
  sudo systemctl restart libvirtd
fi

if [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
  if ! command -v minikube 2>/dev/null || [[ "$(minikube version --short)" != "${MINIKUBE_VERSION}" ]]; then
      wget --no-verbose -O minikube https://storage.googleapis.com/minikube/releases/"${MINIKUBE_VERSION}"/minikube-linux-amd64
      chmod +x minikube
      sudo mv minikube /usr/local/bin/.
  fi

  if ! command -v docker-machine-driver-kvm2 2>/dev/null ; then
      wget --no-verbose -O docker-machine-driver-kvm2 https://storage.googleapis.com/minikube/releases/"${MINIKUBE_VERSION}"/docker-machine-driver-kvm2
      chmod +x docker-machine-driver-kvm2
      sudo mv docker-machine-driver-kvm2 /usr/local/bin/.
  fi
# Install Kind for both Kind and tilt
else
  if ! command -v kind 2>/dev/null || [[ "v$(kind version -q)" != "$KIND_VERSION" ]]; then
      wget --no-verbose -O ./kind https://github.com/kubernetes-sigs/kind/releases/download/"${KIND_VERSION}"/kind-"$(uname)"-amd64
      chmod +x ./kind
      sudo mv kind /usr/local/bin/.
  fi
  if [ "${EPHEMERAL_CLUSTER}" == "tilt" ]; then
    curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
  fi
fi

KUBECTL_LATEST=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
KUBECTL_LOCAL=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion' 2> /dev/null)
KUBECTL_PATH=$(whereis -b kubectl | cut -d ":" -f2 | awk '{print $1}')

if [ "$KUBECTL_LOCAL" != "$KUBECTL_LATEST" ]; then
    wget --no-verbose -O kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_LATEST}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    KUBECTL_PATH="${KUBECTL_PATH:-/usr/local/bin/kubectl}"
    sudo mv kubectl "${KUBECTL_PATH}"
fi

if ! command -v kustomize 2>/dev/null ; then
    wget --no-verbose "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
    tar -xzvf "kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
    chmod +x kustomize
    sudo mv kustomize /usr/local/bin/.
    rm "kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
fi

# Install clusterctl client
function install_clusterctl() {
  wget --no-verbose -O clusterctl https://github.com/kubernetes-sigs/cluster-api/releases/download/"${CAPIRELEASE}"/clusterctl-linux-amd64
  chmod +x ./clusterctl
  sudo mv ./clusterctl /usr/local/bin/clusterctl
}

if ! [ -x "$(command -v clusterctl)" ]; then
  install_clusterctl
elif [ "$(clusterctl version | grep -o -P '(?<=GitVersion:").*?(?=",)')" != "${CAPIRELEASE}" ]; then
  sudo rm /usr/local/bin/clusterctl
  install_clusterctl
fi

# Clean-up any old ironic containers
remove_ironic_containers

# Clean-up existing pod, if podman
case $CONTAINER_RUNTIME in
podman)
  for pod in ironic-pod infra-pod; do
    if  sudo "${CONTAINER_RUNTIME}" pod exists "${pod}" ; then
        sudo "${CONTAINER_RUNTIME}" pod rm "${pod}" -f
    fi
    sudo "${CONTAINER_RUNTIME}" pod create -n "${pod}"
  done
  ;;
esac


mkdir -p "$IRONIC_IMAGE_DIR"
pushd "$IRONIC_IMAGE_DIR"

if [ ! -f "${IMAGE_NAME}" ] ; then
    wget --no-verbose --no-check-certificate "${IMAGE_LOCATION}/${IMAGE_NAME}"
    IMAGE_SUFFIX="${IMAGE_NAME##*.}"
    if [ "${IMAGE_SUFFIX}" == "xz" ] ; then
      unxz -v "${IMAGE_NAME}"
      IMAGE_NAME="$(basename "${IMAGE_NAME}" .xz)"
      export IMAGE_NAME
      IMAGE_BASE_NAME="${IMAGE_NAME%.*}"
      export IMAGE_RAW_NAME="${IMAGE_BASE_NAME}-raw.img"
    fi
    if [ "${IMAGE_SUFFIX}" == "bz2" ] ; then
        bunzip2 "${IMAGE_NAME}"
        IMAGE_NAME="$(basename "${IMAGE_NAME}" .bz2)"
        export IMAGE_NAME
        IMAGE_BASE_NAME="${IMAGE_NAME%.*}"
        export IMAGE_RAW_NAME="${IMAGE_BASE_NAME}-raw.img"
    fi
    if [ "${IMAGE_SUFFIX}" != "iso" ] ; then
        qemu-img convert -O raw "${IMAGE_NAME}" "${IMAGE_RAW_NAME}"
        md5sum "${IMAGE_RAW_NAME}" | awk '{print $1}' > "${IMAGE_RAW_NAME}.md5sum"
    fi
fi
popd

# Pulling all the images except any local image.
for IMAGE_VAR in $(env | grep -v "_LOCAL_IMAGE=" | grep "_IMAGE=" | grep -o "^[^=]*") ; do
  IMAGE="${!IMAGE_VAR}"
  pull_container_image_if_missing "$IMAGE"
 done

if ${IPA_DOWNLOAD_ENABLED} || [ ! -f "${IRONIC_DATA_DIR}/html/images/ironic-python-agent.kernel" ]; then
    # Run image downloader container. The output is very verbose and not that interesting so we hide it.
    for i in {1..5}; do
        echo "Attempting to download IPA. $i/5"
        #shellcheck disable=SC2086
        sudo "${CONTAINER_RUNTIME}" run --rm --net host --name ipa-downloader ${POD_NAME} \
          -e IPA_BASEURI="$IPA_BASEURI" \
          -v "$IRONIC_DATA_DIR":/shared "${IPA_DOWNLOADER_IMAGE}" \
          /bin/bash -c "/usr/local/bin/get-resource.sh &> /dev/null" && s=0 && break || s=$?
    done
    (exit "${s}")
fi

function configure_minikube() {
    minikube config set driver kvm2
    minikube config set memory 4096
}

#
# Create Minikube VM and add correct interfaces
#
function init_minikube() {
    #If the vm exists, it has already been initialized
    if [[ "$(sudo virsh list --name --all)" != *"minikube"* ]]; then
      # Loop to ignore minikube issues
      while /bin/true; do
        minikube_error=0
        # Restart libvirtd.service as suggested here
        # https://github.com/kubernetes/minikube/issues/3566
        sudo systemctl restart libvirtd.service
        configure_minikube
        #NOTE(elfosardo): workaround for https://bugzilla.redhat.com/show_bug.cgi?id=2057769
        sudo mkdir -p /etc/qemu/firmware
        sudo touch /etc/qemu/firmware/50-edk2-ovmf-amdsev.json
        sudo su -l -c "minikube start --insecure-registry ${REGISTRY}"  "${USER}" || minikube_error=1
        if [[ $minikube_error -eq 0 ]]; then
          break
        fi
        sudo su -l -c 'minikube delete --all --purge' "${USER}"
        # NOTE (Mohammed): workaround for https://github.com/kubernetes/minikube/issues/9878
        sudo ip link delete virbr0
      done
      sudo su -l -c "minikube stop" "$USER"
    fi

    MINIKUBE_IFACES="$(sudo virsh domiflist minikube)"

    # The interface doesn't appear in the minikube VM with --live,
    # so just attach it before next boot. As long as the
    # 02_configure_host.sh script does not run, the provisioning network does
    # not exist. Attempting to start Minikube will fail until it is created.
    if ! echo "$MINIKUBE_IFACES" | grep -w provisioning  > /dev/null ; then
      sudo virsh attach-interface --domain minikube \
          --model virtio --source provisioning \
          --type network --config
    fi

    if ! echo "$MINIKUBE_IFACES" | grep -w baremetal  > /dev/null ; then
      sudo virsh attach-interface --domain minikube \
          --model virtio --source baremetal \
          --type network --config
    fi
}

if [ "${EPHEMERAL_CLUSTER}" == "minikube" ]; then
  init_minikube
fi
