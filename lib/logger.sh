#!/usr/bin/env bash


#
# ------------------------------------------------------------
# LOG FIELD SANITIZER
# ------------------------------------------------------------
#

lpd_sanitize_log_field() {

    local value="${1:-}"

    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//|/ }"

    printf "%s" "$value"
}


#
# ------------------------------------------------------------
# INITIALIZE RUN
# ------------------------------------------------------------
#

lpd_log_init() {

    local command_line="${*:-}"


    mkdir -p "$ROOT_DIR/logs"
    mkdir -p "$ROOT_DIR/reports"


    LPD_AUDIT_LOG="$ROOT_DIR/logs/audit.log"
    LPD_ACTION_LOG="$ROOT_DIR/logs/actions.log"
    LPD_REMEDIATION_LOG="$ROOT_DIR/logs/remediations.log"


    touch "$LPD_AUDIT_LOG"
    touch "$LPD_ACTION_LOG"
    touch "$LPD_REMEDIATION_LOG"


    LPD_RUN_ID="$(
        date '+%Y%m%d-%H%M%S'
    )-$$"


    LPD_RUN_START_EPOCH="$(
        date '+%s'
    )"


    LPD_RUN_START_TIME="$(
        date '+%Y-%m-%dT%H:%M:%S%z'
    )"


    LPD_RUN_COMMAND="$command_line"


    LPD_RUN_HOST="$(
        hostname -s 2>/dev/null ||
        hostname 2>/dev/null ||
        echo unknown
    )"


    LPD_RUN_KERNEL="$(
        uname -r 2>/dev/null ||
        echo unknown
    )"


    LPD_RUN_ARCH="$(
        uname -m 2>/dev/null ||
        echo unknown
    )"


    LPD_RUN_USER="${SUDO_USER:-${USER:-unknown}}"


    LPD_RUN_OS="$(
        (
            if [[ -r /etc/os-release ]]; then

                source /etc/os-release

                printf "%s\n" "${PRETTY_NAME:-Linux}"

            else

                printf "%s\n" "Linux"

            fi
        )
    )"


    #
    # Save starting positions.
    #

    LPD_ACTION_START_LINES="$(
        wc -l < "$LPD_ACTION_LOG" 2>/dev/null ||
        echo 0
    )"


    LPD_REMEDIATION_START_LINES="$(
        wc -l < "$LPD_REMEDIATION_LOG" 2>/dev/null ||
        echo 0
    )"


    LPD_RESULT_CPU=""
    LPD_RESULT_MEMORY=""
    LPD_RESULT_DISK=""
    LPD_RESULT_NETWORK=""
    LPD_RESULT_FD=""

    LPD_OVERALL_EXIT_CODE=""
    LPD_OVERALL_STATUS=""

    LPD_RUN_FINISHED=0


    lpd_audit \
        "INFO" \
        "core" \
        "RUN_START" \
        "command=$LPD_RUN_COMMAND"
}


#
# ------------------------------------------------------------
# AUDIT EVENT
# ------------------------------------------------------------
#

lpd_audit() {

    local level="${1:-INFO}"
    local subsystem="${2:-core}"
    local event="${3:-EVENT}"
    local message="${4:-}"


    local timestamp

    timestamp="$(
        date '+%Y-%m-%dT%H:%M:%S%z'
    )"


    level="$(
        lpd_sanitize_log_field "$level"
    )"

    subsystem="$(
        lpd_sanitize_log_field "$subsystem"
    )"

    event="$(
        lpd_sanitize_log_field "$event"
    )"

    message="$(
        lpd_sanitize_log_field "$message"
    )"


    printf "%s|%s|%s|%s|%s|%s\n" \
        "$timestamp" \
        "${LPD_RUN_ID:-unknown}" \
        "$level" \
        "$subsystem" \
        "$event" \
        "$message" \
        >> "${LPD_AUDIT_LOG:-$ROOT_DIR/logs/audit.log}"
}


