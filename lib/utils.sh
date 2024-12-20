#!/usr/bin/env bash
# common util functions, separated from common.sh

# Reusable repository cloning function
clone_repo()
{
    local repo_url="$1"
    local repo_branch="$2"
    local repo_path="$3"
    local repo_commit="${4:-HEAD}"

    if [[ -d "${repo_path}" ]] && [[ "${FORCE_REPO_UPDATE}" = "true" ]]; then
        rm -rf "${repo_path}"
    fi

    if [[ ! -d "${repo_path}" ]]; then
        pushd "${M3PATH}" || exit
        if [[ "${repo_commit}" = "HEAD" ]]; then
            git clone --depth 1 --branch "${repo_branch}" "${repo_url}" \
                "${repo_path}"
        else
            git clone --branch "${repo_branch}" "${repo_url}" "${repo_path}"
            pushd "${repo_path}" || exit
            git checkout "${repo_commit}"
            popd || exit
        fi
        popd || exit
    fi
}

#
# Iterate a command until it runs successfully or exceeds the maximum retries
#
# Inputs:
# - the command to run
#
iterate()
{
    local runs=0
    local command="$*"

    until "$@" || [[ "${SKIP_RETRIES}" = true ]]; do
        if [[ "${runs}" = "0" ]]; then
            echo "   - Waiting for task completion (up to" \
                "$((TEST_TIME_INTERVAL*TEST_MAX_TIME)) seconds)" \
                " - Command: '${command}'"
        fi
        runs="$((runs + 1))"
        if [[ "${runs}" -ge "${TEST_MAX_TIME}" ]]; then
            return 1
        fi
        sleep "${TEST_TIME_INTERVAL}"
    done

    return $?
}


#
# Retry a command until it runs successfully or exceeds the maximum retries
#
# Inputs:
# - the command to run
#
retry()
{
    local retries=10
    local i
    for i in $(seq 1 "${retries}"); do
        if "${@}"; then
            return 0
        fi
        echo "Retrying... ${i}/${retries}"
        sleep 5
    done
    return 1
}


#
# Check the return code
#
# Inputs:
# - return code to check
# - message to print
#
process_status()
{
    local retcode="$1"
    local message="${2:-}"

    if [[ "${retcode}" -eq 0 ]]; then
        if [[ -n "${message}" ]]; then
            echo "OK - ${message}"
        fi
        return 0
    fi

    if [[ -n "${message}" ]]; then
        echo "FAIL - ${message}"
    else
        echo -n "FAIL - "
    fi

    FAILS=$((FAILS + 1))
    return 1
}

#
# Compare if the two inputs are the same and log
#
# Inputs:
# - first input to compare
# - second input to compare
#
equals()
{
    local retval=0
    [[ "${1}" = "${2}" ]] || retval=1
    if ! process_status "${retval}"; then
        echo "       expected ${2}, got ${1}"
    fi
}

#
# Compare the substring to the string and log
#
# Inputs:
# - Substring to look for
# - String to look for the substring in
#
is_in()
{
    local retval=0
    [[ "${2}" =~ .*(${1}).* ]] || retval=1
    if ! process_status "${retval}"; then
        echo "       expected ${1} to be in ${2}"
    fi
}
