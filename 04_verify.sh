#!/usr/bin/env bash
# ignore shellcheck v0.9.0 introduced SC2317 about unreachable code
# that doesn't understand traps, variables, functions etc causing all
# code called via iterate() to false trigger SC2317
# shellcheck disable=SC2317

# do not set -e, we want to process all failures, not just one
set -u

export FAILS=0

# shellcheck disable=SC1091
. lib/logging.sh
# shellcheck disable=SC1091
. lib/common.sh
# shellcheck disable=SC1091
. lib/utils.sh
# shellcheck disable=SC1091
. lib/network.sh
# shellcheck disable=SC1091
. lib/images.sh

BMO_RUN_LOCAL="${BMO_RUN_LOCAL:-false}"
CAPM3_RUN_LOCAL="${CAPM3_RUN_LOCAL:-false}"

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
declare -a EXPTD_V1ALPHAX_V1BETAX_CRDS=(
    clusters.cluster.x-k8s.io
    kubeadmconfigs.bootstrap.cluster.x-k8s.io
    kubeadmconfigtemplates.bootstrap.cluster.x-k8s.io
    machinedeployments.cluster.x-k8s.io
    machines.cluster.x-k8s.io
    machinesets.cluster.x-k8s.io
    baremetalhosts.metal3.io
)
declare -a EXPTD_DEPLOYMENTS=(
    capm3-system:capm3-controller-manager
    capi-system:capi-controller-manager
    capi-kubeadm-bootstrap-system:capi-kubeadm-bootstrap-controller-manager
    capi-kubeadm-control-plane-system:capi-kubeadm-control-plane-controller-manager
    baremetal-operator-system:baremetal-operator-controller-manager
)
declare -a EXPTD_RS=(
    cluster.x-k8s.io/provider:infrastructure-metal3:capm3-system:2
    cluster.x-k8s.io/provider:cluster-api:capi-system:1
    cluster.x-k8s.io/provider:bootstrap-kubeadm:capi-kubeadm-bootstrap-system:1
    cluster.x-k8s.io/provider:control-plane-kubeadm:capi-kubeadm-control-plane-system:1
)
declare -a BRIDGES=(
    provisioning
    external
)
declare -a EXPTD_CONTAINERS=(
    httpd-infra
    registry
    vbmc
    sushy-tools
)

if [[ "${EPHEMERAL_CLUSTER}" = "tilt" ]]; then
    exit 0
fi

check_bm_hosts()
{
    local name="$1"
    local address="$2"
    local user="$3"
    local password="$4"
    local mac="$5"

    local cred_name cred_secret
    local bare_metal_hosts bare_metal_host bare_metal_vms bare_metal_vmname bare_metal_vm_ifaces

    bare_metal_hosts="$(kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts \
        -n metal3 -o json)"
    bare_metal_vms="$(sudo virsh list --all)"
    bare_metal_vmname="${name//-/_}"

    # Skip BMH verification if not applied
    if [[ "${SKIP_APPLY_BMH:-false}" != "true" ]]; then
        # Verify BM host exists
        echo "${bare_metal_hosts}" | grep -w "${name}"  > /dev/null
        process_status $? "${name} Baremetalhost exist"

        bare_metal_host="$(echo "${bare_metal_hosts}" | \
            jq ' .items[] | select(.metadata.name=="'"${name}"'" )')"

        # Verify addresses of the host
        equals "$(echo "${bare_metal_host}" | jq -r '.spec.bmc.address')" "${address}" \
            "${name} Baremetalhost address correct"

        equals "$(echo "${bare_metal_host}" | jq -r '.spec.bootMACAddress')" \
            "${mac}" "${name} Baremetalhost mac address correct"

        # Verify BM host status
        equals "$(echo "${bare_metal_host}" | jq -r '.status.operationalStatus')" \
            "OK" "${name} Baremetalhost status OK"

        # Verify credentials exist
        cred_name="$(echo "${bare_metal_host}" | jq -r '.spec.bmc.credentialsName')"
        cred_secret="$(kubectl get secret "${cred_name}" -n metal3 -o json | \
            jq '.data')"
        process_status $? "${name} Baremetalhost credentials secret exist"

        # Verify credentials correct
        equals "$(echo "${cred_secret}" | jq -r '.password' | \
            base64 --decode)" "${password}" "${name} Baremetalhost password correct"

        equals "$(echo "${cred_secret}" | jq -r '.username' | \
            base64 --decode)" "${user}" "${name} Baremetalhost user correct"
    fi

    # Verify the VM was created
    echo "${bare_metal_vms} "| grep -w "${bare_metal_vmname}"  > /dev/null
    process_status $? "${name} Baremetalhost VM exist"

    #Verify the VMs interfaces
    bare_metal_vm_ifaces="$(sudo virsh domiflist "${bare_metal_vmname}")"
    for bridge in "${BRIDGES[@]}"; do
        echo "${bare_metal_vm_ifaces}" | grep -w "${bridge}"  > /dev/null
        process_status $? "${name} Baremetalhost VM interface ${bridge} exist"
    done

    # Skip introspection verification in no BMH applied
    if [[ "${SKIP_APPLY_BMH:-false}" != "true" ]]; then
        # Verify the introspection completed successfully
        is_in "$(echo "${bare_metal_host}" | jq -r '.status.provisioning.state')" \
            "ready available" "${name} Baremetalhost introspecting completed"
    fi

    echo ""
}