#
# ------------------------------------------------------------
# STRUCTURED REMEDIATION RECORD
# ------------------------------------------------------------
#
# Format:
#
# timestamp
# run_id
# subsystem
# finding
# target_pid
# target_command
# action
# before
# after
# verification
# result
#
#

lpd_record_remediation() {

    local subsystem="${1:-unknown}"
    local finding="${2:-unknown}"
    local target_pid="${3:-N/A}"
    local target_command="${4:-N/A}"
    local action="${5:-unknown}"
    local before="${6:-}"
    local after="${7:-}"
    local verification="${8:-UNKNOWN}"
    local result="${9:-UNKNOWN}"


    local timestamp

    timestamp="$(
        date '+%Y-%m-%dT%H:%M:%S%z'
    )"


    subsystem="$(
        lpd_sanitize_log_field "$subsystem"
    )"

    finding="$(
        lpd_sanitize_log_field "$finding"
    )"

    target_pid="$(
        lpd_sanitize_log_field "$target_pid"
    )"

    target_command="$(
        lpd_sanitize_log_field "$target_command"
    )"

    action="$(
        lpd_sanitize_log_field "$action"
    )"

    before="$(
        lpd_sanitize_log_field "$before"
    )"

    after="$(
        lpd_sanitize_log_field "$after"
    )"

    verification="$(
        lpd_sanitize_log_field "$verification"
    )"

    result="$(
        lpd_sanitize_log_field "$result"
    )"


    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "$timestamp" \
        "${LPD_RUN_ID:-unknown}" \
        "$subsystem" \
        "$finding" \
        "$target_pid" \
        "$target_command" \
        "$action" \
        "$before" \
        "$after" \
        "$verification" \
        "$result" \
        >> "${LPD_REMEDIATION_LOG:-$ROOT_DIR/logs/remediations.log}"


    lpd_audit \
        "INFO" \
        "$subsystem" \
        "REMEDIATION_RECORDED" \
        "finding=$finding action=$action verification=$verification result=$result"
}


#
# ------------------------------------------------------------
# ACTIONS CREATED DURING CURRENT RUN
# ------------------------------------------------------------
#

lpd_actions_since_start() {

    local action_log="${LPD_ACTION_LOG:-$ROOT_DIR/logs/actions.log}"

    local start_lines="${LPD_ACTION_START_LINES:-0}"


    [[ -f "$action_log" ]] || return 0


    local current_lines

    current_lines="$(
        wc -l < "$action_log" 2>/dev/null ||
        echo 0
    )"


    if (( current_lines <= start_lines )); then
        return 0
    fi


    tail -n "+$((start_lines + 1))" "$action_log"
}


#
# ------------------------------------------------------------
# REMEDIATIONS CREATED DURING CURRENT RUN
# ------------------------------------------------------------
#

lpd_remediations_since_start() {

    local remediation_log="${LPD_REMEDIATION_LOG:-$ROOT_DIR/logs/remediations.log}"

    local start_lines="${LPD_REMEDIATION_START_LINES:-0}"


    [[ -f "$remediation_log" ]] || return 0


    local current_lines

    current_lines="$(
        wc -l < "$remediation_log" 2>/dev/null ||
        echo 0
    )"


    if (( current_lines <= start_lines )); then
        return 0
    fi


    tail -n "+$((start_lines + 1))" "$remediation_log"
}


#
# ------------------------------------------------------------
# FINISH RUN
# ------------------------------------------------------------
#

lpd_log_finish() {

    local exit_code="${1:-0}"


    if [[ "${LPD_RUN_FINISHED:-0}" == "1" ]]; then
        return 0
    fi


    LPD_RUN_FINISHED=1


    local end_epoch

    end_epoch="$(
        date '+%s'
    )"


    local duration=0


    if [[ "${LPD_RUN_START_EPOCH:-}" =~ ^[0-9]+$ ]]; then
        duration=$((end_epoch - LPD_RUN_START_EPOCH))
    fi


    lpd_audit \
        "INFO" \
        "core" \
        "RUN_END" \
        "exit_code=$exit_code duration_seconds=$duration"


    return 0
}
