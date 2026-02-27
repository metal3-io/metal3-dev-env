#!/usr/bin/env bash
set -euo pipefail

# Secure Boot verification tests for metal3-dev-env
# Run after: make
# Requires: at least 2 available BMHs for parallel positive/negative tests

NAMESPACE="${NAMESPACE:-metal3}"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
SERIAL_LOG_DIR="${SERIAL_LOG_DIR:-/var/log/libvirt/qemu}"
HTTP_IMAGE_DIR="${HTTP_IMAGE_DIR:-/opt/metal3-dev-env/ironic/html/images}"
export KUBECONFIG

# Discover signed image URL from existing BMH or environment

discover_signed_image() {
    # Try from an existing provisioned/available BMH
    local url
    url=$(kubectl get bmh -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.image.url}' 2>/dev/null || true)
    local checksum
    checksum=$(kubectl get bmh -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.image.checksum}' 2>/dev/null || true)

    # Fallback: check ironic httpd for raw images
    if [[ -z "${url}" ]]; then
        local raw_img
        raw_img=$(find "${HTTP_IMAGE_DIR}" -name '*-raw.img' -print -quit 2>/dev/null || true)
        if [[ -n "${raw_img}" ]]; then
            local basename
            basename=$(basename "${raw_img}")
            url="http://172.22.0.1/images/${basename}"
            checksum="http://172.22.0.1/images/${basename}.sha256sum"
        fi
    fi

    SIGNED_IMAGE_URL="${IMAGE_RAW_URL:-${url}}"
    SIGNED_IMAGE_CHECKSUM="${IMAGE_RAW_CHECKSUM:-${checksum}}"
}

discover_signed_image
RESULTS_DIR="/tmp/secureboot-test-$$"
mkdir -p "${RESULTS_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
pass() { log "PASS: $*"; }
fail() { log "FAIL: $*"; }
# shellcheck disable=SC2317,SC2329
skip() { log "SKIP: $*"; }
serial_grep() { sudo grep "$@"; }
serial_tail() { sudo tail "$@"; }

# --- Pre-flight checks ---

preflight() {
    log "=== Pre-flight checks ==="

    # Check VMs have Secure Boot
    local vms
    vms=$(virsh list --all --name | grep -v '^$' || true)
    if [[ -z "${vms}" ]]; then
        fail "No libvirt VMs found"
        exit 1
    fi
    for vm in ${vms}; do
        if ! virsh dumpxml "${vm}" | grep -q "secure='yes'"; then
            fail "VM ${vm} missing secure='yes' in loader"
            exit 1
        fi
    done
    pass "All VMs have Secure Boot configuration"

    # Check sushy-tools config
    local working_dir="${WORKING_DIR:-/opt/metal3-dev-env}"
    local conf_file="${working_dir}/virtualbmc/sushy-tools/conf.py"
    if [[ -f "${conf_file}" ]] && \
        grep -q "SUSHY_EMULATOR_SECURE_BOOT_ENABLED_NVRAM" "${conf_file}"; then
        pass "sushy-tools has Secure Boot configuration"
    else
        fail "sushy-tools missing Secure Boot config"
        exit 1
    fi

    # Ensure two available BMHs (deprovision if needed)
    local all_bmhs
    all_bmhs=$(kubectl get bmh -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}')
    local total
    total=$(echo "${all_bmhs}" | wc -w)
    if [[ "${total}" -lt 2 ]]; then
        fail "Need at least 2 BMHs, found ${total}"
        exit 1
    fi

    for bmh in ${all_bmhs}; do
        local state
        state=$(kubectl get bmh -n "${NAMESPACE}" "${bmh}" \
            -o jsonpath='{.status.provisioning.state}')
        if [[ "${state}" != "available" && "${state}" != "ready" ]]; then
            log "BMH ${bmh} is ${state}, deprovisioning..."
            kubectl patch bmh -n "${NAMESPACE}" "${bmh}" --type=json \
                -p '[{"op":"remove","path":"/spec/image"}]' 2>/dev/null || true
        fi
    done

    log "Waiting for BMHs to become available (up to 300s)..."
    local waited=0
    while [[ ${waited} -lt 300 ]]; do
        local available
        available=$(kubectl get bmh -n "${NAMESPACE}" \
            -o jsonpath='{.items[?(@.status.provisioning.state=="available")].metadata.name}' \
            2>/dev/null)
        local count
        count=$(echo "${available}" | wc -w)
        if [[ "${count}" -ge 2 ]]; then
            break
        fi
        sleep 10
        waited=$((waited + 10))
    done

    local available
    available=$(kubectl get bmh -n "${NAMESPACE}" \
        -o jsonpath='{.items[?(@.status.provisioning.state=="available")].metadata.name}' \
        2>/dev/null)
    local count
    count=$(echo "${available}" | wc -w)
    if [[ "${count}" -lt 2 ]]; then
        fail "Need 2 available BMHs, only ${count} after deprovisioning"
        exit 1
    fi
    pass "Found ${count} available BMHs"

    # Need signed image URL
    if [[ -z "${SIGNED_IMAGE_URL}" ]]; then
        fail "No signed image URL (source lib/images.sh or set IMAGE_RAW_URL)"
        exit 1
    fi
    pass "Signed image: ${SIGNED_IMAGE_URL}"
}

