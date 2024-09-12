#!/usr/bin/env bash
# ignore shellcheck v0.9.0 introduced SC2317 about unreachable code
# that doesn't understand traps, variables, functions etc causing all
# code called via iterate() to false trigger SC2317
# shellcheck disable=SC2317

set -u

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh
# shellcheck disable=SC1091
source lib/network.sh
# shellcheck disable=SC1091
source lib/images.sh

if [ "${EPHEMERAL_CLUSTER}" == "tilt" ]; then
  exit 0
fi

check_bm_hosts() {
    local FAILS_CHECK="${FAILS}"
    local NAME ADDRESS USER PASSWORD MAC CRED_NAME CRED_SECRET
    local BARE_METAL_HOSTS BARE_METAL_HOST BARE_METAL_VMS BARE_METAL_VMNAME BARE_METAL_VM_IFACES
    NAME="${1}"
    ADDRESS="${2}"
    USER="${3}"
    PASSWORD="${4}"
    MAC="${5}"
    BARE_METAL_HOSTS="$(kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts\
      -n metal3 -o json)"
    BARE_METAL_VMS="$(sudo virsh list --all)"
    BARE_METAL_VMNAME="${NAME//-/_}"
    # Verify BM host exists
    RESULT_STR="${NAME} Baremetalhost exist"
    echo "${BARE_METAL_HOSTS}" | grep -w "${NAME}"  > /dev/null
    process_status $?

    BARE_METAL_HOST="$(echo "${BARE_METAL_HOSTS}" | \
      jq ' .items[] | select(.metadata.name=="'"${NAME}"'" )')"

    # Verify addresses of the host
    RESULT_STR="${NAME} Baremetalhost address correct"
    equals "$(echo "${BARE_METAL_HOST}" | jq -r '.spec.bmc.address')" "${ADDRESS}"

    RESULT_STR="${NAME} Baremetalhost mac address correct"
    equals "$(echo "${BARE_METAL_HOST}" | jq -r '.spec.bootMACAddress')" \
      "${MAC}"

    # Verify BM host status
    RESULT_STR="${NAME} Baremetalhost status OK"
    equals "$(echo "${BARE_METAL_HOST}" | jq -r '.status.operationalStatus')" \
      "OK"

    # Verify credentials exist
    RESULT_STR="${NAME} Baremetalhost credentials secret exist"
    CRED_NAME="$(echo "${BARE_METAL_HOST}" | jq -r '.spec.bmc.credentialsName')"
    CRED_SECRET="$(kubectl get secret "${CRED_NAME}" -n metal3 -o json | \
      jq '.data')"
    process_status $?

    # Verify credentials correct
    RESULT_STR="${NAME} Baremetalhost password correct"
    equals "$(echo "${CRED_SECRET}" | jq -r '.password' | \
      base64 --decode)" "${PASSWORD}"

    RESULT_STR="${NAME} Baremetalhost user correct"
    equals "$(echo "${CRED_SECRET}" | jq -r '.username' | \
      base64 --decode)" "${USER}"

    # Verify the VM was created
    RESULT_STR="${NAME} Baremetalhost VM exist"
    echo "${BARE_METAL_VMS} "| grep -w "${BARE_METAL_VMNAME}"  > /dev/null
    process_status $?

    #Verify the VMs interfaces
    BARE_METAL_VM_IFACES="$(sudo virsh domiflist "${BARE_METAL_VMNAME}")"
    for bridge in ${BRIDGES}; do
      RESULT_STR="${NAME} Baremetalhost VM interface ${bridge} exist"
      echo "${BARE_METAL_VM_IFACES}" | grep -w "${bridge}"  > /dev/null
      process_status $?
    done

    #Verify the introspection completed successfully
    RESULT_STR="${NAME} Baremetalhost introspecting completed"
    is_in "$(echo "${BARE_METAL_HOST}" | jq -r '.status.provisioning.state')" \
      "ready available"

    echo ""

    return "$((FAILS-FAILS_CHECK))"
}


