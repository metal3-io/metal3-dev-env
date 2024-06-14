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
  sudo apt-get -y install python3-pip python3-dev python3-venv jq curl wget pkg-config bash-completion

  # Set update-alternatives to python3
  if [[ "${DISTRO}" = "ubuntu18" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.6 1
  elif [[ "${DISTRO}" = "ubuntu20" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  elif [[ "${DISTRO}" = "ubuntu22" ]]; then
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
  fi
elif [[ "${OS}" = "centos" ]] || [[ "${OS}" = "rhel" ]]; then
  sudo dnf upgrade -y --nobest
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

# NOTE(tuminoid) lib/releases.sh must be after the jq and python installation
# TODO: fix all of the lib/ scripts not to actually run code, but only define functions
# shellcheck disable=SC1091
source lib/releases.sh
# shellcheck disable=SC1091
source lib/download.sh
# NOTE(fmuyassarov) Make sure to source before runnig install-package-playbook.yml
# because there are some vars exported in network.sh and used by
# install-package-playbook.yml.
# shellcheck disable=SC1091
source lib/network.sh

# NOTE(dtantsur): system-site-packages is required because of certain Python
# packages that cannot be pip-installed (firewalld, selinux, etc).
sudo python -m venv --system-site-packages "${ANSIBLE_VENV}"
# TODO: since ansible 8.0.0, pinning by digest is PITA, due additional ansible
# dependencies, which would need to be pinned as well, so it is skipped for now
sudo "${ANSIBLE_VENV}/bin/pip" install ansible=="${ANSIBLE_VERSION}"

# Install requirements
"${ANSIBLE}-galaxy" install -r vm-setup/requirements.yml

# Install required packages
ANSIBLE_FORCE_COLOR=true "${ANSIBLE}-playbook" \
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


## Install krew
if ! kubectl krew > /dev/null 2>&1; then
  download_and_install_krew
fi

# Allow local non-root-user access to libvirt
if ! id "${USER}" | grep -q libvirt; then
  sudo usermod -a -G "libvirt" "${USER}"
fi

if [[ "${EPHEMERAL_CLUSTER}" = "minikube" ]]; then
  if ! command -v minikube &>/dev/null || [[ "$(minikube version --short)" != "${MINIKUBE_VERSION}" ]]; then
    download_and_install_minikube
    download_and_install_kvm2_driver
  fi

  if ! command -v docker-machine-driver-kvm2 &>/dev/null ; then
    download_and_install_kvm2_driver
  fi
# Install Kind for both Kind and tilt
else
  if ! command -v kind &>/dev/null || [[ "v$(kind version -q)" != "${KIND_VERSION}" ]]; then
    download_and_install_kind
  fi
  if [[ "${EPHEMERAL_CLUSTER}" = "tilt" ]]; then
    download_and_install_tilt
  fi
fi

if ! command -v kubectl &>/dev/null || [[ "$(kubectl version --client -o json|jq -r '.clientVersion.gitVersion')" != "${KUBECTL_VERSION}" ]]; then
  download_and_install_kubectl
fi

if ! command -v kustomize &>/dev/null; then
  download_and_install_kustomize
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
  *)
    ;;
esac

# pre-pull node and container images
# shellcheck disable=SC1091
source lib/image_prepull.sh
