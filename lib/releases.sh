#!/bin/bash

function get_latest_release() {
  set +x
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    release="$(curl -sL "${1}")" || ( set -x && exit 1 )
  else
    release="$(curl -H "Authorization: token ${GITHUB_TOKEN}" -sL "${1}")" || ( set -x && exit 1 )
  fi
  # This gets the latest release as vx.y.z or vx.y.z-rc.0, including any version with a suffix starting with - , for example -rc.0
  # The order is exactly as released in Github.
  # Downside is that selecting official releases only isn't possible, while pre-release
  # selection is possible given specific enough prefix, like v1.3.0-pre
  release_tag="$(echo "$release" | jq -r "[.[].tag_name | select( startswith(\"${2:-}\"))] | .[0]")"

  if [[ "$release_tag" == "null" ]]; then
    set -x
    exit 1
  fi
  set -x
  # shellcheck disable=SC2005
  echo "$release_tag"
}

# CAPM3, CAPI and BMO release path
CAPM3RELEASEPATH="{https://api.github.com/repos/${CAPM3_BASE_URL:-metal3-io/cluster-api-provider-metal3}/releases}"
CAPIRELEASEPATH="{https://api.github.com/repos/${CAPI_BASE_URL:-kubernetes-sigs/cluster-api}/releases?per_page=100}"
BMORELEASEPATH="{https://api.github.com/repos/${BMO_BASE_URL:-metal3-io/baremetal-operator}/releases}"

# CAPM3, CAPI and BMO releases
if [ "${CAPM3RELEASEBRANCH}" == "release-0.5" ] || [ "${CAPM3_VERSION}" == "v1alpha5" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v0.5.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v0.4.")}"
elif [ "${CAPM3RELEASEBRANCH}" == "release-1.1" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.1.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.1.")}"
elif [ "${CAPM3RELEASEBRANCH}" == "release-1.2" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.2.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.2.")}"
else
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.3.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.3.")}"
fi

export BMORELEASE="${BMORELEASE:-$(get_latest_release "${BMORELEASEPATH}" "v0.2.")}"

CAPIBRANCH="${CAPIBRANCH:-${CAPIRELEASE}}"
BMOBRANCH="${BMOBRANCH:-${BMORELEASE}}"

# On first iteration, jq might not be installed
if [[ "$CAPIRELEASE" == "" ]]; then
  command -v jq &> /dev/null && echo "Failed to fetch CAPI release from Github" && exit 1
fi

if [[ "$CAPM3RELEASE" == "" ]]; then
  command -v jq &> /dev/null && echo "Failed to fetch CAPM3 release from Github" && exit 1
fi

if [[ "$BMORELEASE" == "" ]]; then
  command -v jq &> /dev/null && echo "Failed to fetch BMO release from Github" && exit 1
fi
