#!/usr/bin/env bash
set -eux

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Please run 'make' as a non-root user"
  exit 1
fi

if [[ "${OS}" = "ubuntu" ]]; then
  # Set apt retry limit to higher than default to
  # make the data retrival more reliable
  sudo sh -c ' echo "Acquire::Retries \"10\";" > /etc/apt/apt.conf.d/80-retries '
  sudo apt-get update
  sudo apt-get -y install python3-pip jq curl wget pkg-config bash-completion

  # Set update-alternatives to python3
  if [[ "${DISTRO}" = "ubuntu18" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.6 1
  elif [[ "${DISTRO}" = "ubuntu20" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  elif [[ "${DISTRO}" = "ubuntu22" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
    # (workaround) disable tdp_mmu to avoid
    # kernel crashes with  NULL pointer dereference
    # note(elfosardo): run this only if we have kvm support
    if grep -q vmx /proc/cpuinfo; then
      sudo modprobe -r -a kvm_intel kvm
      sudo modprobe kvm tdp_mmu=0
      sudo modprobe -a kvm kvm_intel
    elif grep -q svm /proc/cpuinfo; then
      sudo modprobe -r -a kvm_amd kvm
      sudo modprobe kvm tdp_mmu=0
      sudo modprobe -a kvm kvm_amd
    fi
  fi
elif [[ "${OS}" = "centos" ]] || [[ "${OS}" = "rhel" ]]; then
  sudo dnf upgrade -y
  case "${VERSION_ID}" in
    8)
      sudo dnf config-manager --set-enabled powertools
      sudo dnf install -y epel-release
      ;;
    9)
      sudo dnf config-manager --set-enabled crb
      sudo dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
      ;;
    *)
      echo -n "CentOS or RHEL version not supported"
      exit 1
      ;;
  esac
  sudo dnf -y install python3-pip jq curl wget pkgconf-pkg-config bash-completion
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
  -e "working_dir=${WORKING_DIR}" \
  -e "metal3_dir=${SCRIPTDIR}" \
  -e "virthost=${HOSTNAME}" \
  -i vm-setup/inventory.ini \
  -b vm-setup/install-package-playbook.yml

# Add usr/local/go/bin to the PATH environment variable
GOBINARY="${GOBINARY:-/usr/local/go/bin}"
if [[ ! "${PATH}" =~ .*(:|^)(${GOBINARY})(:|$).* ]]; then
  echo "export PATH=${PATH}:${GOBINARY}" >> ~/.bashrc
  export PATH=${PATH}:${GOBINARY}
fi

# shellcheck disable=SC1091
source lib/releases.sh

## Install krew
if ! kubectl krew > /dev/null 2>&1; then
  pushd "$(mktemp -d)" &&
  KERNEL_OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${KERNEL_OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  rm -f "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
  # Add krew to PATH by appending this line to .bashrc
  krew_path_bashrc="export PATH=${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
  # Add the line if it is not already there
  grep -qxF "${krew_path_bashrc}" ~/.bashrc || echo "${krew_path_bashrc}" >> ~/.bashrc
  popd
fi

# Allow local non-root-user access to libvirt
# Restart libvirtd service to get the new group membership loaded
if ! id "${USER}" | grep -q libvirt; then
  sudo usermod -a -G "libvirt" "${USER}"
  sudo systemctl restart libvirtd
fi

if [[ "${EPHEMERAL_CLUSTER}" = "minikube" ]]; then
  if ! command -v minikube &>/dev/null || [ "$(minikube version --short)" != "${MINIKUBE_VERSION}" ]; then
      wget --no-verbose -O minikube "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
      chmod +x minikube
      sudo mv minikube /usr/local/bin/
  fi

  if ! command -v docker-machine-driver-kvm2 &>/dev/null ; then
      wget --no-verbose -O docker-machine-driver-kvm2 "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/docker-machine-driver-kvm2"
      chmod +x docker-machine-driver-kvm2
      sudo mv "docker-machine-driver-kvm2" "/usr/local/bin/"
  fi
# Install Kind for both Kind and tilt
else
  if ! command -v kind &>/dev/null || [[ "v$(kind version -q)" != "${KIND_VERSION}" ]]; then
      wget --no-verbose -O "./kind" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-$(uname)-amd64"
      chmod +x ./kind
      sudo mv kind "/usr/local/bin/"
  fi
  if [[ "${EPHEMERAL_CLUSTER}" = "tilt" ]]; then
    curl -fsSL "https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh" | bash
  fi
fi

KUBECTL_LATEST=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
KUBECTL_LOCAL=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion' 2> /dev/null)
KUBECTL_PATH=$(whereis -b kubectl | cut -d ":" -f2 | awk '{print $1}')

if [ "${KUBECTL_LOCAL}" != "${KUBECTL_LATEST}" ]; then
    wget --no-verbose -O kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_LATEST}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    KUBECTL_PATH="${KUBECTL_PATH:-/usr/local/bin/kubectl}"
    sudo mv kubectl "${KUBECTL_PATH}"
fi

if ! command -v kustomize &>/dev/null ; then
    wget --no-verbose "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
    tar -xzvf "kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
    chmod +x kustomize
    sudo mv kustomize /usr/local/bin/
    rm "kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
fi

BASH_COMPLETION="/etc/bash_completion.d/kubectl"
if [[ ! -r "${BASH_COMPLETION}" ]]; then
  kubectl completion bash | sudo tee "${BASH_COMPLETION}"
fi

# Clean-up any old ironic containers
remove_ironic_containers

# Clean-up existing pod, if podman
case "${CONTAINER_RUNTIME}" in
podman)
  for pod in ironic-pod infra-pod; do
    if  sudo "${CONTAINER_RUNTIME}" pod exists "${pod}" ; then
        sudo "${CONTAINER_RUNTIME}" pod rm "${pod}" -f
    fi
    sudo "${CONTAINER_RUNTIME}" pod create -n "${pod}"
  done
  ;;
esac

# pre-pull node and container images
# shellcheck disable=SC1091
source lib/image_prepull.sh
