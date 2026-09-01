#!/usr/bin/env bash


#
# ------------------------------------------------------------
# RUNTIME RESOURCE REGISTRY
# ------------------------------------------------------------
#
# Only helper resources created by LPD itself are registered.
#
# Diagnosed user workloads are NEVER registered here.
#

LPD_RUNTIME_PIDS=()
LPD_RUNTIME_FILES=()

LPD_RUNTIME_CLEANING=0


#
# ------------------------------------------------------------
# PID STATE
# ------------------------------------------------------------
#

lpd_runtime_pid_alive() {

    local pid="${1:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1


    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi


    local state=""

    state=$(
        ps -o stat= -p "$pid" 2>/dev/null |
        awk '
            NR == 1 {
                print $1
                exit
            }
        '
    )


    [[ -n "$state" ]] || return 1


    if [[ "$state" == Z* ]]; then
        return 1
    fi


    return 0
}


#
# ------------------------------------------------------------
# REGISTER PID
# ------------------------------------------------------------
#

lpd_runtime_register_pid() {

    local pid="${1:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1


    local existing=""


    for existing in "${LPD_RUNTIME_PIDS[@]}"; do

        if [[ "$existing" == "$pid" ]]; then
            return 0
        fi

    done


    LPD_RUNTIME_PIDS+=("$pid")


    return 0
}


#
# ------------------------------------------------------------
# UNREGISTER PID
# ------------------------------------------------------------
#

lpd_runtime_unregister_pid() {

    local target="${1:-}"

    local updated=()

    local pid=""


    for pid in "${LPD_RUNTIME_PIDS[@]}"; do

        if [[ "$pid" != "$target" ]]; then
            updated+=("$pid")
        fi

    done


    LPD_RUNTIME_PIDS=("${updated[@]}")


    return 0
}


#
# ------------------------------------------------------------
# REGISTER FILE
# ------------------------------------------------------------
#

lpd_runtime_register_file() {

    local file="${1:-}"


    [[ -n "$file" ]] || return 1


    local existing=""


    for existing in "${LPD_RUNTIME_FILES[@]}"; do

        if [[ "$existing" == "$file" ]]; then
            return 0
        fi

    done


    LPD_RUNTIME_FILES+=("$file")


    return 0
}


#
# ------------------------------------------------------------
# UNREGISTER FILE
# ------------------------------------------------------------
#

lpd_runtime_unregister_file() {

    local target="${1:-}"

    local updated=()

    local file=""


    for file in "${LPD_RUNTIME_FILES[@]}"; do

        if [[ "$file" != "$target" ]]; then
            updated+=("$file")
        fi

    done


    LPD_RUNTIME_FILES=("${updated[@]}")


    return 0
}


#
# ------------------------------------------------------------
# WAIT UNTIL HELPER STOPS
# ------------------------------------------------------------
#

lpd_runtime_wait_stopped() {

    local pid="${1:-}"
    local attempts="${2:-20}"
    local delay="${3:-0.1}"


    local i=0


    for ((i = 0; i < attempts; i++)); do

        if ! lpd_runtime_pid_alive "$pid"; then

            wait "$pid" 2>/dev/null || true

            return 0
        fi


        sleep "$delay"

    done


    return 1
}


#
# ------------------------------------------------------------
# STOP LPD-OWNED HELPER
# ------------------------------------------------------------
#

lpd_runtime_stop_pid() {

    local pid="${1:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 0


    if ! lpd_runtime_pid_alive "$pid"; then

        wait "$pid" 2>/dev/null || true

        return 0
    fi


    #
    # Stage 1: SIGINT
    #

    kill -INT "$pid" 2>/dev/null || true


    if lpd_runtime_wait_stopped "$pid" 30 0.1; then
        return 0
    fi


    #
    # Stage 2: SIGTERM
    #

    kill -TERM "$pid" 2>/dev/null || true


    if lpd_runtime_wait_stopped "$pid" 20 0.1; then
        return 0
    fi


    #
    # Stage 3: SIGKILL
    #
    # IMPORTANT:
    # Only LPD-created helper processes ever reach this function.
    #

    kill -KILL "$pid" 2>/dev/null || true


    lpd_runtime_wait_stopped "$pid" 10 0.1 || true


    wait "$pid" 2>/dev/null || true


    return 0
}


#
# ------------------------------------------------------------
# GLOBAL CLEANUP
# ------------------------------------------------------------
#

lpd_runtime_cleanup() {

    #
    # Prevent duplicate/re-entrant cleanup.
    #

    if (( LPD_RUNTIME_CLEANING == 1 )); then
        return 0
    fi


    LPD_RUNTIME_CLEANING=1


    if declare -F lpd_audit >/dev/null 2>&1; then

        lpd_audit \
            "INFO" \
            "runtime" \
            "CLEANUP_START" \
            "pids=${#LPD_RUNTIME_PIDS[@]} files=${#LPD_RUNTIME_FILES[@]}"

    fi


    local pid=""
    local file=""


    #
    # Stop every helper process created by this LPD run.
    #

    for pid in "${LPD_RUNTIME_PIDS[@]}"; do

        lpd_runtime_stop_pid "$pid"

    done


    #
    # Remove every registered temporary file.
    #

    for file in "${LPD_RUNTIME_FILES[@]}"; do

        [[ -n "$file" ]] || continue


        if [[ -e "$file" ]]; then
            rm -f -- "$file" 2>/dev/null || true
        fi

    done


    LPD_RUNTIME_PIDS=()
    LPD_RUNTIME_FILES=()


    if declare -F lpd_audit >/dev/null 2>&1; then

        lpd_audit \
            "INFO" \
            "runtime" \
            "CLEANUP_END" \
            "runtime resources released"

    fi


    return 0
}


#
# ------------------------------------------------------------
# SIGNAL HANDLER
# ------------------------------------------------------------
#

lpd_signal_handler() {

    local signal="${1:-UNKNOWN}"

    local exit_code=130


    case "$signal" in

        INT)
            exit_code=130
            ;;

        TERM)
            exit_code=143
            ;;

        *)
            exit_code=1
            ;;

    esac


    if declare -F lpd_audit >/dev/null 2>&1; then

        lpd_audit \
            "WARNING" \
            "core" \
            "SIGNAL_RECEIVED" \
            "signal=$signal"

    fi


    if declare -F warn >/dev/null 2>&1; then

        warn "Interrupt received; cleaning up LPD runtime resources..."

    fi


    exit "$exit_code"
}


#
# ------------------------------------------------------------
# EXIT HANDLER
# ------------------------------------------------------------
#

lpd_exit_handler() {

    local exit_code=$?


    #
    # CRITICAL:
    #
    # Disable EXIT recursion, but IGNORE INT/TERM while cleanup
    # is running.
    #
    # Previous implementation restored INT/TERM to defaults.
    # A second Ctrl+C could therefore kill the shell halfway
    # through cleanup and leave BCC helpers/temp files behind.
    #

    trap - EXIT

    trap '' INT TERM


    lpd_runtime_cleanup


    if declare -F lpd_log_finish >/dev/null 2>&1; then

        lpd_log_finish "$exit_code"

    fi


    exit "$exit_code"
}
