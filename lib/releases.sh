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
    release_tag=$(curl -s "${proxuUrl}" | sort -rV | grep -m1 "^${release}")
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
  CAPM3_RELEASE_PREFIX="${CAPM3RELEASEBRANCH#release-}"
else
  CAPM3_RELEASE_PREFIX=""
fi

# Fetch CAPI version that coresponds to CAPM3_RELEASE_PREFIX release version
if [[ "${CAPM3_RELEASE_PREFIX}" =~ ^(1\.6|1\.7|1\.8|1\.9)$ ]]; then
  export CAPM3RELEASE="v${CAPM3_RELEASE_PREFIX}.99"
  CAPI_RELEASE_PREFIX="v${CAPM3_RELEASE_PREFIX}."
else
  export CAPM3RELEASE="v1.10.99"
  CAPI_RELEASE_PREFIX="v1.9."
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
