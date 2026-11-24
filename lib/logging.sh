#!/usr/bin/env bash

# Logging functions (log_ts, step, run_quiet_with_log_dump_on_failure,
# source_quiet_with_log_dump_on_failure etc.) and logging colors are derived
# from the ptp-operator project:
#   git@github.com:k8snetworkplumbingwg/ptp-operator.git
#   original file: scripts/run-on-vm.sh
#   commit hash: 85a0f5e1fc16b61ccc411bdc0b659e92576e1046
#   Licensed under the Apache License, Version 2.0
#   Modifications made to adapt metal3-dev-env needs.

# Log output automatically
LOGDIR="$(dirname "$0")/logs"
if [ ! -d "$LOGDIR" ]; then
	mkdir -p "$LOGDIR"
fi
LOGFILE="$LOGDIR/$(basename "$0" .sh)-$(date +%F-%H%M%S).log"
echo "Logging to $LOGFILE"

# Enable global tee only with verbose logging. Without verbose logging we need
# to capture each command output separately because subshell output is not
# captured when redirecting the output. So in order to build full log even in
# non-verbose case, disable global redirection and copy the logs after each
# function call.
if [[ "${VERBOSE_LOGS:-true}" == true ]]; then
	# Set fd 1 and 2 to write to the log file
	exec > >( tee "${LOGFILE}" ) 2>&1
fi

COLOR_STEP='\033[1;36m'
COLOR_ERR='\033[1;31m'
COLOR_GRAY='\033[90m'
COLOR_RESET='\033[0m'

# Same clock layout as Ginkgo's default GINKGO_TIME_FORMAT ("01/02/06 15:04:05.999", see onsi/ginkgo/v2/types).
log_ts() { date '+%m/%d/%y %H:%M:%S.%3N'; }

# Echo step message
step() { echo -e "${COLOR_STEP}STEP:${COLOR_RESET} $* ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"; }

# Run with stdout/stderr captured; no output on success, on failure, print the command log.
# With VERBOSE_LOGS=true, stream output live.
run_quiet_with_log_dump_on_failure() {
	local log_tag="$1"
	shift

	local log_file
	log_file="$(mktemp "${LOGDIR}/${log_tag// /_}.XXXXXX.log")"
	local rc=0

	if [[ "${VERBOSE_LOGS:-true}" == true ]]; then
		echo -e "${COLOR_GRAY}---- BEGIN ${log_tag} (verbose) ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
		set +e
		( set -e -x; "$@" </dev/null; )
		{ rc=$?; set +x -e; } 2>/dev/null
		echo -e "${COLOR_GRAY}---- END ${log_tag} (verbose, exit ${rc}) ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
		rm -f "${log_file}"
		return "${rc}"
	fi

	set +e
	( set -e -x; "$@" </dev/null;) >"${log_file}" 2>&1
	{ rc=$?; set +x -e; } 2>/dev/null

	# Print output to the global logfile
	cat "${log_file}" >> "${LOGFILE}"

	if [[ ${rc} -eq 0 ]]; then
		rm -f "${log_file}"
		return 0
	fi

	# Print failure to terminal
	echo -e "${COLOR_ERR}FAIL ${log_tag}:${COLOR_RESET} (exit code ${rc}) ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
	echo -e "${COLOR_ERR}  CMD:${COLOR_RESET} $*"
	echo -e "${COLOR_ERR}---- BEGIN ${log_tag} LOG ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
	cat "${log_file}"
	echo -e "${COLOR_ERR}---- END ${log_tag} LOG ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
	rm -f "${log_file}"
	return "${rc}"
}

# Sourcing cannot be done in subshell. Hence do sourcing in the current shell
# and accept that error in source target does not stop execution. Source targets
# should only define stuff, not execute though.
source_quiet_with_log_dump_on_failure() {
	local log_tag="$1"
	shift

	local log_file
	log_file="$(mktemp "${LOGDIR}/${log_tag// /_}.XXXXXX.log")"
	local rc=0

	if [[ "${VERBOSE_LOGS:-true}" == true ]]; then
		echo -e "${COLOR_GRAY}---- BEGIN ${log_tag} (verbose) ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
		{ set -x; "$@" </dev/null; }
		{ rc=$?; set +x -e; } 2>/dev/null
		echo -e "${COLOR_GRAY}---- END ${log_tag} (verbose, exit ${rc}) ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
		rm -f "${log_file}"
		return "${rc}"
	fi

	{ set -x; "$@" </dev/null;} >"${log_file}" 2>&1
	{ rc=$?; set +x -e; } 2>/dev/null

	# Print output to the global logfile
	cat "${log_file}" >> "${LOGFILE}"

	if [[ ${rc} -eq 0 ]]; then
		rm -f "${log_file}"
		return 0
	fi

	# Print failure to terminal
	echo -e "${COLOR_ERR}FAIL ${log_tag}:${COLOR_RESET} (exit code ${rc}) ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
	echo -e "${COLOR_ERR}  CMD:${COLOR_RESET} $*"
	echo -e "${COLOR_ERR}---- BEGIN ${log_tag} LOG ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
	cat "${log_file}"
	echo -e "${COLOR_ERR}---- END ${log_tag} LOG ----${COLOR_RESET} ${COLOR_GRAY}@ $(log_ts)${COLOR_RESET}"
	rm -f "${log_file}"
	return "${rc}"
}