# Verify that a resource exists in a type
check_k8s_entity() {
  local FAILS_CHECK="${FAILS}"
  local ENTITY
  local TYPE="${1}"
  shift
  for name in "${@}"; do
    # Check entity exists
    RESULT_STR="${TYPE} ${name} created"
    NS="$(echo "${name}" | cut -d ':' -f1)"
    NAME="$(echo "${name}" | cut -d ':' -f2)"
    ENTITY="$(kubectl --kubeconfig "${KUBECONFIG}" get "${TYPE}" "${NAME}" \
      -n "${NS}" -o json)"
    process_status $?

    # Check the replicabaremetalclusters
    if [[ "${BMO_RUN_LOCAL}" != true ]] && [[ "${CAPM3_RUN_LOCAL}" != true ]]
    then
      RESULT_STR="${name} ${TYPE} replicas correct"
      equals "$(echo "${ENTITY}" | jq -r '.status.readyReplicas')" \
        "$(echo "${ENTITY}" | jq -r '.status.replicas')"
    fi
  done

  return "$((FAILS-FAILS_CHECK))"
}


# Verify that a resource exists in a type
check_k8s_rs() {
  local FAILS_CHECK="${FAILS}"
  local ENTITY
  for name in "${@}"; do
    # Check entity exists
    LABEL="$(echo "$name" | cut -f1 -d:)"
    NAME="$(echo "$name" | cut -f2 -d:)"
    NS="$(echo "${name}" | cut -d ':' -f3)"
    NB="$(echo "${name}" | cut -d ':' -f4)"
    ENTITIES="$(kubectl --kubeconfig "${KUBECONFIG}" get replicasets \
      -l "${LABEL}"="${NAME}" -n "${NS}" -o json)"
    NB_ENTITIES="$(echo "$ENTITIES" | jq -r '.items | length')"
    RESULT_STR="Replica sets with label ${LABEL}=${NAME} created"
    equals "${NB_ENTITIES}" "${NB}"

    # Check the replicas
    if [[ "${BMO_RUN_LOCAL}" != true ]] && [[ "${CAPM3_RUN_LOCAL}" != true ]]
    then
      for i in $(seq 0 $((NB_ENTITIES-1))); do
        RESULT_STR="${NAME} replicas correct for replica set ${i}"
        equals "$(echo "${ENTITIES}" | jq -r ".items[${i}].status.readyReplicas")" \
          "$(echo "${ENTITIES}" | jq -r ".items[${i}].status.replicas")"
      done
    fi
  done

  return "$((FAILS-FAILS_CHECK))"
}


# Verify that a resource exists in a type
check_k8s_pods() {
  local FAILS_CHECK="${FAILS}"
  local ENTITY
  local NS="${2:-metal3}"
  for name in "${@}"; do
    # Check entity exists
    LABEL=$(echo "$name" | cut -f1 -d:);
    NAME=$(echo "$name" | cut -f2 -d:);

    ENTITY="$(kubectl --kubeconfig "${KUBECONFIG}" get pods \
      -l "${LABEL}"="${NAME}" -n "${NS}" -o json | jq '.items[0]')"
    RESULT_STR="Pod ${NAME} created"
    differs "${ENTITY}" "null"
  done

  return "$((FAILS-FAILS_CHECK))"
}

# Verify a container is running
check_container(){
  local NAME="$1"
  RESULT_STR="Container ${NAME} running"
  sudo "${CONTAINER_RUNTIME}" ps | grep -w "$NAME$" > /dev/null
  process_status $?
  return $?
}

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
EXPTD_V1ALPHAX_V1BETAX_CRDS="clusters.cluster.x-k8s.io \
  kubeadmconfigs.bootstrap.cluster.x-k8s.io \
  kubeadmconfigtemplates.bootstrap.cluster.x-k8s.io \
  machinedeployments.cluster.x-k8s.io \
  machines.cluster.x-k8s.io \
  machinesets.cluster.x-k8s.io \
  baremetalhosts.metal3.io"
EXPTD_DEPLOYMENTS="capm3-system:capm3-controller-manager \
  capi-system:capi-controller-manager \
  capi-kubeadm-bootstrap-system:capi-kubeadm-bootstrap-controller-manager \
  capi-kubeadm-control-plane-system:capi-kubeadm-control-plane-controller-manager \
  baremetal-operator-system:baremetal-operator-controller-manager"