# Verify that a resource exists in a type
check_k8s_entity()
{
    local type="$1"
    local entity ns name

    shift
    for item in "$@"; do
        # Check entity exists
        ns="$(echo "${item}" | cut -d ':' -f1)"
        name="$(echo "${item}" | cut -d ':' -f2)"
        entity="$(kubectl --kubeconfig "${KUBECONFIG}" get "${type}" "${name}" \
            -n "${ns}" -o json)"
        process_status $? "${type} ${name} created"

        # Check the replicabaremetalclusters
        if [[ "${BMO_RUN_LOCAL}" != true ]] && [[ "${CAPM3_RUN_LOCAL}" != true ]]; then
            equals "$(echo "${entity}" | jq -r '.status.readyReplicas')" \
                "$(echo "${entity}" | jq -r '.status.replicas')" \
                "${name} ${type} replicas correct"
        fi
    done
}

# Verify that a resource exists in a type
check_k8s_rs()
{
    local label name ns nb entities nb_entities

    for item in "$@"; do
        # Check entity exists
        label="$(echo "${item}" | cut -f1 -d:)"
        name="$(echo "${item}" | cut -f2 -d:)"
        ns="$(echo "${item}" | cut -f3 -d:)"
        nb="$(echo "${item}" | cut -f4 -d:)"
        entities="$(kubectl --kubeconfig "${KUBECONFIG}" get replicasets \
            -l "${label}"="${name}" -n "${ns}" -o json)"
        nb_entities="$(echo "${entities}" | jq -r '.items | length')"
        equals "${nb_entities}" "${nb}" "Replica sets with label ${label}=${name} created"

        # Check the replicas
        if [[ "${BMO_RUN_LOCAL}" != true ]] && [[ "${CAPM3_RUN_LOCAL}" != true ]]; then
            for i in $(seq 0 $((nb_entities-1))); do
                equals "$(echo "${entities}" | jq -r ".items[${i}].status.readyReplicas")" \
                    "$(echo "${entities}" | jq -r ".items[${i}].status.replicas")" \
                    "${name} replicas correct for replica set ${i}"
            done
        fi
    done
}

# Verify a container is running
check_container()
{
    local name="$1"
    local return_status

    sudo "${CONTAINER_RUNTIME}" ps | grep -w "${name}$" > /dev/null
    return_status="$?"
    process_status "${return_status}" "Container ${name} running"
    return "${return_status}"
}

#
# start verifying stuff
#

# Verify networking
for bridge in "${BRIDGES[@]}"; do
    ip link show dev "${bridge}" > /dev/null
    process_status $? "Network ${bridge} exists"
done


# Verify Kubernetes cluster is reachable
kubectl version > /dev/null
process_status $? "Kubernetes cluster reachable"
echo ""

# Verify that the CRDs exist
CRDS="$(kubectl --kubeconfig "${KUBECONFIG}" get crds)"
process_status $? "Fetch CRDs"

# shellcheck disable=SC2068
for name in "${EXPTD_V1ALPHAX_V1BETAX_CRDS[@]}"; do
    echo "${CRDS}" | grep -w "${name}"  >/dev/null
    process_status $? "CRD ${name} created"
done
echo ""

# Verify v1beta1 Operators, Deployments, Replicasets
iterate check_k8s_entity deployments "${EXPTD_DEPLOYMENTS[@]}"
iterate check_k8s_rs "${EXPTD_RS[@]}"

# Skip verification related to virsh when running with fakeIPA
if [[ "${NODES_PLATFORM}" = "fake" ]]; then
    echo "Skipping virsh nodes verification on fake vm platform"
    exit 0
fi

# Verify the baremetal hosts
## Fetch the BM CRs
kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts -n metal3 -o json >/dev/null
process_status $? "Fetch Baremetalhosts"

## Fetch the VMs
sudo virsh list --all >/dev/null
process_status $? "Fetch Baremetalhosts VMs"
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
if [[ "${BMO_RUN_LOCAL}" = true ]]; then
    pgrep "operator-sdk" > /dev/null 2> /dev/null
    process_status $? "Baremetal operator locally running"
fi

if [[ "${CAPM3_RUN_LOCAL}" = true ]]; then
    # shellcheck disable=SC2034
    pgrep -f "go run ./main.go" > /dev/null 2> /dev/null
    process_status $? "CAPI operator locally running"
fi

if [[ "${BMO_RUN_LOCAL}" = true ]] || [[ "${CAPM3_RUN_LOCAL}" = true ]]; then
    echo ""
fi

for container in "${EXPTD_CONTAINERS[@]}"; do
    iterate check_container "${container}"
done

IRONIC_NODES_ENDPOINT="${IRONIC_URL}nodes"
status="$(curl -sk -o /dev/null -I -w "%{http_code}" "${IRONIC_NODES_ENDPOINT}")"
if [[ "${status}" -eq 200 ]]; then
    echo "WARNING: Ironic endpoint is exposed for unauthenticated users"
    exit 1
elif [[ "${status}" -eq 401 ]]; then
    echo "OK - Ironic endpoint is secured"
else
    echo "FAIL- got ${status} from ${IRONIC_NODES_ENDPOINT}, expected 401"
    exit 1
fi
echo ""

echo -e "\nNumber of failures: ${FAILS}"
exit "${FAILS}"
