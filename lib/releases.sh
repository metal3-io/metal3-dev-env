#!/bin/bash

function get_latest_release() {
  # get last page
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    last_page="$(curl -s -I "${1}" | grep '^link:' | sed -e 's/^link:.*page=//g' -e 's/>.*$//g')"
  else
    last_page="$(curl -s -I "${1}" -H "Authorization: token $GITHUB_TOKEN" | grep '^link:' | sed -e 's/^link:.*page=//g' -e 's/>.*$//g')"
  fi
  # default last page to 1
  last_page="${last_page:-1}"

  set +x

  for current_page in $(seq 1 "$last_page"); do

    url="${1}?page=${current_page}"

    if [ -z "${GITHUB_TOKEN:-}" ]; then
      release="$(curl -sL "${url}")" || { set -x && exit 1; }
    else
      release="$(curl -H "Authorization: token ${GITHUB_TOKEN}" -sL "${url}")" || { set -x && exit 1; }
    fi

    # This gets the latest release as vx.y.z or vx.y.z-rc.0, including any version with a suffix starting with - , for example -rc.0
    # The order is exactly as released in Github.
    # Downside is that selecting official releases only isn't possible, while pre-release
    # selection is possible given specific enough prefix, like v1.3.0-pre
    release_tag="$(echo "${release}" | jq -r "[.[].tag_name | select( startswith(\"${2:-}\"))] | .[0]")"
    # if release tag found
    if [[ "${release_tag}" != "null" ]]; then
      break
    fi

  done

  set -x
  # if not found
  if [[ "${release_tag}" == "null" ]]; then
    exit 1
  fi
  # shellcheck disable=SC2005
  echo "${release_tag}"
}

# CAPM3, CAPI and BMO release path
CAPM3RELEASEPATH="{https://api.github.com/repos/${CAPM3_BASE_URL:-metal3-io/cluster-api-provider-metal3}/releases}"
CAPIRELEASEPATH="{https://api.github.com/repos/${CAPI_BASE_URL:-kubernetes-sigs/cluster-api}/releases}"

# CAPM3, CAPI and BMO releases
if [ "${CAPM3RELEASEBRANCH}" == "release-1.1" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.1.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.1.")}"
elif [ "${CAPM3RELEASEBRANCH}" == "release-1.2" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.2.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.2.")}"
elif [ "${CAPM3RELEASEBRANCH}" = "release-1.3" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.3.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.3.")}"
elif [ "${CAPM3RELEASEBRANCH}" = "release-1.4" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.4.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.4.")}"
else
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.4.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.4.")}"
fi

CAPIBRANCH="${CAPIBRANCH:-${CAPIRELEASE}}"

# On first iteration, jq might not be installed
if [[ "$CAPIRELEASE" == "" ]]; then
  command -v jq &>/dev/null && echo "Failed to fetch CAPI release from Github" && exit 1
fi

if [[ "$CAPM3RELEASE" == "" ]]; then
  command -v jq &>/dev/null && echo "Failed to fetch CAPM3 release from Github" && exit 1
fi