#!/usr/bin/env bash


#
# ------------------------------------------------------------
# DIAGNOSIS RESULT LABEL
# ------------------------------------------------------------
#

lpd_diagnose_result_label() {

    local rc="${1:-3}"


    case "$rc" in

        0)
            printf "OK"
            ;;

        1)
            printf "WARNING"
            ;;

        2)
            printf "CRITICAL"
            ;;

        3)
            printf "UNKNOWN"
            ;;

        *)
            printf "UNKNOWN"
            ;;

    esac
}


#
# ------------------------------------------------------------
# RUN ONE DIAGNOSIS
# ------------------------------------------------------------
#

lpd_diagnose_run_one() {

    local subsystem="${1:-}"
    local function_name="${2:-}"


    if [[ -z "$subsystem" ||
          -z "$function_name" ]]; then

        return 3
    fi


    if ! declare -F "$function_name" >/dev/null 2>&1; then

        fail "Diagnosis function missing: $function_name"


        lpd_audit \
            "ERROR" \
            "$subsystem" \
            "DIAGNOSIS_MISSING" \
            "function=$function_name"


        return 3
    fi


    "$function_name"

    local rc=$?


    case "$rc" in

        0|1|2|3)
            ;;

        *)

            fail "Unexpected diagnosis return code from $subsystem: $rc"


            lpd_audit \
                "ERROR" \
                "$subsystem" \
                "DIAGNOSIS_INVALID_RC" \
                "return_code=$rc"


            rc=3
            ;;

    esac


    lpd_audit \
        "INFO" \
        "$subsystem" \
        "DIAGNOSIS_RESULT" \
        "result=$(lpd_diagnose_result_label "$rc") return_code=$rc"


    return "$rc"
}


#
# ------------------------------------------------------------
# DEEP DIAGNOSIS - ALL SUBSYSTEMS
# ------------------------------------------------------------
#

diagnose_all_run() {

    local cpu_rc=3
    local memory_rc=3
    local disk_rc=3
    local network_rc=3
    local fd_rc=3


    local warnings=0
    local criticals=0
    local unknowns=0


    #
    # ------------------------------------------------------------
    # CPU
    # ------------------------------------------------------------
    #

    lpd_diagnose_run_one \
        "cpu" \
        "cpu_diagnose"

    cpu_rc=$?


    #
    # ------------------------------------------------------------
    # MEMORY
    # ------------------------------------------------------------
    #

    lpd_diagnose_run_one \
        "memory" \
        "memory_diagnose"

    memory_rc=$?


    #
    # ------------------------------------------------------------
    # DISK
    # ------------------------------------------------------------
    #

    lpd_diagnose_run_one \
        "disk" \
        "disk_diagnose"

    disk_rc=$?


    #
    # ------------------------------------------------------------
    # NETWORK
    # ------------------------------------------------------------
    #
    # Network diagnosis intentionally performs active BCC
    # observation and may therefore take longer than the other
    # modules.
    #

    lpd_diagnose_run_one \
        "network" \
        "network_diagnose"

    network_rc=$?


    #
    # ------------------------------------------------------------
    # FILE DESCRIPTORS
    # ------------------------------------------------------------
    #

    lpd_diagnose_run_one \
        "fd" \
        "fd_diagnose"

    fd_rc=$?


    #
    # ------------------------------------------------------------
    # SAVE STATUS FOR REPORTING / FUTURE UI
    # ------------------------------------------------------------
    #

    LPD_DIAG_CPU_STATUS="$(
        lpd_diagnose_result_label "$cpu_rc"
    )"

    LPD_DIAG_MEMORY_STATUS="$(
        lpd_diagnose_result_label "$memory_rc"
    )"

    LPD_DIAG_DISK_STATUS="$(
        lpd_diagnose_result_label "$disk_rc"
    )"

    LPD_DIAG_NETWORK_STATUS="$(
        lpd_diagnose_result_label "$network_rc"
    )"

    LPD_DIAG_FD_STATUS="$(
        lpd_diagnose_result_label "$fd_rc"
    )"


    #
    # ------------------------------------------------------------
    # COUNT RESULTS
    # ------------------------------------------------------------
    #

    local rc=0


    for rc in \
        "$cpu_rc" \
        "$memory_rc" \
        "$disk_rc" \
        "$network_rc" \
        "$fd_rc"
    do

        case "$rc" in

            1)
                warnings=$((warnings + 1))
                ;;

            2)
                criticals=$((criticals + 1))
                ;;

            3)
                unknowns=$((unknowns + 1))
                ;;

        esac

    done


    #
    # ------------------------------------------------------------
    # SUMMARY
    # ------------------------------------------------------------
    #

    section "Deep Diagnosis Summary"


    printf "%-20s %-12s\n" \
        "Subsystem" \
        "Result"

    printf "%-20s %-12s\n" \
        "--------------------" \
        "------------"


    printf "%-20s %-12s\n" \
        "CPU" \
        "$LPD_DIAG_CPU_STATUS"

    printf "%-20s %-12s\n" \
        "Memory" \
        "$LPD_DIAG_MEMORY_STATUS"

    printf "%-20s %-12s\n" \
        "Disk" \
        "$LPD_DIAG_DISK_STATUS"

    printf "%-20s %-12s\n" \
        "Network" \
        "$LPD_DIAG_NETWORK_STATUS"

    printf "%-20s %-12s\n" \
        "File Descriptors" \
        "$LPD_DIAG_FD_STATUS"


    echo

    printf "Warnings:            %s\n" "$warnings"
    printf "Critical findings:   %s\n" "$criticals"
    printf "Unknown/Error:       %s\n" "$unknowns"


    #
    # ------------------------------------------------------------
    # AGGREGATE RESULT
    # ------------------------------------------------------------
    #
    # Safety precedence:
    #
    # UNKNOWN  > CRITICAL > WARNING > HEALTHY
    #
    # A failed diagnostic must never result in a false HEALTHY
    # classification.
    #

    if (( unknowns > 0 )); then

        echo

        fail "Overall deep diagnosis status: UNKNOWN"


        lpd_audit \
            "ERROR" \
            "diagnose" \
            "DIAGNOSIS_ALL_RESULT" \
            "status=UNKNOWN warnings=$warnings criticals=$criticals unknowns=$unknowns"


        return 3
    fi


    if (( criticals > 0 )); then

        echo

        fail "Overall deep diagnosis status: CRITICAL"


        lpd_audit \
            "WARNING" \
            "diagnose" \
            "DIAGNOSIS_ALL_RESULT" \
            "status=CRITICAL warnings=$warnings criticals=$criticals unknowns=$unknowns"


        return 2
    fi


    if (( warnings > 0 )); then

        echo

        warn "Overall deep diagnosis status: WARNING"


        lpd_audit \
            "WARNING" \
            "diagnose" \
            "DIAGNOSIS_ALL_RESULT" \
            "status=WARNING warnings=$warnings criticals=$criticals unknowns=$unknowns"


        return 1
    fi


    echo

    ok "Overall deep diagnosis status: HEALTHY"


    lpd_audit \
        "INFO" \
        "diagnose" \
        "DIAGNOSIS_ALL_RESULT" \
        "status=HEALTHY warnings=0 criticals=0 unknowns=0"


    return 0
}
