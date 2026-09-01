#!/usr/bin/env bash


#
# ------------------------------------------------------------
# UI HELPERS
# ------------------------------------------------------------
#

interactive_ui_enabled() {

    if declare -F lpd_ui_enabled >/dev/null 2>&1 &&
       lpd_ui_enabled
    then
        return 0
    fi

    return 1
}


interactive_ui_banner() {

    if declare -F lpd_ui_banner >/dev/null 2>&1; then

        lpd_ui_banner

    else

        print_banner

    fi
}


interactive_ui_stage() {

    local stage="${1:-}"
    local subsystem="${2:-}"


    if declare -F lpd_ui_stage >/dev/null 2>&1; then

        lpd_ui_stage \
            "$stage" \
            "$subsystem"

    fi
}


interactive_ui_progress() {

    local current="${1:-0}"
    local total="${2:-0}"
    local label="${3:-Progress}"


    if declare -F lpd_ui_progress >/dev/null 2>&1; then

        lpd_ui_progress \
            "$current" \
            "$total" \
            "$label"

    fi
}


interactive_subsystem_display() {

    local subsystem="${1:-}"


    case "$subsystem" in

        cpu)
            printf "CPU"
            ;;

        memory)
            printf "Memory"
            ;;

        disk)
            printf "Disk"
            ;;

        network)
            printf "Network"
            ;;

        fd)
            printf "File Descriptors"
            ;;

        *)
            printf "%s" "$subsystem"
            ;;

    esac
}


#
# ------------------------------------------------------------
# INTERACTIVE RESULT LABEL
# ------------------------------------------------------------
#

interactive_result_label() {

    local rc="${1:-3}"


    case "$rc" in

        0)
            printf "HEALTHY"
            ;;

        1)
            printf "ATTENTION"
            ;;

        2)
            printf "FAILED"
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
# VALIDATE RETURN CODE
# ------------------------------------------------------------
#

interactive_validate_rc() {

    local subsystem="${1:-unknown}"
    local stage="${2:-unknown}"

    local rc="${3:-}"
    local allow_no_action="${4:-0}"


    case "$rc" in

        0|1|2|3)
            return 0
            ;;

    esac


    if [[ "$allow_no_action" == "1" &&
          "$rc" == "10" ]]; then

        return 0
    fi


    fail "Unexpected return code from $subsystem $stage: $rc"


    lpd_audit \
        "ERROR" \
        "$subsystem" \
        "INTERACTIVE_INVALID_RC" \
        "stage=$stage return_code=$rc"


    return 1
}


#
# ------------------------------------------------------------
# RECORD EXPLICIT NO-ACTION DECISION
# ------------------------------------------------------------
#

interactive_record_no_action() {

    local subsystem="${1:-unknown}"


    local finding="UNKNOWN_FINDING"

    local pid="N/A"
    local command="N/A"

    local action="NO_ACTION"
    local before="N/A"


    case "$subsystem" in

        cpu)

            finding="CPU_PRESSURE"

            pid="${LPD_CPU_PID:-N/A}"
            command="${LPD_CPU_COMMAND:-N/A}"

            action="${LPD_CPU_ACTION:-NO_ACTION}"

            before="cpu=${LPD_CPU_USAGE:-N/A}%"
            ;;


        memory)

            finding="MEMORY_PRESSURE"

            pid="${LPD_MEMORY_PID:-N/A}"
            command="${LPD_MEMORY_COMMAND:-N/A}"

            action="${LPD_MEMORY_ACTION:-NO_ACTION}"

            before="available=${LPD_MEMORY_BEFORE_AVAILABLE:-N/A}%;process_memory=${LPD_MEMORY_PROCESS_PCT:-N/A}%"
            ;;


        disk)

            finding="DISK_IO_PRESSURE"

            pid="${LPD_DISK_PID:-N/A}"
            command="${LPD_DISK_COMMAND:-N/A}"

            action="${LPD_DISK_ACTION:-NO_ACTION}"

            before="device=${LPD_DISK_DEVICE:-N/A};util=${LPD_DISK_BEFORE_UTIL:-N/A}%;queue=${LPD_DISK_BEFORE_QUEUE:-N/A}"
            ;;


        network)

            finding="NETWORK_CONNECTION_ANOMALY"

            pid="${LPD_NETWORK_PID:-N/A}"
            command="${LPD_NETWORK_COMMAND:-N/A}"

            action="${LPD_NETWORK_ACTION:-NO_ACTION}"

            before="time_wait=${LPD_NETWORK_BEFORE_TIME_WAIT:-N/A};connections=${LPD_NETWORK_TOTAL_CONNECTS:-N/A}"
            ;;


        fd)

            finding="FILE_DESCRIPTOR_PRESSURE"

            pid="${LPD_FD_PID:-N/A}"
            command="${LPD_FD_COMMAND:-N/A}"

            action="${LPD_FD_ACTION:-NO_ACTION}"

            before="open=${LPD_FD_BEFORE_OPEN:-N/A};soft_limit=${LPD_FD_BEFORE_SOFT:-N/A};utilization=${LPD_FD_BEFORE_RATIO:-N/A}%"
            ;;

    esac


    lpd_record_remediation \
        "$subsystem" \
        "$finding" \
        "$pid" \
        "$command" \
        "$action" \
        "$before" \
        "no_change;rollback=NOT_APPLICABLE" \
        "NOT_RUN" \
        "NO_ACTION"
}