EXPTD_RS="cluster.x-k8s.io/provider:infrastructure-metal3:capm3-system:2 \
  cluster.x-k8s.io/provider:cluster-api:capi-system:1 \
  cluster.x-k8s.io/provider:bootstrap-kubeadm:capi-kubeadm-bootstrap-system:1 \
  cluster.x-k8s.io/provider:control-plane-kubeadm:capi-kubeadm-control-plane-system:1"
BRIDGES="provisioning external"
EXPTD_CONTAINERS="httpd-infra registry vbmc sushy-tools"

FAILS=0
BMO_RUN_LOCAL="${BMO_RUN_LOCAL:-false}"
CAPM3_RUN_LOCAL="${CAPM3_RUN_LOCAL:-false}"


# Verify networking
for bridge in ${BRIDGES}; do
  RESULT_STR="Network ${bridge} exists"
  ip link show dev "${bridge}" > /dev/null
  process_status $? "Network ${bridge} exists"
done


# Verify Kubernetes cluster is reachable
RESULT_STR="Kubernetes cluster reachable"
kubectl version > /dev/null
process_status $?
echo ""

# Verify that the CRDs exist
RESULT_STR="Fetch CRDs"
CRDS="$(kubectl --kubeconfig "${KUBECONFIG}" get crds)"
process_status $? "Fetch CRDs"

LIST_OF_CRDS=("${EXPTD_V1ALPHAX_V1BETAX_CRDS}")

# shellcheck disable=SC2068
for name in ${LIST_OF_CRDS[@]}; do
  RESULT_STR="CRD ${name} created"
  echo "${CRDS}" | grep -w "${name}"  > /dev/null
  process_status $?
done
echo ""

# Verify v1beta1 Operators, Deployments, Replicasets
iterate check_k8s_entity deployments "${EXPTD_DEPLOYMENTS}"
iterate check_k8s_rs "${EXPTD_RS}"

# Verify the baremetal hosts
## Fetch the BM CRs
RESULT_STR="Fetch Baremetalhosts"
kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts -n metal3 -o json \
  > /dev/null
process_status $?

## Fetch the VMs
RESULT_STR="Fetch Baremetalhosts VMs"
sudo virsh list --all > /dev/null
process_status $?
echo ""

## Verify
if [[ -n "$(list_nodes)" ]]; then
  while read -r name address user password mac; do
    iterate check_bm_hosts "${name}" "${address}" "${user}" \
      "${password}" "${mac}"
    echo ""
  done <<< "$(list_nodes)"
fi

# Verify that the operator are running locally
if [[ "${BMO_RUN_LOCAL}" == true ]]; then
  RESULT_STR="Baremetal operator locally running"
  pgrep "operator-sdk" > /dev/null 2> /dev/null
  process_status $?
fi
if [[ "${CAPM3_RUN_LOCAL}" == true ]]; then
  # shellcheck disable=SC2034
  RESULT_STR="CAPI operator locally running"
  pgrep -f "go run ./main.go" > /dev/null 2> /dev/null
  process_status $?
fi
if [[ "${BMO_RUN_LOCAL}" == true ]] || [[ "${CAPM3_RUN_LOCAL}" == true ]]; then
  echo ""
fi

for container in ${EXPTD_CONTAINERS}; do
  iterate check_container "$container"
done


IRONIC_NODES_ENDPOINT="${IRONIC_URL}nodes"
status="$(curl -sk -o /dev/null -I -w "%{http_code}" "${IRONIC_NODES_ENDPOINT}")"
if [[ $status == 200 ]]; then
    echo "⚠️  ⚠️  ⚠️   WARNING: Ironic endpoint is exposed for unauthenticated users"
    exit 1
elif [[ $status == 401 ]]; then
    echo "OK - Ironic endpoint is secured"
else
    echo "FAIL- got $status from ${IRONIC_NODES_ENDPOINT}, expected 401"
    exit 1
fi
echo ""

echo -e "\nNumber of failures : $FAILS"
exit "${FAILS}"
