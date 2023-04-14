#!/usr/bin/env bash
#
# usage:
#
# 1. source this debug.sh in other scripts, and run
# "debug_store_vars <prefix text>"
# to store current environment variables, and print those that have
# changed since the previous call to the function
#
# 2. you can also print the currently stored variables with
# "debug_print_stored_vars"
#
# 3. at the end of configuration and setup, call
# "debug_print_all_vars"
# to get full dump of variables, and if you supply a pattern as $1
# you get only the matching ones
#
# NOTE: This script does disable "set -eux" temporarily to work with
# improper variable names, variable errors, and to prevent "-x" spamming
# so much that the list of variables and values is readable. Script
# restores the previous flags or uses subshell to do that, so it will not
# mess up the flags set earlier.


# array to store variables and their previous values
declare -A PREVIOUS_VARS=()

# get all variable names from the environment, vars.md is often lagging behind
# and the list of variables from there can be misleading
debug_get_vars()
{
    env | cut -f1 -d"=" | grep -E "^[A-Za-z0-9_]"
}

# print all variables
debug_print_all_vars()
{
    # if a pattern is passed as $1, we filter only those variables
    local only="${1:-}"

    # print all debug in subshell, so we can temporarily disable "ux" errors
    # and we can conveniently also sort the output so its much more readable
    (
        set +eux
        for var in $(debug_get_vars); do
            if [[ -z "${only}" ]] || [[ "${var}" =~ ${only} ]]; then
                echo "${var} = \"${!var}\""
            fi
        done
    ) | sort
}

# print variables we have stored (that have non-empty values)
debug_print_stored_vars()
{
    # print all debug in subshell, so we can temporarily disable "ux" errors
    # and we can conveniently also sort the output so its much more readable
    (
        set +ux
        for var in "${!PREVIOUS_VARS[@]}"; do
            echo "${var} = \"${PREVIOUS_VARS[${var}]}\""
        done
    ) | sort
}

# read and store all variables and their values
debug_store_vars()
{
    # if set, print any variable and value that was changed since previous call
    # use this value as line prefix for prints
    local print_changed="${1:-}"

    # store set values, so we can disable -x temporarily
    # can't use subshell as then stored variables would disappear with subshell
    local set_vars="$-"
    set +eux

    # loop through variables
    for var in $(debug_get_vars); do
        if [[ -n "${print_changed}" ]] && [[ "${PREVIOUS_VARS[${var}]}" != "${!var}" ]]; then
            echo "${print_changed}: ${var} = \"${PREVIOUS_VARS[${var}]}\"  =>  \"${!var}\""
        fi
        if [[ -n "${!var}" ]]; then
            PREVIOUS_VARS[${var}]="${!var}"
        fi
    done

    # restore set options, if they were previously set
    if [[ "${set_vars}" =~ e ]]; then set -e; fi
    if [[ "${set_vars}" =~ u ]]; then set -u; fi
    if [[ "${set_vars}" =~ x ]]; then set -x; fi
}
