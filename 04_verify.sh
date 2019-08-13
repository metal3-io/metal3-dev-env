#!/usr/bin/env bash

set -u

# Redirect to stdout for logging
# Workaround to avoid returning logs in functions
exec 3>&1

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh


# Check the return code and log
process_status(){
  if [[ "${1}" == 0 ]]; then
    echo "OK - ${2}" >&3
    echo "${FAILS}"
  else
    echo "FAIL - ${2}" >&3
    echo "$((FAILS+1))"
  fi
}


# Compare the two inputs and log
equals(){
  if [[ "${1}" == "${2}" ]]; then
    echo "OK - ${3}" >&3
    echo "${FAILS}"
  else
    echo "FAIL - ${3}" >&3
    echo "$((FAILS+1))"
  fi
}


# Compare the two inputs and log
differs(){
  if [[ "${1}" != "${2}" ]]; then
    echo "OK - ${3}" >&3
    echo "${FAILS}"
  else
    echo "FAIL - ${3}" >&3
    echo "$((FAILS+1))"
  fi
}


check_bm_hosts() {
    while read -r name address user password mac; do
      BM_VMNAME="${name//-/_}"
      # Verify BM host exists
      echo "$BM_HOSTS" | grep -w "${name}"  > /dev/null
      FAILS="$(process_status $? "${name} Baremetalhost exist")"

      BM_HOST="$(echo "${BM_HOSTS}" | jq ' .items[] | select(.metadata.name=="'"${name}"'" )')"

      # Verify addresses of the host
      FAILS="$(equals "$(echo "${BM_HOST}" | jq -r '.spec.bmc.address')" \
        "${address}" "${name} Baremetalhost address correct")"

      FAILS="$(equals "$(echo "${BM_HOST}" | jq -r '.spec.bootMACAddress')" \
        "${mac}" "${name} Baremetalhost mac address correct")"

      # Verify BM host status
      FAILS="$(equals "$(echo "${BM_HOST}" | jq -r '.status.operationalStatus')" \
        "OK" "${name} Baremetalhost status OK")"

      # Verify credentials exist
      CRED_NAME="$(echo "${BM_HOST}" | jq -r '.spec.bmc.credentialsName')"
      CRED_SECRET="$(kubectl get secret "${CRED_NAME}" -n metal3 -o json | jq '.data')"
      FAILS="$(process_status $? \
        "${name} Baremetalhost credentials secret exist")"

      # Verify credentials correct
      FAILS="$(equals "$(echo "${CRED_SECRET}" | jq -r '.password' | base64 --decode)" \
        "${password}" "${name} Baremetalhost password correct")"

      FAILS="$(equals "$(echo "${CRED_SECRET}" | jq -r '.username' | base64 --decode)" \
        "${user}" "${name} Baremetalhost user correct")"

      # Verify the VM was created
      echo "$BM_VMS "| grep -w "${BM_VMNAME}"  > /dev/null
      FAILS="$(process_status $? "${name} Baremetalhost VM exist")"

      BM_VM_IFACES="$(virsh domiflist "${BM_VMNAME}")"
      for bridge in ${BRIDGES}; do
        echo "$BM_VM_IFACES" | grep -w "${bridge}"  > /dev/null
        FAILS="$(process_status $? \
          "${name} Baremetalhost VM interface ${bridge} exist")"
      done
      echo "" >&3
    done
    echo "${FAILS}"
}


#Verify that a resource exists in a type
check_k8s_entity() {
  for name in ${2}; do
    # Check entity exists
    ENTITY="$(kubectl --kubeconfig "${KUBECONFIG}" get "${1}" "${name}" -n metal3 -o json)"
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
}


#Verify that a resource exists in a type
check_k8s_rs() {
  for name in ${1}; do
    # Check entity exists
    ENTITY="$(kubectl --kubeconfig "${KUBECONFIG}" get replicasets -l name="${name}" -n metal3 -o json | jq '.items[0]')"
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

# Verify the baremetal hosts
## Fetch the BM CRs
BM_HOSTS="$(kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts -n metal3 -o json)"
FAILS=$(process_status $? "Fetch Baremetalhosts")
## Fetch the VMs
BM_VMS="$(virsh list --all)"
FAILS=$(process_status $? "Fetch Baremetalhosts VMs")
## Verify
FAILS="$(list_nodes | check_bm_hosts)"

# Verify the Operators, stateful sets
FAILS=$(check_k8s_entity statefulsets "${EXPTD_STATEFULSETS}")

# Verify the Operators, Deployments
FAILS=$(check_k8s_entity deployments "${EXPTD_DEPLOYMENTS}")

# Verify the Operators, Replica sets
FAILS=$(check_k8s_rs "${EXPTD_DEPLOYMENTS}")


#Verify Ironic containers are running
for name in ironic ironic-inspector dnsmasq httpd mariadb; do
  sudo "${CONTAINER_RUNTIME}" ps | grep -w "$name$" > /dev/null
  FAILS=$(process_status $? "Container ${name} running")
done
echo "" >&3


echo -e "\nNumber of failures : $FAILS" >&3
exit "${FAILS}"