# --- Positive test: signed image + UEFISecureBoot ---

run_positive_test() {
    local bmh="${1}"
    local result_file="${RESULTS_DIR}/positive"

    log "[+] Positive test on BMH ${bmh}..."

    kubectl patch bmh -n "${NAMESPACE}" "${bmh}" --type=merge -p "
    {\"spec\":{
      \"bootMode\":\"UEFISecureBoot\",
      \"online\":true,
      \"image\":{
        \"url\":\"${SIGNED_IMAGE_URL}\",
        \"checksum\":\"${SIGNED_IMAGE_CHECKSUM}\",
        \"checksumType\":\"sha256\",
        \"format\":\"raw\"
      }
    }}"

    log "[+] Waiting for provisioning (up to 600s)..."
    if ! kubectl wait --for=jsonpath='{.status.provisioning.state}'=provisioned \
        "bmh/${bmh}" -n "${NAMESPACE}" --timeout=600s 2>/dev/null; then
        echo "FAIL" > "${result_file}"
        fail "[+] BMH ${bmh} did not reach provisioned state"
        return 1
    fi

    log "[+] Provisioned. Checking Secure Boot via serial log..."

    local vm_name
    vm_name=$(virsh list --all --name | sed 's/_/-/g' | grep "${bmh}" || true)
    vm_name="${vm_name//-/_}"
    local serial_log="${SERIAL_LOG_DIR}/${vm_name}-serial0.log"

    # Wait for kernel boot messages to appear
    local waited=0
    while [[ ${waited} -lt 120 ]]; do
        if serial_grep -qi "Secure Boot is enabled\|Secure boot enabled" \
            "${serial_log}" 2>/dev/null; then
            break
        fi
        sleep 10
        waited=$((waited + 10))
    done

    if serial_grep -qi "Secure Boot is enabled\|Secure boot enabled" \
        "${serial_log}" 2>/dev/null; then
        local sb_line
        sb_line=$(serial_grep -i "Secure Boot is enabled\|Secure boot enabled" \
            "${serial_log}" 2>/dev/null | head -1)
        echo "PASS" > "${result_file}"
        pass "[+] ${sb_line}"
    else
        echo "FAIL" > "${result_file}"
        fail "[+] Secure Boot not confirmed in serial log: ${serial_log}"
    fi
}

# --- Negative test: unsigned image + UEFISecureBoot ---

