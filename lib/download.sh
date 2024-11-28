#!/usr/bin/env bash
#
# Utils to download and verify binary downloads in shell scripts
#
# This expects lib/common.sh to be sourced where the variables are defined

# set to true for testing without having to also change digests
INSECURE_SKIP_DOWNLOAD_VERIFICATION="${INSECURE_SKIP_DOWNLOAD_VERIFICATION:-false}"
SKIP_INSTALLATION="${SKIP_INSTALLATION:-false}"

# Pip can't take hashes on the command line, so we need to create
# temporary rqeuirements file with the hash and then clean it up
# NOTE: does not obey SKIP_INSTALLATION
pip_install_with_hash()
{
    local pkg_and_version="${1:?package==version missing}"
    local sha256="${2:?sha256 missing}"
    local tmpfile

    if [[ "${INSECURE_SKIP_DOWNLOAD_VERIFICATION}" == "true" ]]; then
        sudo python -m pip install "${pkg_and_version}"
    else
        tmpfile="$(mktemp)"
        echo "${pkg_and_version} --hash=sha256:${sha256}" > "${tmpfile}"
        sudo python -m pip install --require-hashes -r "${tmpfile}"
        rm -f "${tmpfile}"
    fi
}

# Download an url and verify the downloaded object has the same sha as
# supplied in the function call. If sha256 starts with https, it is downloaded
# and read as the sha256 sum, allowing us to verify binaries without hardcoding
# the pinning.
# Acceptable checksum formats: given as string param or as a download link,
# content can either be just the checksum, a pair or checksum & platform (in that order),
# or a list of checksum & platform pairs.
# If SKIP_INSTALLATION is not false, just prints out the sha and deletes the
# download.
wget_and_verify()
{
    local url="${1:?url missing}"
    local checksum="${2:?checksum missing}"
    local target="${3:?target missing}"
    local dlname="${url##*/}"
    local calculated

    declare -a args=(
        --no-verbose
        -O "${target}"
        "${url}"
    )

    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        args+=(--quiet)
    fi
    time wget "${args[@]}"

    if [[ "${checksum}" =~ https ]]; then
        checksum="$(curl -SsL "${checksum}")"
    fi

    if [[ "${checksum}" =~ ${dlname,,} ]]; then
        while read -r line; do
            if [[ "${line}" =~ ${dlname,,} ]]; then
                # It is assumed here that lines look like <checksum> <platform>
                checksum="${line%% *}"
                break
            fi
        done <<< "${checksum}"
    fi

    calculated="$(sha256sum "${target}" | awk '{print $1;}')"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        echo "info: sha256(${target/*\/}): ${calculated}"
        rm -f "${target?:}"

    elif [[ "${calculated}" != "${checksum}" ]]; then
        if [[ "${INSECURE_SKIP_DOWNLOAD_VERIFICATION}" == "true" ]]; then
            echo >&2 "warning: ${url} binary checksum '${calculated}' differs from expected checksum '${checksum}'"
        else
            echo >&2 "fatal: ${url} binary checksum '${calculated}' differs from expected checksum '${checksum}'"
            return 1
        fi
    fi

    return 0
}

download_and_install_krew()
{
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    KERNEL_OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')"
    KREW="krew-${KERNEL_OS}_${ARCH}"
    KREW_URL="https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/${KREW}.tar.gz"
    wget_and_verify "${KREW_URL}" "${KREW_SHA256}" "${tmp_dir}/${KREW}.tar.gz"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    pushd "${tmp_dir}" || return 1
    tar zxvf "${KREW}.tar.gz"
    rm -f "${KREW}.tar.gz"
    ./"${KREW}" install krew

    # Add krew to PATH by appending this line to .bashrc
    krew_path_bashrc="export PATH=${KREW_ROOT:-${HOME}/.krew}/bin:${PATH}"
    grep -qxF "${krew_path_bashrc}" ~/.bashrc || echo "${krew_path_bashrc}" >> ~/.bashrc
    popd || return 1
}

download_and_install_minikube()
{
    MINIKUBE_URL="https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
    MINIKUBE_SHA256="${MINIKUBE_SHA256:-https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64.sha256}"
    MINIKUBE_BINARY="minikube"

    wget_and_verify "${MINIKUBE_URL}" "${MINIKUBE_SHA256}" "${MINIKUBE_BINARY}"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    chmod +x "${MINIKUBE_BINARY}"
    sudo mv "${MINIKUBE_BINARY}" /usr/local/bin/
}

