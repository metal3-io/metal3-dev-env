#!/usr/bin/env bash

set -u

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

  RESULT_STR="${MACHINE_NAME} baremetal host reachable by ssh"
  ssh -o ConnectTimeout=2 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${USER}"@"${SERVER}" echo "SSH to host is up" > /dev/null 2>&1
  process_status "$?"
  return "$?"
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

  RESULT_STR="${MACHINE_NAME} baremetal host in correct state : ${EXPECTED_STATE}"
  equals "$(echo "${BMH}" | jq -r '.status.provisioning.state')" \
    "${EXPECTED_STATE}"
  return "$((FAILS-FAILS_CHECK))"
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
  RESULT_STR="${MACHINE_NAME} Baremetalhost associated"
  is_in "${BMH_NAME}" "node-0 node-1"

  # Fail fast if they are not associated as we cannot get the BMH name
  if [[ "${FAILS_CHECK}" != "${FAILS}" ]]; then
    return 1
  fi

  # Verify the existence of the bmh
  RESULT_STR="${BMH_NAME} baremetal host CR exist"
  BMH="$(kubectl get bmh -n metal3 -o json "${BMH_NAME}")"
  process_status $?

  # Check the consumer ref
  RESULT_STR="${MACHINE_NAME} Baremetal host correct consumer ref"
  equals "$(echo "${BMH}" | jq -r '.spec.consumerRef.name')" \
    "${MACHINE_NAME}"

  return "$((FAILS-FAILS_CHECK))"
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

  # Verify the provisioning state of the BMH
  iterate check_provisioning_status "${MACHINE_NAME}" "${BMH_NAME}" \
    "${PROVISIONED_STATUS}"

  BMH="$(kubectl get bmh -n metal3 -o json "${BMH_NAME}")"

  #Check the image
  RESULT_STR="${MACHINE_NAME} Baremetal host correct image"
  equals "$(echo "${BMH}" | jq -r '.spec.image.url')" \
    "${IMAGE_NAME}"

  # Check the error message and operational status
  RESULT_STR="${MACHINE_NAME} Baremetal host no error message"
  equals "$(echo "${BMH}" | jq -r '.status.errorMessage')" ""
  RESULT_STR="${MACHINE_NAME} Baremetal host operational status ok"
  equals "$(echo "${BMH}" | jq -r '.status.operationalStatus')" "OK"

  return "$((FAILS-FAILS_CHECK))"
}

#
# Checks if an ip is in a range
#
# Inputs:
# - IP address to check (X.X.X.X)
# - IP range (X.X.X.X,X.X.X.X)
#
# Usage ip_in_range ip start end
ip_in_range() {
  python ip_range_check.py "$1" "$2"
}

#
# Get the IP of a vm from the dhcp leases
#
# Inputs:
# - baremetal host name
#
get_vm_ip(){
  local BMH_NAME="${1}"
  local DHCP_RANGE
  local CONFIGMAP

  # Get configmap for ironic operator
  CONFIGMAP=$(kubectl get configmap -n metal3 | grep ironic-bmo-configmap | awk '{print $1}')

  # Get the DHCP start and end values
  DHCP_RANGE=$(kubectl get configmap -n metal3 "$CONFIGMAP" -o jsonpath='{.data.DHCP_RANGE}')
  #Compare the bmh ips to the dhcp range
  for ip in $(kubectl get bmh -n metal3 "${BMH_NAME}" -o yaml | grep "ip:" | awk '{print $3}'); do
    if ip_in_range "$ip" "$DHCP_RANGE"; then
      echo "$ip"
    fi
  done
}

# provision the machines
for name in $MACHINES_LIST; do
  # Create the machines
  RESULT_STR="${name} machine CR created"
  ./scripts/v1alpha1/create_machine.sh "${name}" > /dev/null
  process_status "$?" || SKIP_RETRIES=true
done

# Test provisioning
for name in $MACHINES_LIST; do

  # Verify the machine CR exists
  RESULT_STR="${name} machine CR exist"
  kubectl get machine -n metal3 -o json "${name}" > /dev/null
  process_status "$?" || SKIP_RETRIES=true

  #Verify that the machine has a bmh associated
  iterate check_bmh_association "${name}" || SKIP_RETRIES=true

  # Get the machine and BMH
  MACHINE="$(kubectl get machine -n metal3 -o json "${name}")"
  BMH_NAME="$(echo "${MACHINE}" | \
    jq -r '.metadata.annotations["metal3.io/BareMetalHost"]' | \
    tr '/' ' ' | awk '{print $2}')"
  BMH="$(kubectl get bmh -n metal3 -o json "${BMH_NAME}")"
  # shellcheck disable=SC2181
  [[ "$?" == 0 ]] || SKIP_RETRIES=true

  # Check the baremetal hosts status fields
  check_bmh_status "${name}" "${BMH_NAME}" "$(echo "${MACHINE}" | \
    jq -r '.spec.providerSpec.value.image.url')" "provisioned"

  # Get the IP of the BMH
  RESULT_STR="${name} get baremetal host IP"
  VM_IP="$(get_vm_ip "${BMH_NAME}")"
  process_status "$?" || SKIP_RETRIES=true

  # Check ssh connection to BMH
  if ! iterate ssh_to_machine "${IMAGE_USERNAME}" "${VM_IP}" "${name}"; then
    SKIP_RETRIES=true
  fi

done

SKIP_RETRIES="${SKIP_RETRIES_USER}"

#Test deprovisioning
for name in $MACHINES_LIST; do
  # Get the machine and BMH
  MACHINE="$(kubectl get machine -n metal3 -o json "${name}")"
  BMH_NAME="$(echo "${MACHINE}" | \
    jq -r '.metadata.annotations["metal3.io/BareMetalHost"]' | \
    tr '/' ' ' | awk '{print $2}')"
  # shellcheck disable=SC2181
  [[ "$?" == 0 ]] || SKIP_RETRIES=true

  # Deprovision the machine
  # shellcheck disable=SC2034
  RESULT_STR="${name} machine CR deleted"
  kubectl delete machine -n metal3 "${name}" > /dev/null
  process_status $?

  # Check the status fields of the BMH previously associated
  if check_bmh_status "${name}" "${BMH_NAME}" "null" "ready"; then
    SKIP_RETRIES=true
  fi

done

echo -e "\nNumber of failures : $FAILS"
exit "${FAILS}"
