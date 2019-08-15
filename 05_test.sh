#!/usr/bin/env bash

set -u

# Redirect to stdout for logging
# Workaround to avoid returning logs in functions
exec 3>&1

# shellcheck disable=SC1091
source lib/logging.sh
# shellcheck disable=SC1091
source lib/common.sh

FAILS=0
SKIP_RETRIES_USER="${SKIP_RETRIES:-false}"
MACHINES_LIST="centos-0 centos-1"

#
# Tries to run a command over ssh in the machine
#
# Inputs:
# - the ssh user
# - the server ip or domain
# - The baremetal host name
#
ssh_to_machine() {
  local USER SERVER MACHINE_NAME

  USER="${1:?}"
  SERVER="${2:?}"
  MACHINE_NAME="${3:?}"

  ssh -o ConnectTimeout=2 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${USER}"@"${SERVER}" echo "SSH to host is up" > /dev/null 2>&1
  RET_CODE="$?"
  process_status "${RET_CODE}" "${MACHINE_NAME} baremetal host reachable by ssh"
  return "${RET_CODE}"
}

#
# Checks the provisioning status of the baremetal host
#
# Inputs:
# - machine name
# - Baremetal host name
# - Expected state
#
check_provisioning_status(){
  local MACHINE_NAME="${1}"
  local BMH_NAME="${2}"
  local FAILS_CHECK
  local EXPECTED_STATE="${3}"
  FAILS_CHECK="${FAILS}"
  BMH="$(kubectl get bmh -n metal3 -o json "${BMH_NAME}")"

  FAILS="$(equals "$(echo "${BMH}" | jq -r '.status.provisioning.state')" \
    "${EXPECTED_STATE}" \
    "${MACHINE_NAME} baremetal host in correct state : ${EXPECTED_STATE}")"
  echo "${FAILS}"
  if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
    return 1
  fi
  return 0
}

#
# Check that the machine and baremetal host CRs are cross-referencing
#
# Inputs:
# - Machine name
# - Baremetal host name
#
check_bmh_association(){
  local MACHINE_NAME="${1}"
  local BMH_NAME
  local FAILS_CHECK
  FAILS_CHECK="${FAILS}"
  MACHINE="$(kubectl get machine -n metal3 -o json "${MACHINE_NAME}")"
  BMH_NAME="$(echo "${MACHINE}" | \
    jq -r '.metadata.annotations["metal3.io/BareMetalHost"]' | \
    tr '/' ' ' | awk '{print $2}')"
  FAILS="$(is_in "${BMH_NAME}" \
    "master-0 worker-0" \
    "${MACHINE_NAME} Baremetalhost associated")"

  # Fail fast if they are not associated as we cannot get the BMH name
  if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
    echo "${FAILS}"
    return 1
  fi

  # Verify the existence of the bmh
  BMH="$(kubectl get bmh -n metal3 -o json "${BMH_NAME}")"
  FAILS="$(process_status $? "${BMH_NAME} baremetal host CR exist")"

  # Check the consumer ref
  FAILS="$(equals "$(echo "${BMH}" | jq -r '.spec.consumerRef.name')" \
    "${MACHINE_NAME}" \
    "${MACHINE_NAME} Baremetal host correct consumer ref")"

  echo "${FAILS}"
  if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
    return 1
  fi
  return 0
}

#
# Checks the status fields of a baremetal host
#
# Inputs:
# - machine name
# - baremetal host name
# - the expected content of the image field (URL)
# - the expected content of the provisioned status
#
check_bmh_status(){
  local MACHINE_NAME="${1}"
  local BMH_NAME="${2}"
  local IMAGE_NAME="${3}"
  local PROVISIONED_STATUS="${4}"
  local FAILS_CHECK
  FAILS_CHECK="${FAILS}"
  BMH="$(kubectl get bmh -n metal3 -o json "${BMH_NAME}")"

  # Verify the provisioning state of the BMH
  FAILS="$(iterate check_provisioning_status "${MACHINE_NAME}" "${BMH_NAME}" \
    "${PROVISIONED_STATUS}")"

  #Check the image
  FAILS="$(equals "$(echo "${BMH}" | jq -r '.spec.image.url')" \
    "${IMAGE_NAME}" \
    "${MACHINE_NAME} Baremetal host correct image")"

  # Check the error message and operational status
  FAILS="$(equals "$(echo "${BMH}" | jq -r '.status.errorMessage')" \
    "" "${MACHINE_NAME} Baremetal host no error message")"
  FAILS="$(equals "$(echo "${BMH}" | jq -r '.status.operationalStatus')" \
    "OK" "${MACHINE_NAME} Baremetal host operational status ok")"

  echo "${FAILS}"
  if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
    return 1
  fi
  return 0
}

