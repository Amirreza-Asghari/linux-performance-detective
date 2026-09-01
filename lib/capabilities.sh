#!/usr/bin/env bash


#
# ------------------------------------------------------------
# COMMAND AVAILABLE
# ------------------------------------------------------------
#

lpd_command_available() {

    local command_name="${1:-}"

    [[ -n "$command_name" ]] || return 1

    command -v "$command_name" >/dev/null 2>&1
}


#
# ------------------------------------------------------------
# REQUIRED COMMAND
# ------------------------------------------------------------
#

lpd_require_command() {

    local subsystem="${1:-core}"
    local command_name="${2:-}"
    local purpose="${3:-required operation}"


    if lpd_command_available "$command_name"; then
        return 0
    fi


    fail "Required tool missing: $command_name"

    info "Required for: $purpose"


    if declare -F lpd_audit >/dev/null 2>&1; then

        lpd_audit \
            "ERROR" \
            "$subsystem" \
            "REQUIRED_TOOL_MISSING" \
            "tool=$command_name purpose=$purpose"

    fi


    return 1
}


#
# ------------------------------------------------------------
# OPTIONAL COMMAND
# ------------------------------------------------------------
#

lpd_optional_command() {

    local subsystem="${1:-core}"
    local command_name="${2:-}"
    local fallback="${3:-reduced functionality}"


    if lpd_command_available "$command_name"; then
        return 0
    fi


    warn "Optional tool unavailable: $command_name"

    info "Fallback: $fallback"


    if declare -F lpd_audit >/dev/null 2>&1; then

        lpd_audit \
            "WARNING" \
            "$subsystem" \
            "OPTIONAL_TOOL_MISSING" \
            "tool=$command_name fallback=$fallback"

    fi


    return 1
}