#
# ------------------------------------------------------------
# RUN ONE WORKFLOW
# ------------------------------------------------------------
#

interactive_run_one() {

    local subsystem="${1:-}"


    local check_function=""
    local diagnose_function=""

    local remediate_function=""
    local verify_function=""

    local subsystem_label=""


    case "$subsystem" in

        cpu)

            check_function="cpu_check"
            diagnose_function="cpu_diagnose"

            remediate_function="cpu_remediate"
            verify_function="cpu_verify"
            ;;


        memory)

            check_function="memory_check"
            diagnose_function="memory_diagnose"

            remediate_function="memory_remediate"
            verify_function="memory_verify"
            ;;


        disk)

            check_function="disk_check"
            diagnose_function="disk_diagnose"

            remediate_function="disk_remediate"
            verify_function="disk_verify"
            ;;


        network)

            check_function="network_check"
            diagnose_function="network_diagnose"

            remediate_function="network_remediate"
            verify_function="network_verify"
            ;;


        fd)

            check_function="file_descriptor_check"
            diagnose_function="fd_diagnose"

            remediate_function="fd_remediate"
            verify_function="fd_verify"
            ;;


        *)

            fail "Unknown interactive subsystem: $subsystem"

            return 3
            ;;

    esac


    subsystem_label=$(
        interactive_subsystem_display \
            "$subsystem"
    )


    #
    # Function validation
    #

    local function_name=""


    for function_name in \
        "$check_function" \
        "$diagnose_function" \
        "$remediate_function" \
        "$verify_function"
    do

        if ! declare -F "$function_name" >/dev/null 2>&1; then

            fail "Required interactive function missing: $function_name"


            lpd_audit \
                "ERROR" \
                "$subsystem" \
                "INTERACTIVE_FUNCTION_MISSING" \
                "function=$function_name"


            return 3
        fi

    done


    #
    # ------------------------------------------------------------
    # DETECT
    # ------------------------------------------------------------
    #

    interactive_ui_stage \
        "Detect" \
        "$subsystem_label"


    "$check_function"

    local check_rc=$?


    if ! interactive_validate_rc \
        "$subsystem" \
        "check" \
        "$check_rc" \
        "0"
    then

        return 3
    fi


    if (( check_rc == 3 )); then

        fail "Interactive workflow cannot continue because the $subsystem check is UNKNOWN"

        return 3
    fi


    #
    # Network is always actively diagnosed because bursty
    # connection activity may not appear in one snapshot.
    #

    if (( check_rc == 0 )) &&
       [[ "$subsystem" != "network" ]]; then

        return 0
    fi


    #
    # ------------------------------------------------------------
    # DIAGNOSE + EVIDENCE
    # ------------------------------------------------------------
    #
    # Diagnosis functions already collect and explain evidence.
    # We intentionally do not invent a separate fake progress
    # stage for "Explain Evidence".
    #

    interactive_ui_stage \
        "Diagnose & Evidence" \
        "$subsystem_label"


    "$diagnose_function"

    local diagnose_rc=$?


    if ! interactive_validate_rc \
        "$subsystem" \
        "diagnose" \
        "$diagnose_rc" \
        "0"
    then

        return 3
    fi


    case "$diagnose_rc" in

        0)
            return 0
            ;;


        3)

            fail "Deep diagnosis is UNKNOWN; remediation will not be attempted"

            return 3
            ;;

    esac


    #
    # ------------------------------------------------------------
    # REMEDIATE
    # ------------------------------------------------------------
    #
    # The remediation module presents the actual user decision
    # when an action is available.
    #

    interactive_ui_stage \
        "Remediate" \
        "$subsystem_label"


    "$remediate_function"

    local remediate_rc=$?


    if ! interactive_validate_rc \
        "$subsystem" \
        "remediate" \
        "$remediate_rc" \
        "1"
    then

        fail "Remediation outcome cannot be trusted"

        return 3
    fi


    case "$remediate_rc" in

        10)

            interactive_record_no_action \
                "$subsystem"


            echo

            warn "No remediation was performed"

            warn "The diagnosed condition remains unresolved"


            lpd_audit \
                "WARNING" \
                "$subsystem" \
                "INTERACTIVE_NO_REMEDIATION" \
                "result=ATTENTION"


            return 1
            ;;


        3)

            fail "Remediation result is UNKNOWN"

            return 3
            ;;


        2)

            fail "Remediation failed"

            return 2
            ;;


        1)

            warn "Remediation did not reach a verified success state"

            return 1
            ;;


        0)
            ;;

    esac


    #
    # ------------------------------------------------------------
    # VERIFY
    # ------------------------------------------------------------
    #

    interactive_ui_stage \
        "Verify" \
        "$subsystem_label"


    "$verify_function"

    local verify_rc=$?


    if ! interactive_validate_rc \
        "$subsystem" \
        "verify" \
        "$verify_rc" \
        "0"
    then

        fail "Verification outcome cannot be trusted"

        return 3
    fi


    case "$verify_rc" in

        0)
            return 0
            ;;

        1)
            return 1
            ;;

        2)
            return 2
            ;;

        3)
            return 3
            ;;

    esac


    return 3
}


