#!/bin/bash

function get_latest_release() {
  set +x
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    release="$(curl -sL "${1}")" || ( set -x && exit 1 )
  else
    release="$(curl -H "Authorization: token ${GITHUB_TOKEN}" -sL "${1}")" || ( set -x && exit 1 )
  fi
  # This gets the latest release as vx.y.z , ignoring any version with a suffix starting with - , for example -rc0
  release_tags_unsorted="$(echo "$release" | jq -r "[.[].tag_name | select( startswith(\"${2:-""}\")) | select(contains(\"-\")==false)]" \
    | cut -sf2 -d\"  | tr '.' ' ' )"
  if [[ $OS == ubuntu ]]; then
    release_tags_sorted="$(echo "$release_tags_unsorted" | sort -n +1 +2 )"
  else
    release_tags_sorted="$(echo "$release_tags_unsorted" | sort -nk1 -nk2 -nk3 )"
  fi
  release_tag="$(echo "$release_tags_sorted" | tail -n 1 | tr ' ' '.')"

  if [[ "$release_tag" == "null" ]]; then
    set -x
    exit 1
  fi
  set -x
  # shellcheck disable=SC2005
  echo "$release_tag"
}

# CAPM3 and CAPI releases
CAPM3RELEASEPATH="${CAPM3RELEASEPATH:-https://api.github.com/repos/${CAPM3_BASE_URL:-metal3-io/cluster-api-provider-metal3}/releases}"
CAPIRELEASEPATH="${CAPIRELEASEPATH:-https://api.github.com/repos/${CAPI_BASE_URL:-kubernetes-sigs/cluster-api}/releases}"

if [ "${CAPM3_VERSION}" == "v1alpha4" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v0.4.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v0.3.")}"
  CAPIBRANCH="${CAPIBRANCH:-${CAPIRELEASE}}"
else
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v0.3.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v0.3.")}"
  CAPIBRANCH="${CAPIBRANCH:-${CAPIRELEASE}}"
fi

# On first iteration, jq might not be installed
if [[ "$CAPIRELEASE" == "" ]]; then
  command -v jq &> /dev/null && echo "Failed to fetch CAPI release from Github" && exit 1
fi

if [[ "$CAPM3RELEASE" == "" ]]; then
  command -v jq &> /dev/null && echo "Failed to fetch CAPM3 release from Github" && exit 1
fi