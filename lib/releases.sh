#!/bin/bash

# Check if a GitHub release asset exists for a given version
# Returns 0 if the release exists, 1 otherwise
# Example usage:
# check_github_release_exists "v1.12.1"
check_github_release_exists() {
  local version="${1:?version is required}"
  local url="https://github.com/kubernetes-sigs/cluster-api/releases/download/${version}/clusterctl-linux-amd64"

  # Use curl with HEAD request to check if the asset exists (follows redirects)
  curl --head --silent --fail --location "${url}" > /dev/null 2>&1
}

# Get the latest release from goproxy that has a valid GitHub release
# This iterates through versions until it finds one with available binaries
# Example usage:
# get_validated_release_from_goproxy "https://proxy.golang.org/sigs.k8s.io/cluster-api/@v/list" "v1.12." "beta|rc|pre|alpha"
get_validated_release_from_goproxy() {
  local proxyUrl="${1:?no release path is given}"
  local release="${2:?no release given}"
  local exclude="${3:-}"
  local versions

  # Get sorted list of versions from goproxy
  if [[ -z "${exclude}" ]]; then
    versions=$(curl -s "${proxyUrl}" | sed '/-/!{s/$/_/}' | sort -rV | sed 's/_$//' | grep "^${release}")
  else
    versions=$(curl -s "${proxyUrl}" | sort -rV | grep -vE "${exclude}" | grep "${release}")
  fi

  # Iterate through versions and return the first one with a valid GitHub release
  while IFS= read -r version; do
    if [[ -n "${version}" ]] && check_github_release_exists "${version}"; then
      echo "${version}"
      return 0
    fi
    echo "info: GitHub release not found for ${version}, trying next version..." >&2
  done <<< "${versions}"

  echo "Error: no valid GitHub release found for ${release}* from ${proxyUrl}" >&2
  return 1
}

# Requires parameters url and version. An optional parameter can be given to
# exclude some versions.
# Example usage:
# get_latest_release_from_goproxy "https://proxy.golang.org/sigs.k8s.io/cluster-api/@v/list" "v1.8." "beta|rc|pre|alpha"
get_latest_release_from_goproxy() {
  local proxuUrl="${1:?no release path is given}"
  local release="${2:?no release given}"
  local exclude="${3:-}"

  # This gets the latest release
  if [[ -z "${exclude}" ]]; then
    # Using whats suggested here https://stackoverflow.com/questions/40390957/how-to-sort-semantic-versions-in-bash
    # Add _ in front of all stable releases, so they are sorted before the pre-releases
    # Sort the list in reverse order, so the latest version is first
    # Remove the _ at the end of the version
    # Get the first version that matches the release
    release_tag=$(curl -s "${proxuUrl}" | sed '/-/!{s/$/_/}' | sort -rV | sed 's/_$//'| grep -m1 "^${release}")
  else
    # prune based on exluded values given in the command
    release_tag=$(curl -s "${proxuUrl}" | sort -rV | grep -vE "${exclude}" | grep -m1 "${release}")
  fi

  # if release_tag is not found
  if [[ -z "${release_tag}" ]]; then
    echo "Error: release is not found from ${proxuUrl}" >&2
    exit 1
  fi
  echo "${release_tag}"
}

CAPIGOPROXY="https://proxy.golang.org/sigs.k8s.io/cluster-api/@v/list"

# Extract release version from release-branch name
if [[ "${CAPM3RELEASEBRANCH}" == release-* ]]; then
  RELEASE_PREFIX="${CAPM3RELEASEBRANCH#release-}"
else
  RELEASE_PREFIX=""
fi

if [[ "${CAPI_NIGHTLY_BUILD:-}" = "true" ]]; then
  if [[  -n "${RELEASE_PREFIX}" ]]; then
    export CAPIRELEASE="v${RELEASE_PREFIX}.99"
  else
    export CAPIRELEASE="${CAPIRELEASE:-"v1.12.99"}"
  fi
fi

# Fetch CAPI version that coresponds to CAPM3_RELEASE_PREFIX release version
if [[ -n "${RELEASE_PREFIX}" ]]; then
  export CAPM3RELEASE="v${RELEASE_PREFIX}.99"
  export IPAMRELEASE="v${RELEASE_PREFIX}.99"
  CAPI_RELEASE_PREFIX="v${RELEASE_PREFIX}."
else
  export CAPM3RELEASE="${CAPM3RELEASE:-"v1.13.99"}"
  export IPAMRELEASE="${IPAMRELEASE:-"v1.13.99"}"
  CAPI_RELEASE_PREFIX="${CAPI_RELEASE_PREFIX:-"v1.12."}"
fi
export CAPIRELEASE="${CAPIRELEASE:-$(get_validated_release_from_goproxy "${CAPIGOPROXY}" "${CAPI_RELEASE_PREFIX}")}"
CAPIBRANCH="${CAPIBRANCH:-${CAPIRELEASE}}"

if [[ -z "${CAPIRELEASE}" ]]; then
  echo "Failed to fetch CAPI release from GOPROXY"
  exit 1
fi

if [[ -z "${CAPM3RELEASE}" ]]; then
  echo "Failed to fetch CAPM3 release from GOPROXY"
  exit 1
fi

if [[ -z "${IPAMRELEASE}" ]]; then
  echo "Failed to fetch IPAM release from GOPROXY"
  exit 1
fi
