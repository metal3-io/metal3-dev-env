#!/usr/bin/env bash

set -u

# Redirect to stdout for logging
# Workaround to avoid returning logs in functions
exec 3>&1

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh


check_bm_hosts() {
    local FAILS_CHECK="${FAILS}"
    local NAME ADDRESS USER PASSWORD MAC CRED_NAME CRED_SECRET\
      BM_HOSTS BM_HOST BM_VMS BM_VMNAME BM_VM_IFACES
    NAME="${1}"
    ADDRESS="${2}"
    USER="${3}"
    PASSWORD="${4}"
    MAC="${5}"
    BM_HOSTS="$(kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts\
      -n metal3 -o json)"
    BM_VMS="$(virsh list --all)"
    BM_VMNAME="${NAME//-/_}"
    # Verify BM host exists
    echo "$BM_HOSTS" | grep -w "${NAME}"  > /dev/null
    FAILS="$(process_status $? "${NAME} Baremetalhost exist")"

    BM_HOST="$(echo "${BM_HOSTS}" | \
      jq ' .items[] | select(.metadata.name=="'"${NAME}"'" )')"

    # Verify addresses of the host
    FAILS="$(equals "$(echo "${BM_HOST}" | jq -r '.spec.bmc.address')" \
      "${ADDRESS}" "${NAME} Baremetalhost address correct")"

    FAILS="$(equals "$(echo "${BM_HOST}" | jq -r '.spec.bootMACAddress')" \
      "${MAC}" "${NAME} Baremetalhost mac address correct")"

    # Verify BM host status
    FAILS="$(equals "$(echo "${BM_HOST}" | jq -r '.status.operationalStatus')" \
      "OK" "${NAME} Baremetalhost status OK")"

    # Verify credentials exist
    CRED_NAME="$(echo "${BM_HOST}" | jq -r '.spec.bmc.credentialsName')"
    CRED_SECRET="$(kubectl get secret "${CRED_NAME}" -n metal3 -o json | \
      jq '.data')"
    FAILS="$(process_status $? \
      "${NAME} Baremetalhost credentials secret exist")"

    # Verify credentials correct
    FAILS="$(equals "$(echo "${CRED_SECRET}" | jq -r '.password' | \
      base64 --decode)" \
      "${PASSWORD}" "${NAME} Baremetalhost password correct")"

    FAILS="$(equals "$(echo "${CRED_SECRET}" | jq -r '.username' | \
      base64 --decode)" \
      "${USER}" "${NAME} Baremetalhost user correct")"

    # Verify the VM was created
    echo "$BM_VMS "| grep -w "${BM_VMNAME}"  > /dev/null
    FAILS="$(process_status $? "${NAME} Baremetalhost VM exist")"

    #Verify the VMs interfaces
    BM_VM_IFACES="$(virsh domiflist "${BM_VMNAME}")"
    for bridge in ${BRIDGES}; do
      echo "$BM_VM_IFACES" | grep -w "${bridge}"  > /dev/null
      FAILS="$(process_status $? \
        "${NAME} Baremetalhost VM interface ${bridge} exist")"
    done

    #Verify the instrospection completed successfully
    FAILS="$(equals "$(echo "${BM_HOST}" | jq -r '.status.provisioning.state')" \
      "ready" "${NAME} Baremetalhost introspecting completed")"
    echo "" >&3
    echo "${FAILS}"
    if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
      return 1
    fi
    return 0
}


#Verify that a resource exists in a type
check_k8s_entity() {
  local FAILS_CHECK="${FAILS}"
  local ENTITY
  for name in ${2}; do
    # Check entity exists
    ENTITY="$(kubectl --kubeconfig "${KUBECONFIG}" get "${1}" "${name}" \
      -n metal3 -o json)"
    FAILS="$(process_status $? "${1} ${name} created")"

    # Check the replicas
    if [[ "${BMO_RUN_LOCAL}" != true ]] && [[ "${CAPBM_RUN_LOCAL}" != true ]]
    then
      FAILS="$(equals "$(echo "${ENTITY}" | jq -r '.status.readyReplicas')" \
        "$(echo "${ENTITY}" | jq -r '.status.replicas')" \
        "${name} ${1} replicas correct")"
    fi
  done
  echo "" >&3
  echo "${FAILS}"
  if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
    return 1
  fi
  return 0
}


