#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source lib/logging.sh

if [[ "${EUID}" -eq 0 ]]; then
    echo "Please run 'make' as a non-root user"
    exit 1
fi

install_packages() {
    if [[ "${OS}" = "ubuntu" ]]; then
        # Set apt retry limit to higher than default to
        # make the data retrival more reliable
        sudo sh -c ' echo "Acquire::Retries \"10\";" > /etc/apt/apt.conf.d/80-retries '
        sudo apt-get update
        sudo apt-get -y install python3-pip python3-dev python3-venv jq curl wget pkg-config bash-completion

        # Set update-alternatives to python3
        case "${DISTRO}" in
            ubuntu22)
                sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 ;;
            ubuntu24)
                sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 ;;
            *) ;;
        esac

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
            10)
                sudo dnf config-manager --set-enabled crb
                sudo dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm"
                ;;
            *)
                echo -n "CentOS or RHEL version not supported"
                exit 1
                ;;
        esac
        sudo dnf -y install python3-pip jq curl wget pkgconf-pkg-config bash-completion
        sudo ln -s /usr/bin/python3 /usr/bin/python || true

    elif [[ "${OS}" = "opensuse-leap" ]]; then
        # sudo SUSEConnect --product sle-module-containers/15.6/x86_64
        sudo zypper refresh
        sudo zypper -n in python311 python311-pip jq bash-completion apparmor-utils update-alternatives
        sudo update-alternatives --install /usr/bin/python python3.11 /usr/bin/python3.11 20
        # Disable apparmor, it causes troubles when running dnsmasq with kind
        # sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 10
        # sudo aa-disable dnsmasq
        sudo aa-teardown
    fi
}

prepare_venv() {
    # NOTE(dtantsur): system-site-packages is required because of certain Python
    # packages that cannot be pip-installed (firewalld, selinux, etc).
    rm -rf "${ANSIBLE_VENV}"
    sudo python -m venv --system-site-packages "${ANSIBLE_VENV}"
    # TODO: since ansible 8.0.0, pinning by digest is PITA, due additional ansible
    # dependencies, which would need to be pinned as well, so it is skipped for now
    sudo "${ANSIBLE_VENV}/bin/pip" install --ignore-installed ansible=="${ANSIBLE_VERSION}"
}

install_krew() {
    if ! kubectl krew > /dev/null 2>&1; then
        download_and_install_krew
    fi
}

install_cluster_runtime() {
    if [[ "${BOOTSTRAP_CLUSTER}" = "minikube" ]]; then
        # shellcheck disable=SC2312
        if ! command -v minikube &>/dev/null || [[ "$(minikube version --short)" != "${MINIKUBE_VERSION}" ]]; then
            download_and_install_minikube
            download_and_install_kvm2_driver
        fi

        if ! command -v docker-machine-driver-kvm2 &>/dev/null ; then
            download_and_install_kvm2_driver
        fi
    # Install Kind for both Kind and tilt
    else
        # shellcheck disable=SC2312
        if ! command -v kind &>/dev/null || [[ "v$(kind version -q)" != "${KIND_VERSION}" ]]; then
            download_and_install_kind
        fi
        if [[ "${BOOTSTRAP_CLUSTER}" = "tilt" ]]; then
            download_and_install_tilt
        fi
    fi
}

install_kubectl_and_tools() {
    # shellcheck disable=SC2312
    if ! command -v kubectl &>/dev/null || [[ "$(kubectl version --client -o json|jq -r '.clientVersion.gitVersion')" != "${KUBECTL_VERSION}" ]]; then
        download_and_install_kubectl
    fi

    if ! command -v kustomize &>/dev/null; then
        download_and_install_kustomize
    fi

    BASH_COMPLETION="/etc/bash_completion.d/kubectl"
    if [[ ! -r "${BASH_COMPLETION}" ]]; then
        # shellcheck disable=SC2312
        kubectl completion bash | sudo tee "${BASH_COMPLETION}" >/dev/null
    fi
}

prepull_images() {
    # TODO (mboukhalfa) fake images
    if [[ "${NODES_PLATFORM}" = "fake" ]]; then
        echo "Skipping image prepulling on fake nodes platform"
        return
    fi
    # pre-pull node and container images
    # shellcheck disable=SC1091
    lib/image_prepull.sh
}

# ***** Execution *****

step "Source lib/common"
source_quiet_with_log_dump_on_failure "source-common" source lib/common.sh

step "Install packages"
run_quiet_with_log_dump_on_failure "install-packages" install_packages

# NOTE(tuminoid) lib/releases.sh must be after the jq and python installation
# TODO: fix all of the lib/ scripts not to actually run code, but only define functions
step "Source library scripts"
source_quiet_with_log_dump_on_failure "source-releases" source lib/releases.sh
source_quiet_with_log_dump_on_failure "source-download" source lib/download.sh
# NOTE(fmuyassarov) Make sure to source before running install-package-playbook.yml
# because there are some vars exported in network.sh and used by
# install-package-playbook.yml.
source_quiet_with_log_dump_on_failure "source-network" source lib/network.sh

step "Install python venv & run ansible"
run_quiet_with_log_dump_on_failure "prepare-ansible-venv" prepare_venv
run_quiet_with_log_dump_on_failure "install-ansible-requirements" "${ANSIBLE}-galaxy" install -r vm-setup/requirements.yml
run_quiet_with_log_dump_on_failure "ansible-install-pb" env ANSIBLE_FORCE_COLOR=true "${ANSIBLE}-playbook" \
	-e "working_dir=${WORKING_DIR}" \
	-e "metal3_dir=${SCRIPTDIR}" \
	-e "virthost=${HOSTNAME}" \
	-i vm-setup/inventory.ini \
	-b vm-setup/install-package-playbook.yml

step "Install cluster tools"
run_quiet_with_log_dump_on_failure "install-krew" install_krew
run_quiet_with_log_dump_on_failure "install-cluster-runtime" install_cluster_runtime
run_quiet_with_log_dump_on_failure "install-kubectl-and-tools" install_kubectl_and_tools

step "Image prepull"
run_quiet_with_log_dump_on_failure "prepull-images" prepull_images