#
# Get the IP of a vm from the dhcp leases
#
# Inputs:
# - baremetal host name
#
get_vm_ip(){
  local BMH_NAME="${1}"
  sudo virsh net-dhcp-leases baremetal | grep "${BMH_NAME}" | awk '{print $5}' \
    | cut -d '/' -f1
}


# provision the machines
for name in $MACHINES_LIST; do
  # Create the machines
  ./create_machine.sh "${name}" > /dev/null
  RET_CODE="$?"
  FAILS="$(process_status "${RET_CODE}" "${name} machine CR created")"
  [[ "${RET_CODE}" != 0 ]] && SKIP_RETRIES=true
done

# Test provisioning
for name in $MACHINES_LIST; do

  # Verify the machine CR exists
  kubectl get machine -n metal3 -o json "${name}" > /dev/null
  RET_CODE="$?"
  FAILS="$(process_status "${RET_CODE}" "${name} machine CR exist")"
  [[ "${RET_CODE}" != 0 ]] && SKIP_RETRIES=true

  #Verify that the machine has a bmh associated
  FAILS="$(iterate check_bmh_association "${name}")"
  # shellcheck disable=SC2181
  [[ "$?" != 0 ]] && SKIP_RETRIES=true

  # Get the machine and BMH
  MACHINE="$(kubectl get machine -n metal3 -o json "${name}")"
  BMH_NAME="$(echo "${MACHINE}" | \
    jq -r '.metadata.annotations["metal3.io/BareMetalHost"]' | \
    tr '/' ' ' | awk '{print $2}')"
  BMH="$(kubectl get bmh -n metal3 -o json "${BMH_NAME}")"
  # shellcheck disable=SC2181
  [[ "$?" != 0 ]] && SKIP_RETRIES=true

  # Check the baremetal hosts status fields
  FAILS="$(check_bmh_status "${name}" "${BMH_NAME}" "$(echo "${MACHINE}" | \
    jq -r '.spec.providerSpec.value.image.url')" "provisioned")"

  # Get the IP of the BMH
  VM_IP="$(get_vm_ip "${BMH_NAME}")"
  RET_CODE="$?"
  FAILS="$(process_status "${RET_CODE}" "${name} get baremetal host IP")"
  [[ "${RET_CODE}" != 0 ]] && SKIP_RETRIES=true

  # Check ssh connection to BMH
  FAILS="$(iterate ssh_to_machine "centos" "${VM_IP}" "${name}")"
  # shellcheck disable=SC2181
  [[ "$?" != 0 ]] && SKIP_RETRIES=true

  echo "" >&3
done
echo "" >&3

SKIP_RETRIES="${SKIP_RETRIES_USER}"

#Test deprovisioning
for name in $MACHINES_LIST; do
  # Get the machine and BMH
  MACHINE="$(kubectl get machine -n metal3 -o json "${name}")"
  BMH_NAME="$(echo "${MACHINE}" | \
    jq -r '.metadata.annotations["metal3.io/BareMetalHost"]' | \
    tr '/' ' ' | awk '{print $2}')"
  # shellcheck disable=SC2181
  [[ "$?" != 0 ]] && SKIP_RETRIES=true

  # Deprovision the machine
  kubectl delete machine -n metal3 "${name}" > /dev/null
  FAILS="$(process_status $? "${name} machine CR deleted")"

  # Check the status fields of the BMH previously associated
  FAILS="$(check_bmh_status "${name}" "${BMH_NAME}" "null" "ready")"
  # shellcheck disable=SC2181
  [[ "$?" != 0 ]] && SKIP_RETRIES=true

  echo "" >&3
done
echo "" >&3



echo -e "\nNumber of failures : $FAILS" >&3
exit "${FAILS}"
