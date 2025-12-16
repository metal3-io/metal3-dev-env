#!/bin/bash

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
export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release_from_goproxy "${CAPIGOPROXY}" "${CAPI_RELEASE_PREFIX}")}"
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
