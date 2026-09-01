#!/usr/bin/env bash


#
# ------------------------------------------------------------
# RUN ONE SCAN CHECK
# ------------------------------------------------------------
#
# The result is stored in LPD_SCAN_LAST_RC.
#
# Valid subsystem results:
#
#   0 = healthy
#   1 = warning
#   2 = critical
#   3 = unknown/error
#
# Any unexpected return code is normalized to 3.
#

lpd_scan_run_check() {

    local module_name="${1:-Unknown}"
    local function_name="${2:-}"

    local raw_rc=3


    LPD_SCAN_LAST_RC=3


    if [[ -z "$function_name" ]] ||
       ! declare -F "$function_name" >/dev/null 2>&1
    then

        fail "$module_name module is not loaded"

        LPD_SCAN_LAST_RC=3

        return 0
    fi


    "$function_name"

    raw_rc=$?


    case "$raw_rc" in

        0|1|2)

            LPD_SCAN_LAST_RC="$raw_rc"
            ;;


        3)

            fail "$module_name check could not be completed"

            LPD_SCAN_LAST_RC=3
            ;;


        *)

            fail "$module_name returned unexpected exit code: $raw_rc"

            LPD_SCAN_LAST_RC=3
            ;;

    esac


    return 0
}


#
# ------------------------------------------------------------
# QUICK SYSTEM SCAN
# ------------------------------------------------------------
#

scan_run() {

    #
    # Professional banner is used only on a real terminal.
    # lpd_ui_banner falls back to the plain banner automatically
    # for redirected / piped output.
    #

    lpd_ui_banner


    section "Quick System Scan"

    info "Collecting system health data..."


    local warnings=0
    local criticals=0
    local errors=0


    local cpu_rc=3
    local memory_rc=3

    local disk_rc=3
    local network_rc=3

    local fd_rc=3


    local rc=0


    #
    # ------------------------------------------------------------
    # REAL PROGRESS START
    # ------------------------------------------------------------
    #
    # Progress represents completed subsystem checks.
    # It is not a health score.
    #

    lpd_ui_progress \
        0 \
        5 \
        "Scan"


    #
    # ------------------------------------------------------------
    # CPU
    # ------------------------------------------------------------
    #

    lpd_scan_run_check \
        "CPU" \
        "cpu_check"

    cpu_rc="$LPD_SCAN_LAST_RC"


    lpd_ui_progress \
        1 \
        5 \
        "Scan"


    #
    # ------------------------------------------------------------
    # MEMORY
    # ------------------------------------------------------------
    #

    lpd_scan_run_check \
        "Memory" \
        "memory_check"

    memory_rc="$LPD_SCAN_LAST_RC"


    lpd_ui_progress \
        2 \
        5 \
        "Scan"


    #
    # ------------------------------------------------------------
    # DISK
    # ------------------------------------------------------------
    #

    lpd_scan_run_check \
        "Disk" \
        "disk_check"

    disk_rc="$LPD_SCAN_LAST_RC"


    lpd_ui_progress \
        3 \
        5 \
        "Scan"


    #
    # ------------------------------------------------------------
    # NETWORK
    # ------------------------------------------------------------
    #

    lpd_scan_run_check \
        "Network" \
        "network_check"

    network_rc="$LPD_SCAN_LAST_RC"


    lpd_ui_progress \
        4 \
        5 \
        "Scan"


    #
    # ------------------------------------------------------------
    # FILE DESCRIPTORS
    # ------------------------------------------------------------
    #

    lpd_scan_run_check \
        "File descriptor" \
        "file_descriptor_check"

    fd_rc="$LPD_SCAN_LAST_RC"


    lpd_ui_progress \
        5 \
        5 \
        "Scan"


    #
    # ------------------------------------------------------------
    # COUNT RESULTS
    # ------------------------------------------------------------
    #

    for rc in \
        "$cpu_rc" \
        "$memory_rc" \
        "$disk_rc" \
        "$network_rc" \
        "$fd_rc"
    do

        case "$rc" in

            0)
                ;;


            1)
                warnings=$((warnings + 1))
                ;;


            2)
                criticals=$((criticals + 1))
                ;;


            3)
                errors=$((errors + 1))
                ;;


            *)

                #
                # Defensive fallback.
                #
                # lpd_scan_run_check already normalizes results,
                # so reaching this branch indicates internal state
                # corruption.
                #

                errors=$((errors + 1))
                ;;

        esac

    done


    #
    # ------------------------------------------------------------
    # TTY SUMMARY
    # ------------------------------------------------------------
    #

    if lpd_ui_enabled; then

        lpd_ui_summary_header


        lpd_ui_status \
            "CPU" \
            "$cpu_rc"


        lpd_ui_status \
            "Memory" \
            "$memory_rc"


        lpd_ui_status \
            "Disk" \
            "$disk_rc"


        lpd_ui_status \
            "Network" \
            "$network_rc"


        lpd_ui_status \
            "File Descriptors" \
            "$fd_rc"

    fi


    #
    # ------------------------------------------------------------
    # FINAL RESULT
    # ------------------------------------------------------------
    #

    section "Scan Result"


    if (( errors > 0 )); then

        fail "System health status is UNKNOWN"

        printf "Errors:            %d\n" "$errors"
        printf "Critical findings: %d\n" "$criticals"
        printf "Warnings:          %d\n" "$warnings"


        lpd_ui_overall 3


        return 3


    elif (( criticals > 0 )); then

        fail "System health: CRITICAL"

        printf "Critical findings: %d\n" "$criticals"
        printf "Warnings:          %d\n" "$warnings"


        lpd_ui_overall 2


        return 2


    elif (( warnings > 0 )); then

        warn "System health: WARNING"

        printf "Warnings:          %d\n" "$warnings"


        lpd_ui_overall 1


        return 1


    else

        ok "System health: HEALTHY"

        printf "Critical findings: 0\n"
        printf "Warnings:          0\n"
        printf "Errors:            0\n"


        lpd_ui_overall 0


        return 0

    fi
}