#Verify that a resource exists in a type
check_k8s_rs() {
  local FAILS_CHECK="${FAILS}"
  local ENTITY
  for name in ${1}; do
    # Check entity exists
    ENTITY="$(kubectl --kubeconfig "${KUBECONFIG}" get replicasets \
      -l name="${name}" -n metal3 -o json | jq '.items[0]')"
    FAILS="$(differs "${ENTITY}" "null" "Replica set ${name} created")"

    # Check the replicas
    if [[ "${BMO_RUN_LOCAL}" != true ]] && [[ "${CAPBM_RUN_LOCAL}" != true ]]
    then
      FAILS="$(equals "$(echo "${ENTITY}" | jq -r '.status.readyReplicas')" \
        "$(echo "${ENTITY}" | jq -r '.status.replicas')" \
        "${name} replicas correct")"
    fi
  done
  echo "" >&3
  echo "${FAILS}"
  if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
    return 1
  fi
  return 0
}

#Verify a container is running
check_container(){
  local NAME="$1"
  sudo "${CONTAINER_RUNTIME}" ps | grep -w "$NAME$" > /dev/null
  process_status $? "Container ${NAME} running"
  return $?
}

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
EXPTD_CRDS="baremetalhosts.metal3.io \
  clusters.cluster.k8s.io \
  machineclasses.cluster.k8s.io \
  machinedeployments.cluster.k8s.io \
  machines.cluster.k8s.io \
  machinesets.cluster.k8s.io"
EXPTD_STATEFULSETS="cluster-api-controller-manager \
  cluster-api-provider-baremetal-controller-manager"
EXPTD_DEPLOYMENTS="metal3-baremetal-operator"
BRIDGES="provisioning baremetal"

FAILS=0
BMO_RUN_LOCAL="${BMO_RUN_LOCAL:-false}"
CAPBM_RUN_LOCAL="${CAPBM_RUN_LOCAL:-false}"


# Verify networking
for bridge in ${BRIDGES}; do
  ip link show dev "${bridge}" > /dev/null
  FAILS=$(process_status $? "Network ${bridge} exists")
done


#Verify Kubernetes cluster is reachable
kubectl version > /dev/null
FAILS=$(process_status $? "Kubernetes cluster reachable")
echo "" >&3

# Verify that the CRDs exist
CRDS="$(kubectl --kubeconfig "${KUBECONFIG}" get crds)"
FAILS=$(process_status $? "Fetch CRDs")

for name in ${EXPTD_CRDS}; do
  echo "${CRDS}" | grep -w "${name}"  > /dev/null
  FAILS=$(process_status $? "CRD ${name} created")
done
echo "" >&3


# Verify the Operators, stateful sets
FAILS=$(iterate check_k8s_entity statefulsets "${EXPTD_STATEFULSETS}")

# Verify the Operators, Deployments
FAILS=$(iterate check_k8s_entity deployments "${EXPTD_DEPLOYMENTS}")

# Verify the Operators, Replica sets
FAILS=$(iterate check_k8s_rs "${EXPTD_DEPLOYMENTS}")

# Verify the baremetal hosts
## Fetch the BM CRs
kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts -n metal3 -o json \
  > /dev/null
FAILS=$(process_status $? "Fetch Baremetalhosts")
## Fetch the VMs
virsh list --all > /dev/null
FAILS=$(process_status $? "Fetch Baremetalhosts VMs")
## Verify
while read -r name address user password mac; do
  FAILS="$(iterate check_bm_hosts "${name}" "${address}" "${user}" \
    "${password}" "${mac}")"
done <<< "$(list_nodes)"

if [[ "${BMO_RUN_LOCAL}" == true ]]; then
  pgrep "operator-sdk" > /dev/null 2> /dev/null
  FAILS=$(process_status $? "Baremetal operator locally running")
fi
if [[ "${CAPBM_RUN_LOCAL}" == true ]]; then
  pgrep -f "go run ./cmd/manager/main.go" > /dev/null 2> /dev/null
  FAILS=$(process_status $? "CAPI operator locally running")
fi

#Verify Ironic containers are running
for name in ironic ironic-inspector dnsmasq httpd mariadb; do
  FAILS="$(iterate check_container "${name}")"
done
echo "" >&3


echo -e "\nNumber of failures : $FAILS" >&3
exit "${FAILS}"
