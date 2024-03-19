#!/bin/bash

function get_latest_release() {

  # fail when release_path is not passed
  local release_path="${1:?no release path is given}"

  # set url to get 100 releases from first page
  local url="${release_path}?per_page=100&page=1"

  # fail when release is not passed
  local release="${2:?no release given}"

  set +x

  if  [ -z "${GITHUB_TOKEN:-}" ]; then
    response=$(curl -si "${url}")
  else
    response=$(curl -si "${url}" -H "Authorization: token ${GITHUB_TOKEN}")
  fi

  # Divide response to headers and body
  response_headers=$(echo "${response}" | awk 'BEGIN {RS="\r\n\r\n"} NR==1 {print}')
  if ! echo "${response_headers}" | grep -q 'Connection established'; then
    response_body=$(echo "${response}" | awk 'BEGIN {RS="\r\n\r\n"} NR==2 {print}')
  else
    response_headers=$(echo "${response}" | awk 'BEGIN {RS="\r\n\r\n"} NR==2 {print}')
    response_body=$(echo "${response}" | awk 'BEGIN {RS="\r\n\r\n"} NR==3 {print}')
  fi

  # get the last page of releases from headers
  last_page=$(echo "${response_headers}" | grep '^link:' | sed -e 's/^link:.*page=//g' -e 's/>.*$//g')

  # This gets the latest release as vx.y.z or vx.y.z-rc.0, including any version with a suffix starting with - , for example -rc.0
  # The order is exactly as released in Github.
  # Downside is that selecting official releases only isn't possible, while pre-release
  # selection is possible given specific enough prefix, like v1.3.0-pre
  release_tag=$(echo "${response_body}" | jq ".[].name" -r | grep -E "${release}" -m 1)

  # If release_tag is not found in the first page(100 releases), this condition checks from second to last_page
  # until release_tag is found
  if [ -z "${release_tag}" ]; then
    for current_page in $(seq 2 "${last_page}"); do
        url="${release_path}?per_page=100&page=${current_page}"
            if [ -z "${GITHUB_TOKEN:-}" ]; then
                release_tag=$(curl -sL "${url}" | jq ".[].name" -r | grep -E "${release}" -m 1)
            else
                release_tag=$(curl -sL "${url}" -H "Authorization: token ${GITHUB_TOKEN}" | jq ".[].name" -r | grep -E "${release}" -m 1)
            fi
            # if release_tag found break the loop
            if [ -n "${release_tag}" ]; then
                break
            fi
    done
  fi

  set -x

  # if release_tag is not found
  if [ -z "${release_tag}" ]; then
    echo "Error: release is not found from ${release_path}"
    exit 1
  else
    echo "${release_tag}"
  fi
}

# CAPM3, CAPI and BMO release path
CAPM3RELEASEPATH="{https://api.github.com/repos/${CAPM3_BASE_URL:-metal3-io/cluster-api-provider-metal3}/releases}"
CAPIRELEASEPATH="{https://api.github.com/repos/${CAPI_BASE_URL:-kubernetes-sigs/cluster-api}/releases}"

# CAPM3, CAPI and BMO releases
if [ "${CAPM3RELEASEBRANCH}" = "release-1.4" ]; then
  export CAPM3RELEASE="${CAPM3RELEASE:-$(get_latest_release "${CAPM3RELEASEPATH}" "v1.4.")}"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.4.")}"
elif [ "${CAPM3RELEASEBRANCH}" = "release-1.5" ]; then
  # 1.5.99 points to the head of the release-1.5 branch. Local override for CAPM3 is created for this version.
  export CAPM3RELEASE="v1.5.99"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.5.")}"
elif [ "${CAPM3RELEASEBRANCH}" = "release-1.6" ]; then
  # 1.6.99 points to the head of the release-1.6 branch. Local override for CAPM3 is created for this version.
  export CAPM3RELEASE="v1.6.99"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.6.")}"
else
  # 1.7.99 points to the head of the main branch as well. Local override for CAPM3 is created for this version.
  export CAPM3RELEASE="v1.7.99"
  export CAPIRELEASE="${CAPIRELEASE:-$(get_latest_release "${CAPIRELEASEPATH}" "v1.7.")}"
fi

CAPIBRANCH="${CAPIBRANCH:-${CAPIRELEASE}}"

# On first iteration, jq might not be installed
if [[ "$CAPIRELEASE" == "" ]]; then
  command -v jq &>/dev/null && echo "Failed to fetch CAPI release from Github" && exit 1
fi

if [[ "$CAPM3RELEASE" == "" ]]; then
  command -v jq &>/dev/null && echo "Failed to fetch CAPM3 release from Github" && exit 1
fi

# Set CAPI_CONFIG_FOLDER variable according to CAPIRELEASE minor version
  # Starting from CAPI v1.5.0 version cluster-api config folder location has changed
  # to XDG_CONFIG_HOME folder.
  # Following code defines the cluster-api config folder location according to CAPI
  # release version

# TODO(Sunnatillo): Following condition should be removed when CAPM3 v1.4 reaches EOL
# NOTE(Sunnatillo): When CAPM3 v1.4 reaches EOL CAPI_CONFIG_FOLDER variable can be removed
# for the sake of reducing variables

version_string="${CAPIRELEASE#v}"
IFS='.' read -r _ minor _ <<< "$version_string"

if [ "$minor" -lt 5 ]; then
  export CAPI_CONFIG_FOLDER="${HOME}/.cluster-api"
else
  # Default CAPI_CONFIG_FOLDER to $HOME/.config folder if XDG_CONFIG_HOME not set
  CONFIG_FOLDER="${XDG_CONFIG_HOME:-$HOME/.config}"
  export CAPI_CONFIG_FOLDER="${CONFIG_FOLDER}/cluster-api"
fi