#
# ------------------------------------------------------------
# INTERACTIVE ALL
# ------------------------------------------------------------
#

interactive_run_all() {

    local cpu_rc=3
    local memory_rc=3

    local disk_rc=3
    local network_rc=3

    local fd_rc=3


    #
    # This progress represents completed subsystem workflows.
    #
    # 0/5 → none completed
    # 5/5 → all five completed
    #
    # It is not a health score.
    #

    interactive_ui_progress \
        0 \
        5 \
        "Workflow"


    interactive_run_one "cpu"
    cpu_rc=$?


    interactive_ui_progress \
        1 \
        5 \
        "Workflow"


    interactive_run_one "memory"
    memory_rc=$?


    interactive_ui_progress \
        2 \
        5 \
        "Workflow"


    interactive_run_one "disk"
    disk_rc=$?


    interactive_ui_progress \
        3 \
        5 \
        "Workflow"


    interactive_run_one "network"
    network_rc=$?


    interactive_ui_progress \
        4 \
        5 \
        "Workflow"


    interactive_run_one "fd"
    fd_rc=$?


    interactive_ui_progress \
        5 \
        5 \
        "Workflow"


    #
    # Defensive normalization
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

            0|1|2|3)
                ;;


            *)

                fail "Unexpected interactive aggregate result: $rc"

                ;;

        esac

    done


    #
    # Save results for reporting.
    #

    LPD_RESULT_CPU="$cpu_rc"
    LPD_RESULT_MEMORY="$memory_rc"

    LPD_RESULT_DISK="$disk_rc"
    LPD_RESULT_NETWORK="$network_rc"

    LPD_RESULT_FD="$fd_rc"


    section "Interactive Summary"


    if interactive_ui_enabled &&
       declare -F lpd_ui_summary_header >/dev/null 2>&1 &&
       declare -F lpd_ui_status >/dev/null 2>&1
    then

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

    else

        printf "%-20s %-12s\n" \
            "Subsystem" \
            "Result"


        printf "%-20s %-12s\n" \
            "--------------------" \
            "------------"


        printf "%-20s %-12s\n" \
            "CPU" \
            "$(interactive_result_label "$cpu_rc")"


        printf "%-20s %-12s\n" \
            "Memory" \
            "$(interactive_result_label "$memory_rc")"


        printf "%-20s %-12s\n" \
            "Disk" \
            "$(interactive_result_label "$disk_rc")"


        printf "%-20s %-12s\n" \
            "Network" \
            "$(interactive_result_label "$network_rc")"


        printf "%-20s %-12s\n" \
            "File Descriptors" \
            "$(interactive_result_label "$fd_rc")"

    fi


    #
    # UNKNOWN > FAILED > ATTENTION > HEALTHY
    #

    local overall=0


    for rc in \
        "$cpu_rc" \
        "$memory_rc" \
        "$disk_rc" \
        "$network_rc" \
        "$fd_rc"
    do

        if (( rc == 3 )); then

            overall=3

            break
        fi


        if (( rc == 2 )); then

            if (( overall < 2 )); then
                overall=2
            fi

            continue
        fi


        if (( rc == 1 )); then

            if (( overall < 1 )); then
                overall=1
            fi

        fi

    done


    echo


    if interactive_ui_enabled &&
       declare -F lpd_ui_overall >/dev/null 2>&1
    then

        lpd_ui_overall \
            "$overall"

    else

        case "$overall" in

            0)
                ok "Overall interactive status: HEALTHY"
                ;;

            1)
                warn "Overall interactive status: ATTENTION"
                ;;

            2)
                fail "Overall interactive status: FAILED"
                ;;

            3)
                fail "Overall interactive status: UNKNOWN"
                ;;

        esac

    fi


    return "$overall"
}