download_and_install_kvm2_driver()
{
    DRIVER_URL="https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/docker-machine-driver-kvm2"
    MINIKUBE_DRIVER_SHA256="${MINIKUBE_DRIVER_SHA256:-https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/docker-machine-driver-kvm2-amd64.sha256}"
    DRIVER_BINARY="docker-machine-driver-kvm2"

    wget_and_verify "${DRIVER_URL}" "${MINIKUBE_DRIVER_SHA256}" "${DRIVER_BINARY}"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    chmod +x "${DRIVER_BINARY}"
    sudo mv "${DRIVER_BINARY}" /usr/local/bin/
}

download_and_install_kind()
{
    KIND_URL="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-$(uname)-amd64"
    KIND_SHA256="${KIND_SHA256:-https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-$(uname)-amd64.sha256sum}"
    KIND_BINARY="kind"

    wget_and_verify "${KIND_URL}" "${KIND_SHA256}" "${KIND_BINARY}"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    chmod +x "${KIND_BINARY}"
    sudo mv "${KIND_BINARY}" /usr/local/bin/
}

download_and_install_tilt()
{
    TILT_URL="https://raw.githubusercontent.com/tilt-dev/tilt/${TILT_VERSION}/scripts/install.sh"
    TILT_SCRIPT="install.sh"

    wget_and_verify "${TILT_URL}" "${TILT_SHA256}" "${TILT_SCRIPT}"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    bash "${TILT_SCRIPT}"
    rm "${TILT_SCRIPT}"
}

# TODO: kubectl shouldd not be latest (same as k8s latest version), but
# use kubernetes version - 1, so the version skew from the latest to the
# old one used in upgrades is within +/- 1 version.
# Currently we default to KUBERNETES_BINARIES_VERSION, which defaults to
# KUBERNETES_VERSION
download_and_install_kubectl()
{
    KUBECTL_PATH=$(whereis -b kubectl | cut -d ":" -f2 | awk '{print $1}')
    KUBECTL_PATH="${KUBECTL_PATH:-/usr/local/bin/kubectl}"
    KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    KUBECTL_SHA256_URL="${KUBECTL_URL}.sha256"

    wget_and_verify "${KUBECTL_URL}" "${KUBECTL_SHA256_URL}" "kubectl"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    chmod +x kubectl
    sudo mv kubectl "${KUBECTL_PATH}"
}

download_and_install_kustomize()
{
    KUSTOMIZE_URL="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
    KUSTOMIZE_SHA256="${KUSTOMIZE_SHA256:-https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/checksums.txt}"
    KUSTOMIZE_BINARY="kustomize"

    wget_and_verify "${KUSTOMIZE_URL}" "${KUSTOMIZE_SHA256}" "${KUSTOMIZE_BINARY}.tar.gz"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    tar -xzvf "${KUSTOMIZE_BINARY}.tar.gz"
    rm "${KUSTOMIZE_BINARY}.tar.gz"
    chmod +x "${KUSTOMIZE_BINARY}"
    sudo mv "${KUSTOMIZE_BINARY}" /usr/local/bin/
}

# TODO: Currently we just download latest CAPIRELEASE version of clusterctl,
# which means we don't know the expected SHA, and can't pin it. This function
# is not used, but it is marked as TODO in 03 script as well.
download_and_install_clusterctl()
{
    CLUSTERCTL_URL="https://github.com/kubernetes-sigs/cluster-api/releases/download/${CAPIRELEASE}/clusterctl-linux-amd64"
    CLUSTERCTL_BINARY="clusterctl"

    wget_and_verify "${CLUSTERCTL_URL}" "${CLUSTERCTL_SHA256}" "${CLUSTERCTL_BINARY}"
    if [[ "${SKIP_INSTALLATION}" != "false" ]]; then
        return 0
    fi

    chmod +x "${CLUSTERCTL_BINARY}"
    sudo mv "${CLUSTERCTL_BINARY}" /usr/local/bin/
}

# Run this helper function called by hack/print_checksums.sh
# 1. update the versions in lib/common.sh
# 2. run ./hack/print_checksums.sh
# 3. update shas in lib/common.sh
_download_and_print_checksums()
{
    # shellcheck disable=SC2034
    SKIP_INSTALLATION=true

    # download_and_install_clusterctl
    download_and_install_kind
    download_and_install_krew
    download_and_install_kubectl
    download_and_install_kustomize
    download_and_install_kvm2_driver
    download_and_install_minikube
    download_and_install_tilt
}
