#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DIR}/lib/common.sh"

MACHINE_TYPE=$1
CONTROLPLANE_YAML=controlplane.yaml
WORKER_YAML=machinedeployment.yaml

if [ -z "$MACHINE_TYPE" ]; then
    echo "Usage: create_machine.sh <machine_type>"
    exit 1
fi

make_machine() {
    if [ "${MACHINE_TYPE}" == controlplane ]; then
        envsubst < "${V1ALPHA2_CR_PATH}${CONTROLPLANE_YAML}"
    fi
    if [ "${MACHINE_TYPE}" == worker ]; then
        envsubst < "${V1ALPHA2_CR_PATH}${WORKER_YAML}"
    fi
}

make_machine | kubectl delete -n metal3 -f -