run_negative_test() {
    local bmh="${1}"
    local result_file="${RESULTS_DIR}/negative"

    log "[-] Negative test on BMH ${bmh}..."

    # Create unsigned image
    local img_dir="${RESULTS_DIR}/images"
    mkdir -p "${img_dir}"
    truncate -s 1G "${img_dir}/unsigned.img"
    mkfs.ext4 -q "${img_dir}/unsigned.img"

    if [[ ! -d "${HTTP_IMAGE_DIR}" ]]; then
        echo "FAIL" > "${result_file}"
        fail "[-] HTTP image dir not found: ${HTTP_IMAGE_DIR}"
        return 1
    fi

    cp "${img_dir}/unsigned.img" "${HTTP_IMAGE_DIR}/"
    sha256sum "${HTTP_IMAGE_DIR}/unsigned.img" | awk '{print $1}' \
        > "${HTTP_IMAGE_DIR}/unsigned.img.sha256sum"

    local http_host
    http_host=$(echo "${SIGNED_IMAGE_URL}" | sed 's|http://||; s|/.*||')

    kubectl patch bmh -n "${NAMESPACE}" "${bmh}" --type=merge -p "
    {\"spec\":{
      \"bootMode\":\"UEFISecureBoot\",
      \"online\":true,
      \"image\":{
        \"url\":\"http://${http_host}/images/unsigned.img\",
        \"checksum\":\"http://${http_host}/images/unsigned.img.sha256sum\",
        \"checksumType\":\"sha256\",
        \"format\":\"raw\"
      }
    }}"

    # Wait for IPA to write image and machine to reboot into final OS
    log "[-] Waiting for boot failure (up to 300s)..."
    local vm_name=""
    local waited=0

    # First wait for VM to exist
    while [[ ${waited} -lt 60 ]]; do
        vm_name=$(virsh list --all --name | grep "${bmh}" || true)
        [[ -n "${vm_name}" ]] && break
        sleep 5
        waited=$((waited + 5))
    done

    local serial_log="${SERIAL_LOG_DIR}/${vm_name}-serial0.log"
    waited=0
    while [[ ${waited} -lt 300 ]]; do
        if sudo test -f "${serial_log}"; then
            if serial_grep -qi \
                "Security Violation\|Access Denied\|Verification failed\|Image is not signed" \
                "${serial_log}" 2>/dev/null; then
                log "[-] Secure Boot rejection found in serial log:"
                serial_grep -i \
                    "Security Violation\|Access Denied\|Verification failed\|Image is not signed" \
                    "${serial_log}" | tail -3 | while IFS= read -r line; do
                    log "[-]   ${line}"
                done
                echo "PASS" > "${result_file}"
                pass "[-] Unsigned image rejected by Secure Boot"
                cleanup_bmh "${bmh}"
                return 0
            fi

            if serial_grep -q "Shell>" "${serial_log}" 2>/dev/null; then
                log "[-] VM dropped to UEFI Shell (no valid bootloader)"
                echo "PASS" > "${result_file}"
                pass "[-] Unsigned image failed to boot"
                cleanup_bmh "${bmh}"
                return 0
            fi
        fi

        sleep 10
        waited=$((waited + 10))
        log "[-] Waiting... (${waited}s)"
    done

    # Fallback: SSH should be unreachable
    local node_ip
    node_ip=$(kubectl get bmh -n "${NAMESPACE}" "${bmh}" \
        -o jsonpath='{.status.hardware.nics[0].ip}' 2>/dev/null || true)

    if [[ -n "${node_ip}" ]]; then
        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o PasswordAuthentication=no \
            "root@${node_ip}" "true" 2>/dev/null; then
            echo "PASS" > "${result_file}"
            pass "[-] Node unreachable (unsigned image did not boot)"
            cleanup_bmh "${bmh}"
            return 0
        fi
        echo "FAIL" > "${result_file}"
        fail "[-] Node booted despite unsigned image!"
        cleanup_bmh "${bmh}"
        return 1
    fi

    echo "FAIL" > "${result_file}"
    fail "[-] Could not determine boot outcome"
    log "[-] Serial log tail:"
    serial_tail -20 "${serial_log}" 2>/dev/null | while IFS= read -r line; do
        log "[-]   ${line}"
    done
    cleanup_bmh "${bmh}"
}

cleanup_bmh() {
    local bmh="${1}"
    log "  Cleaning up BMH ${bmh}..."
    kubectl patch bmh -n "${NAMESPACE}" "${bmh}" --type=json \
        -p '[{"op":"remove","path":"/spec/image"}]' 2>/dev/null || true
}

# --- Main ---

main() {
    log "=== Secure Boot Verification Tests ==="
    log ""

    preflight

    # Pick two available BMHs
    local bmhs
    bmhs=$(kubectl get bmh -n "${NAMESPACE}" \
        -o jsonpath='{.items[?(@.status.provisioning.state=="available")].metadata.name}')
    local positive_bmh negative_bmh
    positive_bmh=$(echo "${bmhs}" | awk '{print $1}')
    negative_bmh=$(echo "${bmhs}" | awk '{print $2}')

    log ""
    log "Positive test BMH: ${positive_bmh}"
    log "Negative test BMH: ${negative_bmh}"
    log ""

    # Run both tests in parallel
    run_positive_test "${positive_bmh}" &
    local positive_pid=$!

    run_negative_test "${negative_bmh}" &
    local negative_pid=$!

    # Wait for both
    local exit_code=0
    wait "${positive_pid}" || exit_code=1
    wait "${negative_pid}" || exit_code=1

    # Summary
    log ""
    log "=== Results ==="
    local pos_result neg_result
    pos_result=$(cat "${RESULTS_DIR}/positive" 2>/dev/null || echo "UNKNOWN")
    neg_result=$(cat "${RESULTS_DIR}/negative" 2>/dev/null || echo "UNKNOWN")
    log "Positive test (signed image boots):    ${pos_result}"
    log "Negative test (unsigned image fails):  ${neg_result}"

    rm -rf "${RESULTS_DIR}"

    if [[ "${pos_result}" == "PASS" && "${neg_result}" == "PASS" ]]; then
        log ""
        pass "All Secure Boot tests passed"
    else
        log ""
        fail "Some tests failed"
        exit_code=1
    fi

    exit "${exit_code}"
}

main "$@"
