#!/usr/bin/env bash
set -euo pipefail

# Keylime measured boot attestation test for metal3-dev-env (Phase 2)
#
# Prerequisites:
#   - metal3-dev-env built with VM_TPM_EMULATOR=true
#
# What this script does:
#   1. Clones upstream keylime repos and builds container images
#   2. Deploys Keylime infra (registrar, verifier) to a dedicated Kind cluster
#   3. Provisions a CAPI workload cluster on bare metal with Secure Boot
#   4. Deploys Keylime agent + TPM device plugin to workload cluster
#   5. Generates measured boot reference state from a node
#   6. Registers agents with verifier using example policy
#   7. Verifies attestation passes (Secure Boot confirmed via PCR 7)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METAL3_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
KEYLIME_DIR="${SCRIPT_DIR}/keylime"
CERTS_DIR="${KEYLIME_DIR}/certs"
KEYLIME_VERSION="${KEYLIME_VERSION:-latest}"
KEYLIME_UID="${KEYLIME_UID:-490}"
KEYLIME_GID="${KEYLIME_GID:-490}"
NAMESPACE="${NAMESPACE:-metal3}"
CLUSTER_NAME="${CLUSTER_NAME:-test1}"
KEYLIME_NS="keylime"
KEYLIME_CLUSTER_NAME="${KEYLIME_CLUSTER_NAME:-keylime}"
KEYLIME_KUBECONFIG="/tmp/kubeconfig-${KEYLIME_CLUSTER_NAME}.yaml"
REGISTRY="${REGISTRY:-192.168.111.1:5000}"
IMAGE_USERNAME="${IMAGE_USERNAME:-metal3}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -q)
RESULTS_DIR="/tmp/keylime-test-$$"

mkdir -p "${RESULTS_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
pass() { log "PASS: $*"; }
fail() { log "FAIL: $*"; }

# Helper: kubectl targeting the keylime Kind cluster
kk() { kubectl --kubeconfig="${KEYLIME_KUBECONFIG}" "$@"; }

# Extract agent UUIDs from registrar via tenant pod
get_agent_uuids() {
    kk exec keylime-tenant -n "${KEYLIME_NS}" -- \
        python3 -c "
import subprocess, json, sys
r = subprocess.run(['keylime_tenant', '-c', 'reglist'],
                   capture_output=True, text=True)
try:
    data = json.loads(r.stdout)
    for u in data.get('results', {}).get('uuids', []):
        print(u)
except json.JSONDecodeError:
    sys.exit(1)
" 2>/dev/null
}

cleanup() {
    log "Cleaning up..."
    rm -rf "${RESULTS_DIR}"
}
trap cleanup EXIT

# --- TLS certificate generation ---