#
# ------------------------------------------------------------
# SAVE SINGLE TARGET RESULT
# ------------------------------------------------------------
#

interactive_save_single_result() {

    local target="${1:-}"
    local rc="${2:-3}"


    case "$target" in

        cpu)
            LPD_RESULT_CPU="$rc"
            ;;

        memory)
            LPD_RESULT_MEMORY="$rc"
            ;;

        disk)
            LPD_RESULT_DISK="$rc"
            ;;

        network)
            LPD_RESULT_NETWORK="$rc"
            ;;

        fd)
            LPD_RESULT_FD="$rc"
            ;;

    esac
}


#
# ------------------------------------------------------------
# GENERATE REPORT
# ------------------------------------------------------------
#

interactive_generate_report() {

    if ! declare -F lpd_report_generate >/dev/null 2>&1; then

        fail "Reporting module is unavailable"

        return 1
    fi


    if ! lpd_report_generate; then

        lpd_audit \
            "ERROR" \
            "report" \
            "REPORT_GENERATION_FAILED" \
            "command=interactive"


        return 1
    fi


    return 0
}


#
# ------------------------------------------------------------
# ENTRY POINT
# ------------------------------------------------------------
#

interactive_run() {

    local target="${1:-}"


    interactive_ui_banner


    local rc=3


    case "$target" in

        cpu|memory|disk|network|fd)

            interactive_run_one "$target"

            rc=$?


            interactive_save_single_result \
                "$target" \
                "$rc"
            ;;


        all)

            interactive_run_all

            rc=$?
            ;;


        "")

            fail "Usage: ./lpd.sh interactive [cpu|memory|disk|network|fd|all]"

            rc=3
            ;;


        *)

            fail "Unknown interactive target: $target"

            fail "Usage: ./lpd.sh interactive [cpu|memory|disk|network|fd|all]"

            rc=3
            ;;

    esac


    #
    # Save final workflow result BEFORE creating report.
    #

    LPD_OVERALL_EXIT_CODE="$rc"


    if declare -F lpd_report_overall_from_code >/dev/null 2>&1; then

        LPD_OVERALL_STATUS=$(
            lpd_report_overall_from_code \
                "$rc"
        )

    else

        case "$rc" in

            0)
                LPD_OVERALL_STATUS="HEALTHY"
                ;;

            1)
                LPD_OVERALL_STATUS="ATTENTION_REQUIRED"
                ;;

            2)
                LPD_OVERALL_STATUS="FAILED"
                ;;

            *)
                LPD_OVERALL_STATUS="UNKNOWN"
                ;;

        esac

    fi


    #
    # A reporting failure is a tool failure.
    #
    # Do not silently claim the whole workflow succeeded if
    # required reports could not be generated.
    #

    if ! interactive_generate_report; then

        LPD_OVERALL_EXIT_CODE=3
        LPD_OVERALL_STATUS="UNKNOWN"

        return 3
    fi


    return "$rc"
}
