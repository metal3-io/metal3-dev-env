#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../../.."

# shellcheck disable=SC1091
# shellcheck disable=SC1090
# shellcheck disable=SC2046
source "${METAL3_DIR}/scripts/feature_tests/feature_test_vars.sh"

export ACTION="node_reuse"
export FROM_K8S_VERSION="v1.21.2"
export KUBERNETES_VERSION=${FROM_K8S_VERSION}
export UPGRADED_K8S_VERSION="v1.21.3"

"${METAL3_DIR}"/scripts/run.sh