generate_certs() {
    if [[ -f "${CERTS_DIR}/cacert.crt" ]]; then
        log "Certificates already exist"
        return
    fi

    log "Generating TLS certificates..."
    mkdir -p "${CERTS_DIR}"
    local validity=365

    # CA
    openssl genrsa -out "${CERTS_DIR}/cacert.key" 4096 2>/dev/null
    openssl req -new -x509 -days "${validity}" \
        -key "${CERTS_DIR}/cacert.key" \
        -out "${CERTS_DIR}/cacert.crt" \
        -subj "/CN=Keylime CA/O=metal3-dev-env" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,digitalSignature,cRLSign,keyCertSign" \
        -addext "subjectKeyIdentifier=hash" 2>/dev/null

    # Server cert with SANs
    openssl genrsa -out "${CERTS_DIR}/server-private.pem" 4096 2>/dev/null
    openssl req -new -key "${CERTS_DIR}/server-private.pem" \
        -out "${CERTS_DIR}/server.csr" \
        -subj "/CN=keylime-server/O=metal3-dev-env" 2>/dev/null

    local host_ip="${REGISTRY%%:*}"
    cat > "${CERTS_DIR}/server-ext.cnf" << EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,DNS:keylime-verifier,DNS:keylime-registrar,DNS:keylime-verifier.keylime.svc.cluster.local,DNS:keylime-registrar.keylime.svc.cluster.local,IP:127.0.0.1,IP:${host_ip}
EOF
    openssl x509 -req -days "${validity}" \
        -in "${CERTS_DIR}/server.csr" \
        -CA "${CERTS_DIR}/cacert.crt" -CAkey "${CERTS_DIR}/cacert.key" \
        -CAcreateserial \
        -out "${CERTS_DIR}/server-cert.crt" \
        -extfile "${CERTS_DIR}/server-ext.cnf" 2>/dev/null

    # Client cert
    openssl genrsa -out "${CERTS_DIR}/client-private.pem" 4096 2>/dev/null
    openssl req -new -key "${CERTS_DIR}/client-private.pem" \
        -out "${CERTS_DIR}/client.csr" \
        -subj "/CN=keylime-client/O=metal3-dev-env" 2>/dev/null
    openssl x509 -req -days "${validity}" \
        -in "${CERTS_DIR}/client.csr" \
        -CA "${CERTS_DIR}/cacert.crt" -CAkey "${CERTS_DIR}/cacert.key" \
        -CAcreateserial \
        -out "${CERTS_DIR}/client-cert.crt" \
        -extfile <(echo "basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth") 2>/dev/null

    rm -f "${CERTS_DIR}"/*.csr "${CERTS_DIR}"/*.cnf "${CERTS_DIR}"/*.srl
    chmod 644 "${CERTS_DIR}"/*.crt
    chmod 600 "${CERTS_DIR}"/*.pem "${CERTS_DIR}"/*.key
    pass "TLS certificates generated"
}

# --- Build Keylime images from upstream source ---

build_images() {
    log "=== Building Keylime images ==="

    local keylime_src="${KEYLIME_SRC_DIR:-${HOME}/git/keylime}"
    local keylime_git="${keylime_src}/keylime"
    local rust_keylime_git="${keylime_src}/rust-keylime"

    # Clone upstream repos if needed
    mkdir -p "${keylime_src}"
    if [[ ! -d "${keylime_git}/.git" ]]; then
        log "Cloning keylime/keylime..."
        git clone https://github.com/keylime/keylime.git "${keylime_git}"
    fi
    if [[ ! -d "${rust_keylime_git}/.git" ]]; then
        log "Cloning keylime/rust-keylime..."
        git clone https://github.com/keylime/rust-keylime.git "${rust_keylime_git}"
    fi

    # Build server images (registrar, verifier, tenant)
    if ! docker image inspect "keylime_verifier:${KEYLIME_VERSION}" &>/dev/null; then
        log "Installing build prerequisites..."
        if ! command -v skopeo &>/dev/null; then
            local tmp
            tmp=$(mktemp -d)
            local skopeo_url="https://github.com/lework/skopeo-binary/releases/download/v1.17.0/skopeo-linux-amd64"
            log "Downloading skopeo..."
            curl -sSL -o "${tmp}/skopeo" "${skopeo_url}"
            chmod +x "${tmp}/skopeo"
            sudo mv "${tmp}/skopeo" /usr/local/bin/skopeo
            rm -rf "${tmp}"
        fi
        log "Building server images from ${keylime_git}..."
        cd "${keylime_git}/docker/release"
        ./build_locally.sh "${KEYLIME_VERSION}"
    else
        log "Server images already built"
    fi

    # Build push model agent
    if ! docker image inspect "keylime-push-agent:${KEYLIME_VERSION}" &>/dev/null; then
        log "Building push model agent..."
        local agent_ctx="${KEYLIME_DIR}/agents/agent"
        rm -rf "${agent_ctx}/rust-keylime"
        cp -r "${rust_keylime_git}" "${agent_ctx}/rust-keylime"
        docker build -t "keylime-push-agent:${KEYLIME_VERSION}" \
            --build-arg "VERSION=${KEYLIME_VERSION}" \
            --build-arg "KEYLIME_UID=${KEYLIME_UID}" \
            --build-arg "KEYLIME_GID=${KEYLIME_GID}" \
            "${agent_ctx}"
        rm -rf "${agent_ctx}/rust-keylime"
    else
        log "Agent image already built"
    fi

    pass "All Keylime images ready"
}

# --- Preflight ---

preflight() {
    log "=== Preflight checks ==="

    if [[ ! -d "${KEYLIME_DIR}/infra" ]]; then
        fail "Keylime manifests not found at ${KEYLIME_DIR}"
        exit 1
    fi

    local vms
    vms=$(virsh list --all --name | grep -v '^$' || true)
    for vm in ${vms}; do
        if ! virsh dumpxml "${vm}" | grep -q '<tpm model='; then
            fail "VM ${vm} missing vTPM. Rebuild with VM_TPM_EMULATOR=true"
            exit 1
        fi
        if ! virsh dumpxml "${vm}" | grep -q "secure='yes'"; then
            fail "VM ${vm} missing Secure Boot"
            exit 1
        fi
    done
    pass "All VMs have vTPM + Secure Boot"

    if ! kubectl cluster-info &>/dev/null; then
        fail "Management cluster not reachable"
        exit 1
    fi
    pass "Management cluster reachable"

    local bmh_count
    bmh_count=$(kubectl get bmh -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
    if [[ "${bmh_count}" -lt 1 ]]; then
        fail "No BMHs found in namespace ${NAMESPACE}"
        exit 1
    fi
    pass "Found ${bmh_count} BMH(s)"
}

# --- Create dedicated Kind cluster for Keylime infra ---

create_keylime_cluster() {
    log "=== Creating Keylime Kind cluster ==="

    # Multiple Kind clusters need higher inotify limits
    sudo sysctl -w fs.inotify.max_user_instances=512 >/dev/null
    sudo sysctl -w fs.inotify.max_user_watches=524288 >/dev/null

    kind delete cluster --name "${KEYLIME_CLUSTER_NAME}" 2>/dev/null || true

    local host_ip="${REGISTRY%%:*}"
    cat <<EOF | kind create cluster --name "${KEYLIME_CLUSTER_NAME}" --kubeconfig "${KEYLIME_KUBECONFIG}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30881
    hostPort: 30881
    listenAddress: "${host_ip}"
    protocol: tcp
  - containerPort: 30890
    hostPort: 30890
    listenAddress: "${host_ip}"
    protocol: tcp
  - containerPort: 30891
    hostPort: 30891
    listenAddress: "${host_ip}"
    protocol: tcp
EOF
    pass "Keylime Kind cluster created with NodePort mappings"
}

# --- Deploy Keylime infra to keylime cluster ---

deploy_keylime_infra() {
    log "=== Deploying Keylime infra ==="

    generate_certs

    log "Loading Keylime images into Kind cluster..."
    for img in keylime_registrar keylime_verifier keylime_tenant; do
        kind load docker-image --name "${KEYLIME_CLUSTER_NAME}" \
            "${img}:${KEYLIME_VERSION}" 2>/dev/null || true
    done

    local infra="${KEYLIME_DIR}/infra"

    kk apply -f "${infra}/namespace.yaml"

    kk create secret generic keylime-certs \
        --namespace "${KEYLIME_NS}" \
        --from-file=cacert.crt="${CERTS_DIR}/cacert.crt" \
        --from-file=server-cert.crt="${CERTS_DIR}/server-cert.crt" \
        --from-file=server-private.pem="${CERTS_DIR}/server-private.pem" \
        --from-file=client-cert.crt="${CERTS_DIR}/client-cert.crt" \
        --from-file=client-private.pem="${CERTS_DIR}/client-private.pem" \
        --dry-run=client -o yaml | kk apply -f -

    kk create configmap keylime-config \
        --namespace "${KEYLIME_NS}" \
        --from-file="${infra}/configmaps/registrar.conf" \
        --from-file="${infra}/configmaps/verifier.conf" \
        --from-file="${infra}/configmaps/tenant.conf" \
        --dry-run=client -o yaml | kk apply -f -

    sed "s/__KEYLIME_VERSION__/${KEYLIME_VERSION}/g" \
        "${infra}/registrar-deployment.yaml" | kk apply -f -
    kk apply -f "${infra}/registrar-service.yaml"
    sed "s/__KEYLIME_VERSION__/${KEYLIME_VERSION}/g" \
        "${infra}/verifier-deployment.yaml" | kk apply -f -
    kk apply -f "${infra}/verifier-service.yaml"

    kk delete pod keylime-tenant -n "${KEYLIME_NS}" --ignore-not-found
    sed "s/__KEYLIME_VERSION__/${KEYLIME_VERSION}/g" \
        "${infra}/tenant-pod.yaml" | kk apply -f -

    log "Waiting for Keylime infra pods..."
    kk wait --for=condition=Ready pod -l app=keylime-registrar \
        -n "${KEYLIME_NS}" --timeout=120s || true
    kk wait --for=condition=Ready pod -l app=keylime-verifier \
        -n "${KEYLIME_NS}" --timeout=120s || true
    kk wait --for=condition=Ready pod keylime-tenant \
        -n "${KEYLIME_NS}" --timeout=120s || true
    pass "Keylime infra deployed"
}

# --- Provision CAPI workload cluster ---

provision_workload_cluster() {
    log "=== Provisioning CAPI workload cluster ==="

    if kubectl get secret "${CLUSTER_NAME}-kubeconfig" -n "${NAMESPACE}" &>/dev/null; then
        log "Workload cluster '${CLUSTER_NAME}' already exists"
        extract_workload_kubeconfig
        return
    fi

    log "Creating workload cluster via CAPI (this takes 15-30 min)..."
    cd "${METAL3_DIR}"
    ACTION=ci_test_provision tests/run.sh
    extract_workload_kubeconfig
}

extract_workload_kubeconfig() {
    local kc="/tmp/kubeconfig-${CLUSTER_NAME}.yaml"
    kubectl get secret "${CLUSTER_NAME}-kubeconfig" -n "${NAMESPACE}" \
        -o jsonpath='{.data.value}' | base64 -d > "${kc}"
    export WORKLOAD_KUBECONFIG="${kc}"

    log "Waiting for workload cluster nodes..."
    local waited=0
    while [[ ${waited} -lt 600 ]]; do
        local ready
        ready=$(kubectl --kubeconfig="${WORKLOAD_KUBECONFIG}" get nodes \
            --no-headers 2>/dev/null | grep -c " Ready" || true)
        if [[ "${ready}" -ge 1 ]]; then
            pass "Workload cluster has ${ready} ready node(s)"
            return
        fi
        sleep 15
        waited=$((waited + 15))
    done
    fail "Workload cluster nodes not ready after 600s"
    exit 1
}

# --- Deploy Keylime agents to workload cluster ---

deploy_agents() {
    log "=== Deploying Keylime agents to workload cluster ==="

    local wkc="${WORKLOAD_KUBECONFIG}"
    local agents="${KEYLIME_DIR}/agents"
    local host_ip="${REGISTRY%%:*}"

    # Clean up any existing agent deployment
    kubectl --kubeconfig="${wkc}" delete namespace "${KEYLIME_NS}" \
        --ignore-not-found --wait

    # Push agent image to local registry
    log "Pushing agent image to local registry..."
    docker tag "keylime-push-agent:${KEYLIME_VERSION}" \
        "${REGISTRY}/keylime-push-agent:${KEYLIME_VERSION}"
    docker push "${REGISTRY}/keylime-push-agent:${KEYLIME_VERSION}"

    # Device plugin
    kubectl --kubeconfig="${wkc}" apply -f "${agents}/device-plugin.yaml"
    kubectl --kubeconfig="${wkc}" wait --for=condition=Ready \
        pod -l app.kubernetes.io/name=generic-device-plugin \
        -n kube-system --timeout=120s || true

    local waited=0
    while [[ ${waited} -lt 60 ]]; do
        if kubectl --kubeconfig="${wkc}" describe nodes | grep -q "squat.ai/tpm"; then
            break
        fi
        sleep 5
        waited=$((waited + 5))
    done
    pass "TPM device plugin ready"

    # Agent namespace + secrets + config
    kubectl --kubeconfig="${wkc}" apply -f "${agents}/namespace.yaml"

    kubectl --kubeconfig="${wkc}" create secret generic keylime-client-certs \
        --namespace "${KEYLIME_NS}" \
        --from-file=cacert.crt="${CERTS_DIR}/cacert.crt" \
        --from-file=client-cert.crt="${CERTS_DIR}/client-cert.crt" \
        --from-file=client-private.pem="${CERTS_DIR}/client-private.pem" \
        --dry-run=client -o yaml | kubectl --kubeconfig="${wkc}" apply -f -

    kubectl --kubeconfig="${wkc}" create configmap keylime-agent-config \
        --namespace "${KEYLIME_NS}" \
        --from-file=agent.conf="${agents}/agent/keylime-agent.conf" \
        --from-literal=registrar_host="${host_ip}" \
        --from-literal=verifier_url="https://${host_ip}:30881" \
        --dry-run=client -o yaml | kubectl --kubeconfig="${wkc}" apply -f -

    # Agent DaemonSet (use local registry image)
    sed "s|keylime-push-agent:__KEYLIME_VERSION__|${REGISTRY}/keylime-push-agent:${KEYLIME_VERSION}|g; \
         s|imagePullPolicy: Never|imagePullPolicy: Always|g; \
         s|__KEYLIME_UID__|${KEYLIME_UID}|g; \
         s|__KEYLIME_GID__|${KEYLIME_GID}|g" \
        "${agents}/agent-daemonset-hw.yaml" | \
        kubectl --kubeconfig="${wkc}" apply -f -

    log "Waiting for agent pods..."
    kubectl --kubeconfig="${wkc}" wait --for=condition=Ready \
        pod -l app=keylime-agent -n "${KEYLIME_NS}" --timeout=180s || true
    pass "Keylime agents deployed"
}

# --- Generate refstate and register agents ---

register_agents() {
    log "=== Registering agents with verifier ==="

    log "Waiting for agents to appear in registrar..."
    local waited=0
    local agent_uuids=""
    while [[ ${waited} -lt 120 ]]; do
        local reglist_output
        reglist_output=$(kk exec keylime-tenant -n "${KEYLIME_NS}" -- \
            keylime_tenant -c reglist 2>/dev/null || true)
        agent_uuids=$(echo "${reglist_output}" | \
            grep '"uuids"' | \
            grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{64}' | \
            sort -u || true)
        if [[ -n "${agent_uuids}" ]]; then
            break
        fi
        if [[ $((waited % 30)) -eq 0 ]] && [[ ${waited} -gt 0 ]]; then
            log "reglist output: ${reglist_output}"
        fi
        sleep 10
        waited=$((waited + 10))
    done

    if [[ -z "${agent_uuids}" ]]; then
        fail "No agents registered after 120s"
        kubectl --kubeconfig="${WORKLOAD_KUBECONFIG}" logs -n "${KEYLIME_NS}" \
            -l app=keylime-agent --tail=20 || true
        exit 1
    fi

    local agent_count
    agent_count=$(echo "${agent_uuids}" | wc -l)
    pass "Found ${agent_count} agent(s) in registrar"

    # Get node IP and copy boot measurements
    local node_ip
    node_ip=$(kubectl --kubeconfig="${WORKLOAD_KUBECONFIG}" get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    log "Copying boot measurements from node ${node_ip}..."
    ssh "${SSH_OPTS[@]}" "${IMAGE_USERNAME}@${node_ip}" \
        "sudo cat /sys/kernel/security/tpm0/binary_bios_measurements" \
        > "${RESULTS_DIR}/binary_bios_measurements"

    # Generate refstate in tenant pod
    log "Generating measured boot reference state..."
    kk cp "${RESULTS_DIR}/binary_bios_measurements" \
        "${KEYLIME_NS}/keylime-tenant:/tmp/binary_bios_measurements"
    kk exec keylime-tenant -n "${KEYLIME_NS}" -- \
        keylime-policy create measured-boot \
        -e /tmp/binary_bios_measurements -o /tmp/refstate.json
    pass "Reference state generated"

    # Add agents to verifier
    for uuid in ${agent_uuids}; do
        log "Adding agent ${uuid} to verifier..."
        kk exec keylime-tenant -n "${KEYLIME_NS}" -- \
            keylime_tenant -c add --push-model -u "${uuid}" \
            --mb-policy /tmp/refstate.json || true
    done
    pass "All agents added to verifier"
}

# --- Verify attestation ---

verify_attestation() {
    log "=== Verifying attestation ==="

    local agent_uuids
    agent_uuids=$(kk exec keylime-tenant -n "${KEYLIME_NS}" -- \
        keylime_tenant -c reglist 2>/dev/null | \
        grep '"uuids"' | \
        grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{64}' | \
        sort -u || true)

    local success=0
    local total=0
    for uuid in ${agent_uuids}; do
        total=$((total + 1))
        local att_count=0
        local waited=0
        while [[ ${waited} -lt 120 ]]; do
            local status
            status=$(kk exec keylime-tenant -n "${KEYLIME_NS}" -- \
                keylime_tenant -c status -u "${uuid}" --push-model 2>/dev/null || true)
            att_count=$(echo "${status}" | grep -o '"attestation_count": [0-9]*' | \
                grep -o '[0-9]*' || echo "0")
            if [[ -n "${att_count}" ]] && [[ "${att_count}" -gt 0 ]]; then
                break
            fi
            sleep 10
            waited=$((waited + 10))
        done

        if [[ -n "${att_count}" ]] && [[ "${att_count}" -gt 0 ]]; then
            pass "Agent ${uuid}: ${att_count} attestation(s)"
            success=$((success + 1))
        else
            fail "Agent ${uuid}: no attestations after 120s"
        fi
    done

    if [[ "${success}" -eq "${total}" ]] && [[ "${total}" -gt 0 ]]; then
        pass "All ${total} agent(s) attesting with measured boot policy"
        echo "PASS" > "${RESULTS_DIR}/result"
    else
        fail "${success}/${total} agents attesting"
        echo "FAIL" > "${RESULTS_DIR}/result"
    fi
}

# --- Main ---

main() {
    log "=== Keylime Measured Boot Attestation Test ==="
    log ""

    preflight
    build_images
    create_keylime_cluster
    deploy_keylime_infra
    provision_workload_cluster
    deploy_agents
    register_agents
    verify_attestation

    log ""
    log "=== Results ==="
    local result
    result=$(cat "${RESULTS_DIR}/result" 2>/dev/null || echo "UNKNOWN")
    log "Measured boot attestation: ${result}"

    if [[ "${result}" == "PASS" ]]; then
        pass "Keylime attestation test passed"
    else
        fail "Keylime attestation test failed"
        exit 1
    fi
}

main "$@"
