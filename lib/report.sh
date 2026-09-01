#!/usr/bin/env bash


#
# ------------------------------------------------------------
# STATUS HELPERS
# ------------------------------------------------------------
#

lpd_report_status_from_code() {

    local code="${1:-}"

    case "$code" in
        0) echo "HEALTHY" ;;
        1) echo "ATTENTION" ;;
        2) echo "FAILED" ;;
        3) echo "UNKNOWN" ;;
        *) echo "NOT_RUN" ;;
    esac
}


lpd_report_overall_from_code() {

    local code="${1:-}"

    case "$code" in
        0) echo "HEALTHY" ;;
        1) echo "ATTENTION_REQUIRED" ;;
        2) echo "FAILED" ;;
        3) echo "UNKNOWN" ;;
        *) echo "UNKNOWN" ;;
    esac
}


lpd_report_json_exit_code() {

    local code="${1:-}"

    if [[ "$code" =~ ^[0-9]+$ ]]; then
        printf "%s" "$code"
    else
        printf "null"
    fi
}


lpd_report_exit_display() {

    local code="${1:-}"

    if [[ "$code" =~ ^[0-9]+$ ]]; then
        printf "%s" "$code"
    else
        printf "-"
    fi
}


lpd_json_number() {

    local value="${1:-}"

    if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        printf "%s" "$value"
    else
        printf "null"
    fi
}


lpd_json_escape() {

    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"

    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf "%s" "$value"
}


lpd_json_nullable_string() {

    local value="${1:-}"

    case "$value" in
        ""|N/A)
            printf "null"
            ;;

        *)
            printf '"%s"' "$(lpd_json_escape "$value")"
            ;;
    esac
}


#
# ------------------------------------------------------------
# EXECUTION / COVERAGE HELPERS
# ------------------------------------------------------------
#

lpd_report_executed_json() {

    local code="${1:-}"

    if [[ "$code" =~ ^[0-3]$ ]]; then
        printf "true"
    else
        printf "false"
    fi
}


lpd_report_executed_display() {

    local code="${1:-}"

    if [[ "$code" =~ ^[0-3]$ ]]; then
        printf "YES"
    else
        printf "NO"
    fi
}


lpd_report_scope() {

    local count=0
    local scope="none"


    if [[ "${LPD_RESULT_CPU:-}" =~ ^[0-3]$ ]]; then
        count=$((count + 1))
        scope="cpu"
    fi

    if [[ "${LPD_RESULT_MEMORY:-}" =~ ^[0-3]$ ]]; then
        count=$((count + 1))
        scope="memory"
    fi

    if [[ "${LPD_RESULT_DISK:-}" =~ ^[0-3]$ ]]; then
        count=$((count + 1))
        scope="disk"
    fi

    if [[ "${LPD_RESULT_NETWORK:-}" =~ ^[0-3]$ ]]; then
        count=$((count + 1))
        scope="network"
    fi

    if [[ "${LPD_RESULT_FD:-}" =~ ^[0-3]$ ]]; then
        count=$((count + 1))
        scope="fd"
    fi


    case "$count" in

        0)
            printf "none"
            ;;

        1)
            printf "%s" "$scope"
            ;;

        5)
            printf "all"
            ;;

        *)
            printf "partial"
            ;;

    esac
}


lpd_report_full_system_json() {

    if [[ "$(lpd_report_scope)" == "all" ]]; then
        printf "true"
    else
        printf "false"
    fi
}


lpd_report_full_system_display() {

    if [[ "$(lpd_report_scope)" == "all" ]]; then
        printf "YES"
    else
        printf "NO"
    fi
}


lpd_report_run_mode() {

    local command="${LPD_RUN_COMMAND:-}"
    local mode="unknown"

    read -r mode _ <<< "$command"

    printf "%s" "${mode:-unknown}"
}


#
# ------------------------------------------------------------
# EFFECTIVE THRESHOLDS
# ------------------------------------------------------------
#

lpd_report_threshold_keys() {

    cat <<'EOF'
CPU_BUSY_WARN_PCT
CPU_BUSY_CRITICAL_PCT
CPU_LOAD_PER_CPU_WARN
CPU_LOAD_PER_CPU_CRITICAL
CPU_PROCESS_SATURATION_PCT
CPU_PSI_WARN_PCT
CPU_PSI_CRITICAL_PCT
CPU_VERIFY_HEALTHY_BUSY_PCT
MEM_AVAILABLE_WARN_PCT
MEM_AVAILABLE_SWAP_CRITICAL_PCT
MEM_AVAILABLE_CRITICAL_PCT
MEM_SWAP_ACTIVITY_WARN_KB
MEM_SWAP_ACTIVITY_CRITICAL_KB
MEM_PSI_SOME_WARN_PCT
MEM_PSI_SOME_CRITICAL_PCT
MEM_PSI_FULL_CRITICAL_PCT
MEM_PROCESS_MEDIUM_CONFIDENCE_PCT
MEM_PROCESS_HIGH_CONFIDENCE_PCT
MEM_PROCESS_REMEDIATE_MIN_PCT
MEM_VERIFY_MIN_AVAILABLE_PCT
MEM_VERIFY_MAX_PSI_PCT
MEM_VERIFY_MAX_SWAP_KB
MEM_MITIGATION_IMPROVEMENT_PCT
FS_USAGE_WARN_PCT
FS_USAGE_CRITICAL_PCT
FS_INODE_WARN_PCT
FS_INODE_CRITICAL_PCT
DISK_UTIL_WARN_PCT
DISK_UTIL_CRITICAL_PCT
DISK_AWAIT_WARN_MS
DISK_AWAIT_CRITICAL_MS
DISK_QUEUE_WARN
DISK_QUEUE_CRITICAL
DISK_CULPRIT_MEDIUM_KBPS
DISK_CULPRIT_HIGH_KBPS
NETWORK_TIME_WAIT_WARN
NETWORK_TIME_WAIT_CRITICAL
NETWORK_RETRANS_WARN
NETWORK_RETRANS_CRITICAL
NETWORK_SYN_WARN
NETWORK_SYN_CRITICAL
NETWORK_CONNECT_WARN_5S
NETWORK_CONNECT_CRITICAL_5S
NETWORK_TOP_CONNECT_MEDIUM_5S
NETWORK_TOP_CONNECT_HIGH_5S
NETWORK_VERIFY_CONNECT_MAX_3S
FD_PROCESS_WARN_PCT
FD_PROCESS_CRITICAL_PCT
FD_SYSTEM_WARN_PCT
FD_SYSTEM_CRITICAL_PCT
EOF
}


lpd_report_threshold_value() {

    local key="${1:-}"

    [[ -n "$key" ]] || {
        printf "N/A"
        return 0
    }


    local value=""

    value="${!key-}"


    if [[ -n "$value" ]]; then
        printf "%s" "$value"
    else
        printf "N/A"
    fi
}


#
# ------------------------------------------------------------
# REMEDIATION METADATA
# ------------------------------------------------------------
#

lpd_report_reversible_display() {

    local action="${1:-}"

    case "$action" in
        IONICE) printf "YES" ;;
        SIGTERM) printf "NO" ;;
        *) printf "N/A" ;;
    esac
}


lpd_report_reversible_json() {

    local action="${1:-}"

    case "$action" in
        IONICE) printf "true" ;;
        SIGTERM) printf "false" ;;
        *) printf "null" ;;
    esac
}


lpd_report_rollback_from_record() {

    local action="${1:-}"
    local after="${2:-}"

    local rollback_regex='(^|;)rollback=([^;]+)'


    if [[ "$after" =~ $rollback_regex ]]; then

        printf "%s" "${BASH_REMATCH[2]}"

        return 0
    fi


    case "$action" in
        SIGTERM) printf "NOT_REVERSIBLE" ;;
        IONICE) printf "NOT_RECORDED" ;;
        *) printf "NOT_APPLICABLE" ;;
    esac
}


#
# ------------------------------------------------------------
# MARKDOWN REPORT
# ------------------------------------------------------------
#

lpd_report_write_markdown() {

    local file="$1"
    local finished_at="$2"
    local duration="$3"
    local actions="$4"
    local remediations="$5"

    local cpu_status=""
    local memory_status=""
    local disk_status=""
    local network_status=""
    local fd_status=""

    local scope=""
    local run_mode=""


    cpu_status=$(
        lpd_report_status_from_code "${LPD_RESULT_CPU:-}"
    )

    memory_status=$(
        lpd_report_status_from_code "${LPD_RESULT_MEMORY:-}"
    )

    disk_status=$(
        lpd_report_status_from_code "${LPD_RESULT_DISK:-}"
    )

    network_status=$(
        lpd_report_status_from_code "${LPD_RESULT_NETWORK:-}"
    )

    fd_status=$(
        lpd_report_status_from_code "${LPD_RESULT_FD:-}"
    )

    scope=$(
        lpd_report_scope
    )

    run_mode=$(
        lpd_report_run_mode
    )


    {
        echo "# Linux Performance Detective Report"
        echo

        echo "## Run Information"
        echo

        printf -- "- **LPD Version:** \`%s\`\n" \
            "${LPD_VERSION:-unknown}"

        printf -- "- **Run ID:** \`%s\`\n" \
            "$LPD_RUN_ID"

        printf -- "- **Started:** %s\n" \
            "$LPD_RUN_START_TIME"

        printf -- "- **Finished:** %s\n" \
            "$finished_at"

        printf -- "- **Duration:** %s seconds\n" \
            "$duration"

        printf -- "- **Command:** \`%s\`\n" \
            "$LPD_RUN_COMMAND"

        printf -- "- **Mode:** \`%s\`\n" \
            "$run_mode"

        printf -- "- **Scope:** \`%s\`\n" \
            "$scope"

        printf -- "- **Full-system coverage:** %s\n" \
            "$(lpd_report_full_system_display)"

        printf -- "- **Final Exit Code:** %s\n" \
            "$(lpd_report_exit_display "${LPD_OVERALL_EXIT_CODE:-}")"


        echo
        echo "## System"
        echo

        printf -- "- **Host:** %s\n" "$LPD_RUN_HOST"
        printf -- "- **OS:** %s\n" "$LPD_RUN_OS"
        printf -- "- **Kernel:** %s\n" "$LPD_RUN_KERNEL"
        printf -- "- **Architecture:** %s\n" "$LPD_RUN_ARCH"
        printf -- "- **User:** %s\n" "$LPD_RUN_USER"


        echo
        echo "## Configuration"
        echo

        printf -- "- **Config file:** \`%s\`\n" \
            "${LPD_CONFIG_FILE:-N/A}"

        echo
        echo "### Effective Thresholds"
        echo

        echo "| Setting | Effective Value |"
        echo "|---|---:|"


        local threshold_key=""

        while read -r threshold_key; do

            [[ -n "$threshold_key" ]] || continue

            printf "| \`%s\` | %s |\n" \
                "$threshold_key" \
                "$(lpd_report_threshold_value "$threshold_key")"

        done < <(
            lpd_report_threshold_keys
        )


        echo
        echo "## Overall Result"
        echo

        printf "**%s**\n" \
            "${LPD_OVERALL_STATUS:-UNKNOWN}"

        echo
        printf "Coverage scope: **%s**. Full-system coverage: **%s**.\n" \
            "$scope" \
            "$(lpd_report_full_system_display)"


        echo
        echo "## Subsystem Results"
        echo

        echo "| Subsystem | Executed | Status | Exit Code |"
        echo "|---|---:|---:|---:|"

        printf "| CPU | %s | %s | %s |\n" \
            "$(lpd_report_executed_display "${LPD_RESULT_CPU:-}")" \
            "$cpu_status" \
            "$(lpd_report_exit_display "${LPD_RESULT_CPU:-}")"

        printf "| Memory | %s | %s | %s |\n" \
            "$(lpd_report_executed_display "${LPD_RESULT_MEMORY:-}")" \
            "$memory_status" \
            "$(lpd_report_exit_display "${LPD_RESULT_MEMORY:-}")"

        printf "| Disk | %s | %s | %s |\n" \
            "$(lpd_report_executed_display "${LPD_RESULT_DISK:-}")" \
            "$disk_status" \
            "$(lpd_report_exit_display "${LPD_RESULT_DISK:-}")"

        printf "| Network | %s | %s | %s |\n" \
            "$(lpd_report_executed_display "${LPD_RESULT_NETWORK:-}")" \
            "$network_status" \
            "$(lpd_report_exit_display "${LPD_RESULT_NETWORK:-}")"

        printf "| File Descriptors | %s | %s | %s |\n" \
            "$(lpd_report_executed_display "${LPD_RESULT_FD:-}")" \
            "$fd_status" \
            "$(lpd_report_exit_display "${LPD_RESULT_FD:-}")"


        echo
        echo "## Post-Run Evidence Snapshot"
        echo

        echo "These metrics were collected after the troubleshooting workflow completed."
        echo
        echo "Evidence collection is supplemental and does not imply that the related subsystem workflow was executed."


        echo
        echo "### CPU"
        echo

        printf -- "- CPU count: %s\n" \
            "${LPD_EVIDENCE_CPU_COUNT:-N/A}"

        printf -- "- CPU busy: %s%%\n" \
            "${LPD_EVIDENCE_CPU_BUSY:-N/A}"

        printf -- "- 1-minute load: %s\n" \
            "${LPD_EVIDENCE_CPU_LOAD1:-N/A}"

        printf -- "- CPU PSI avg10: %s%%\n" \
            "${LPD_EVIDENCE_CPU_PSI:-N/A}"

        printf -- "- Top stable process: %s (PID %s, %s%% CPU)\n" \
            "${LPD_EVIDENCE_CPU_TOP_COMMAND:-N/A}" \
            "${LPD_EVIDENCE_CPU_TOP_PID:-N/A}" \
            "${LPD_EVIDENCE_CPU_TOP_USAGE:-N/A}"


        echo
        echo "### Memory"
        echo

        printf -- "- Memory available: %s%%\n" \
            "${LPD_EVIDENCE_MEMORY_AVAILABLE:-N/A}"

        printf -- "- Swap used: %s%%\n" \
            "${LPD_EVIDENCE_MEMORY_SWAP_USED:-N/A}"

        printf -- "- Memory PSI some avg10: %s%%\n" \
            "${LPD_EVIDENCE_MEMORY_PSI_SOME:-N/A}"

        printf -- "- Memory PSI full avg10: %s%%\n" \
            "${LPD_EVIDENCE_MEMORY_PSI_FULL:-N/A}"

        printf -- "- Largest stable RSS process: %s (PID %s, %s%%, %s MB RSS)\n" \
            "${LPD_EVIDENCE_MEMORY_TOP_COMMAND:-N/A}" \
            "${LPD_EVIDENCE_MEMORY_TOP_PID:-N/A}" \
            "${LPD_EVIDENCE_MEMORY_TOP_PERCENT:-N/A}" \
            "${LPD_EVIDENCE_MEMORY_TOP_RSS_MB:-N/A}"


        echo
        echo "### Disk"
        echo

        printf -- "- Root filesystem usage: %s%%\n" \
            "${LPD_EVIDENCE_ROOT_USAGE:-N/A}"

        printf -- "- Project filesystem usage: %s%%\n" \
            "${LPD_EVIDENCE_LAB_USAGE:-N/A}"

        printf -- "- Device: %s\n" \
            "${LPD_EVIDENCE_DISK_DEVICE:-N/A}"

        printf -- "- Utilization: %s%%\n" \
            "${LPD_EVIDENCE_DISK_UTIL:-N/A}"

        printf -- "- Read await: %s ms\n" \
            "${LPD_EVIDENCE_DISK_RAWAIT:-N/A}"

        printf -- "- Write await: %s ms\n" \
            "${LPD_EVIDENCE_DISK_WAWAIT:-N/A}"

        printf -- "- Queue depth: %s\n" \
            "${LPD_EVIDENCE_DISK_QUEUE:-N/A}"


        echo
        echo "### Network"
        echo

        printf -- "- ESTABLISHED: %s\n" \
            "${LPD_EVIDENCE_NETWORK_ESTABLISHED:-N/A}"

        printf -- "- TIME-WAIT: %s\n" \
            "${LPD_EVIDENCE_NETWORK_TIME_WAIT:-N/A}"

        printf -- "- SYN-SENT: %s\n" \
            "${LPD_EVIDENCE_NETWORK_SYN_SENT:-N/A}"

        printf -- "- SYN-RECV: %s\n" \
            "${LPD_EVIDENCE_NETWORK_SYN_RECV:-N/A}"

        printf -- "- Retransmission telemetry during diagnosis: %s\n" \
            "${LPD_EVIDENCE_NETWORK_RETRANS:-N/A}"

        printf -- "- eBPF trace status: %s\n" \
            "${LPD_EVIDENCE_NETWORK_TRACE_STATUS:-NOT_RUN}"

        printf -- "- Connections observed during diagnosis: %s\n" \
            "${LPD_EVIDENCE_NETWORK_CONNECTS:-N/A}"

        printf -- "- Top connector: %s (PID %s)\n" \
            "${LPD_EVIDENCE_NETWORK_TOP_COMMAND:-N/A}" \
            "${LPD_EVIDENCE_NETWORK_TOP_PID:-N/A}"


        echo
        echo "### File Descriptors"
        echo

        printf -- "- Highest-utilization process: %s (PID %s)\n" \
            "${LPD_EVIDENCE_FD_COMMAND:-N/A}" \
            "${LPD_EVIDENCE_FD_PID:-N/A}"

        printf -- "- Open descriptors: %s\n" \
            "${LPD_EVIDENCE_FD_COUNT:-N/A}"

        printf -- "- Soft limit: %s\n" \
            "${LPD_EVIDENCE_FD_SOFT:-N/A}"

        printf -- "- Limit utilization: %s%%\n" \
            "${LPD_EVIDENCE_FD_RATIO:-N/A}"


        echo
        echo "## Structured Remediation Records"
        echo


        if [[ -z "$remediations" ]]; then

            echo "No remediation or explicit no-action decision was recorded during this run."

        else

            echo "| Subsystem | Finding | Target | Action | Verification | Result | Reversible | Rollback |"
            echo "|---|---|---|---|---|---|---|---|"

            local timestamp=""
            local run_id=""
            local subsystem=""
            local finding=""
            local target_pid=""
            local target_command=""
            local action=""
            local before=""
            local after=""
            local verification=""
            local result=""
            local reversible=""
            local rollback=""


            while IFS='|' read -r \
                timestamp \
                run_id \
                subsystem \
                finding \
                target_pid \
                target_command \
                action \
                before \
                after \
                verification \
                result
            do

                [[ -n "$timestamp" ]] || continue

                reversible=$(
                    lpd_report_reversible_display "$action"
                )

                rollback=$(
                    lpd_report_rollback_from_record \
                        "$action" \
                        "$after"
                )

                printf "| %s | %s | %s (PID %s) | %s | %s | %s | %s | %s |\n" \
                    "$subsystem" \
                    "$finding" \
                    "$target_command" \
                    "$target_pid" \
                    "$action" \
                    "$verification" \
                    "$result" \
                    "$reversible" \
                    "$rollback"

            done <<< "$remediations"


            echo
            echo "### Remediation Evidence"
            echo

            local record_number=0


            while IFS='|' read -r \
                timestamp \
                run_id \
                subsystem \
                finding \
                target_pid \
                target_command \
                action \
                before \
                after \
                verification \
                result
            do

                [[ -n "$timestamp" ]] || continue

                record_number=$((record_number + 1))

                reversible=$(
                    lpd_report_reversible_display "$action"
                )

                rollback=$(
                    lpd_report_rollback_from_record \
                        "$action" \
                        "$after"
                )

                printf "#### Record %s — %s\n\n" \
                    "$record_number" \
                    "$subsystem"

                printf -- "- **Timestamp:** %s\n" "$timestamp"
                printf -- "- **Finding:** %s\n" "$finding"

                printf -- "- **Target:** %s (PID %s)\n" \
                    "$target_command" \
                    "$target_pid"

                printf -- "- **Action:** %s\n" "$action"
                printf -- "- **Before:** \`%s\`\n" "$before"
                printf -- "- **After:** \`%s\`\n" "$after"
                printf -- "- **Verification:** %s\n" "$verification"
                printf -- "- **Result:** %s\n" "$result"
                printf -- "- **Reversible:** %s\n" "$reversible"
                printf -- "- **Rollback:** %s\n" "$rollback"

                echo

            done <<< "$remediations"

        fi


        echo
        echo "## Action Log"
        echo

        if [[ -n "$actions" ]]; then

            echo '```text'
            printf "%s\n" "$actions"
            echo '```'

        else

            echo "No legacy action log entries were recorded during this run."

        fi


        echo
        echo "## Audit"
        echo

        echo "Audit events for this run are stored in:"
        echo

        printf "\`%s\`\n" "$LPD_AUDIT_LOG"

        echo
        echo "---"
        echo

        printf "Generated by Linux Performance Detective %s.\n" \
            "${LPD_VERSION:-unknown}"

    } > "$file"
}


#
# ------------------------------------------------------------
# JSON REPORT
# ------------------------------------------------------------
#

lpd_report_write_json() {

    local file="$1"
    local finished_at="$2"
    local duration="$3"
    local actions="$4"
    local remediations="$5"

    local cpu_status=""
    local memory_status=""
    local disk_status=""
    local network_status=""
    local fd_status=""

    local scope=""
    local run_mode=""


    cpu_status=$(
        lpd_report_status_from_code "${LPD_RESULT_CPU:-}"
    )

    memory_status=$(
        lpd_report_status_from_code "${LPD_RESULT_MEMORY:-}"
    )

    disk_status=$(
        lpd_report_status_from_code "${LPD_RESULT_DISK:-}"
    )

    network_status=$(
        lpd_report_status_from_code "${LPD_RESULT_NETWORK:-}"
    )

    fd_status=$(
        lpd_report_status_from_code "${LPD_RESULT_FD:-}"
    )

    scope=$(
        lpd_report_scope
    )

    run_mode=$(
        lpd_report_run_mode
    )


    {
        echo "{"

        printf '  "schema_version": 1,\n'


        #
        # RUN
        #

        printf '  "run": {\n'

        printf '    "id": "%s",\n' \
            "$(lpd_json_escape "$LPD_RUN_ID")"

        printf '    "version": "%s",\n' \
            "$(lpd_json_escape "${LPD_VERSION:-unknown}")"

        printf '    "started_at": "%s",\n' \
            "$(lpd_json_escape "$LPD_RUN_START_TIME")"

        printf '    "finished_at": "%s",\n' \
            "$(lpd_json_escape "$finished_at")"

        printf '    "duration_seconds": %s,\n' \
            "$duration"

        printf '    "command": "%s",\n' \
            "$(lpd_json_escape "$LPD_RUN_COMMAND")"

        printf '    "mode": "%s",\n' \
            "$(lpd_json_escape "$run_mode")"

        printf '    "target": "%s",\n' \
            "$(lpd_json_escape "$scope")"

        printf '    "exit_code": %s\n' \
            "$(lpd_report_json_exit_code "${LPD_OVERALL_EXIT_CODE:-}")"

        printf '  },\n'


        #
        # COVERAGE
        #

        printf '  "coverage": {\n'

        printf '    "scope": "%s",\n' \
            "$(lpd_json_escape "$scope")"

        printf '    "full_system": %s\n' \
            "$(lpd_report_full_system_json)"

        printf '  },\n'


        #
        # SYSTEM
        #

        printf '  "system": {\n'

        printf '    "host": "%s",\n' \
            "$(lpd_json_escape "$LPD_RUN_HOST")"

        printf '    "os": "%s",\n' \
            "$(lpd_json_escape "$LPD_RUN_OS")"

        printf '    "kernel": "%s",\n' \
            "$(lpd_json_escape "$LPD_RUN_KERNEL")"

        printf '    "architecture": "%s",\n' \
            "$(lpd_json_escape "$LPD_RUN_ARCH")"

        printf '    "user": "%s"\n' \
            "$(lpd_json_escape "$LPD_RUN_USER")"

        printf '  },\n'


        #
        # CONFIGURATION
        #

        printf '  "configuration": {\n'

        printf '    "file": %s,\n' \
            "$(lpd_json_nullable_string "${LPD_CONFIG_FILE:-}")"

        printf '    "effective_thresholds": {\n'


        local first_threshold=1
        local threshold_key=""
        local threshold_value=""


        while read -r threshold_key; do

            [[ -n "$threshold_key" ]] || continue

            threshold_value=$(
                lpd_report_threshold_value "$threshold_key"
            )


            if (( first_threshold == 0 )); then
                printf ',\n'
            fi


            printf '      "%s": %s' \
                "$(lpd_json_escape "$threshold_key")" \
                "$(lpd_json_number "$threshold_value")"

            first_threshold=0

        done < <(
            lpd_report_threshold_keys
        )


        if (( first_threshold == 0 )); then
            printf '\n'
        fi


        printf '    }\n'
        printf '  },\n'


        #
        # OVERALL RESULT
        #

        printf '  "overall_status": "%s",\n' \
            "$(lpd_json_escape "${LPD_OVERALL_STATUS:-UNKNOWN}")"


        #
        # SUBSYSTEM RESULTS
        #

        printf '  "subsystems": {\n'

        printf '    "cpu": {"executed": %s, "status": "%s", "exit_code": %s},\n' \
            "$(lpd_report_executed_json "${LPD_RESULT_CPU:-}")" \
            "$cpu_status" \
            "$(lpd_report_json_exit_code "${LPD_RESULT_CPU:-}")"

        printf '    "memory": {"executed": %s, "status": "%s", "exit_code": %s},\n' \
            "$(lpd_report_executed_json "${LPD_RESULT_MEMORY:-}")" \
            "$memory_status" \
            "$(lpd_report_json_exit_code "${LPD_RESULT_MEMORY:-}")"

        printf '    "disk": {"executed": %s, "status": "%s", "exit_code": %s},\n' \
            "$(lpd_report_executed_json "${LPD_RESULT_DISK:-}")" \
            "$disk_status" \
            "$(lpd_report_json_exit_code "${LPD_RESULT_DISK:-}")"

        printf '    "network": {"executed": %s, "status": "%s", "exit_code": %s},\n' \
            "$(lpd_report_executed_json "${LPD_RESULT_NETWORK:-}")" \
            "$network_status" \
            "$(lpd_report_json_exit_code "${LPD_RESULT_NETWORK:-}")"

        printf '    "file_descriptors": {"executed": %s, "status": "%s", "exit_code": %s}\n' \
            "$(lpd_report_executed_json "${LPD_RESULT_FD:-}")" \
            "$fd_status" \
            "$(lpd_report_json_exit_code "${LPD_RESULT_FD:-}")"

        printf '  },\n'


        #
        # POST-RUN EVIDENCE
        #
        # Evidence is a supplemental snapshot. Presence of
        # evidence does not mean the related workflow executed.
        #

        printf '  "evidence": {\n'


        printf '    "cpu": {\n'

        printf '      "cpu_count": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_CPU_COUNT:-}")"

        printf '      "busy_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_CPU_BUSY:-}")"

        printf '      "load_1m": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_CPU_LOAD1:-}")"

        printf '      "psi_avg10_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_CPU_PSI:-}")"

        printf '      "top_process": {"pid": %s, "command": %s, "cpu_percent": %s}\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_CPU_TOP_PID:-}")" \
            "$(lpd_json_nullable_string "${LPD_EVIDENCE_CPU_TOP_COMMAND:-}")" \
            "$(lpd_json_number "${LPD_EVIDENCE_CPU_TOP_USAGE:-}")"

        printf '    },\n'


        printf '    "memory": {\n'

        printf '      "available_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_MEMORY_AVAILABLE:-}")"

        printf '      "swap_used_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_MEMORY_SWAP_USED:-}")"

        printf '      "psi_some_avg10_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_MEMORY_PSI_SOME:-}")"

        printf '      "psi_full_avg10_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_MEMORY_PSI_FULL:-}")"

        printf '      "top_process": {"pid": %s, "command": %s, "memory_percent": %s, "rss_mb": %s}\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_MEMORY_TOP_PID:-}")" \
            "$(lpd_json_nullable_string "${LPD_EVIDENCE_MEMORY_TOP_COMMAND:-}")" \
            "$(lpd_json_number "${LPD_EVIDENCE_MEMORY_TOP_PERCENT:-}")" \
            "$(lpd_json_number "${LPD_EVIDENCE_MEMORY_TOP_RSS_MB:-}")"

        printf '    },\n'


        printf '    "disk": {\n'

        printf '      "root_usage_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_ROOT_USAGE:-}")"

        printf '      "project_filesystem_usage_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_LAB_USAGE:-}")"

        printf '      "device": %s,\n' \
            "$(lpd_json_nullable_string "${LPD_EVIDENCE_DISK_DEVICE:-}")"

        printf '      "util_percent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_DISK_UTIL:-}")"

        printf '      "read_await_ms": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_DISK_RAWAIT:-}")"

        printf '      "write_await_ms": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_DISK_WAWAIT:-}")"

        printf '      "queue_depth": %s\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_DISK_QUEUE:-}")"

        printf '    },\n'


        printf '    "network": {\n'

        printf '      "established": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_NETWORK_ESTABLISHED:-}")"

        printf '      "time_wait": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_NETWORK_TIME_WAIT:-}")"

        printf '      "syn_sent": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_NETWORK_SYN_SENT:-}")"

        printf '      "syn_recv": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_NETWORK_SYN_RECV:-}")"

        printf '      "retransmission_telemetry": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_NETWORK_RETRANS:-}")"

        printf '      "trace_status": "%s",\n' \
            "$(lpd_json_escape "${LPD_EVIDENCE_NETWORK_TRACE_STATUS:-NOT_RUN}")"

        printf '      "connections_observed": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_NETWORK_CONNECTS:-}")"

        printf '      "top_connector": {"pid": %s, "command": %s}\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_NETWORK_TOP_PID:-}")" \
            "$(lpd_json_nullable_string "${LPD_EVIDENCE_NETWORK_TOP_COMMAND:-}")"

        printf '    },\n'


        printf '    "file_descriptors": {\n'

        printf '      "highest_utilization_pid": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_FD_PID:-}")"

        printf '      "command": %s,\n' \
            "$(lpd_json_nullable_string "${LPD_EVIDENCE_FD_COMMAND:-}")"

        printf '      "open_descriptors": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_FD_COUNT:-}")"

        printf '      "soft_limit": %s,\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_FD_SOFT:-}")"

        printf '      "limit_utilization_percent": %s\n' \
            "$(lpd_json_number "${LPD_EVIDENCE_FD_RATIO:-}")"

        printf '    }\n'

        printf '  },\n'


        #
        # REMEDIATIONS
        #

        printf '  "remediations": [\n'


        local remediation_first=1

        local timestamp=""
        local run_id=""
        local subsystem=""
        local finding=""
        local target_pid=""
        local target_command=""
        local action=""
        local before=""
        local after=""
        local verification=""
        local result=""
        local rollback=""


        while IFS='|' read -r \
            timestamp \
            run_id \
            subsystem \
            finding \
            target_pid \
            target_command \
            action \
            before \
            after \
            verification \
            result
        do

            [[ -n "$timestamp" ]] || continue


            if (( remediation_first == 0 )); then
                printf ',\n'
            fi


            rollback=$(
                lpd_report_rollback_from_record \
                    "$action" \
                    "$after"
            )


            printf '    {\n'

            printf '      "timestamp": "%s",\n' \
                "$(lpd_json_escape "$timestamp")"

            printf '      "subsystem": "%s",\n' \
                "$(lpd_json_escape "$subsystem")"

            printf '      "finding": "%s",\n' \
                "$(lpd_json_escape "$finding")"

            printf '      "target": {"pid": %s, "command": %s},\n' \
                "$(lpd_json_number "$target_pid")" \
                "$(lpd_json_nullable_string "$target_command")"

            printf '      "action": "%s",\n' \
                "$(lpd_json_escape "$action")"

            printf '      "before": "%s",\n' \
                "$(lpd_json_escape "$before")"

            printf '      "after": "%s",\n' \
                "$(lpd_json_escape "$after")"

            printf '      "verification": "%s",\n' \
                "$(lpd_json_escape "$verification")"

            printf '      "result": "%s",\n' \
                "$(lpd_json_escape "$result")"

            printf '      "reversible": %s,\n' \
                "$(lpd_report_reversible_json "$action")"

            printf '      "rollback": "%s"\n' \
                "$(lpd_json_escape "$rollback")"

            printf '    }'

            remediation_first=0

        done <<< "$remediations"


        if (( remediation_first == 0 )); then
            printf '\n'
        fi


        printf '  ],\n'


        #
        # ACTIONS
        #

        printf '  "actions": [\n'


        local first_action=1
        local line=""


        while IFS= read -r line; do

            [[ -n "$line" ]] || continue


            if (( first_action == 0 )); then
                printf ',\n'
            fi


            printf '    "%s"' \
                "$(lpd_json_escape "$line")"

            first_action=0

        done <<< "$actions"


        if (( first_action == 0 )); then
            printf '\n'
        fi


        printf '  ],\n'


        printf '  "audit_log": "%s"\n' \
            "$(lpd_json_escape "$LPD_AUDIT_LOG")"

        echo "}"

    } > "$file"
}


#
# ------------------------------------------------------------
# GENERATE REPORT
# ------------------------------------------------------------
#

lpd_report_generate() {

    if ! mkdir -p "$ROOT_DIR/reports"; then

        fail "Unable to create report directory"

        return 1
    fi


    if [[ ! -w "$ROOT_DIR/reports" ]]; then

        fail "Report directory is not writable: $ROOT_DIR/reports"

        return 1
    fi


    #
    # Overall result must already be known.
    #

    if [[ ! "${LPD_OVERALL_EXIT_CODE:-}" =~ ^[0-3]$ ]]; then
        LPD_OVERALL_EXIT_CODE=3
    fi


    if [[ -z "${LPD_OVERALL_STATUS:-}" ]]; then

        LPD_OVERALL_STATUS=$(
            lpd_report_overall_from_code \
                "$LPD_OVERALL_EXIT_CODE"
        )
    fi


    #
    # Post-run evidence is supplemental.
    #
    # Failure is recorded, but the report is still created with
    # null/N/A fields rather than invented measurements.
    #

    if ! lpd_collect_all_evidence; then

        warn "Post-run evidence collection was incomplete"

        lpd_audit \
            "WARNING" \
            "evidence" \
            "EVIDENCE_FAILED" \
            "post-run evidence collection incomplete"
    fi


    local finished_epoch=0
    local finished_at=""
    local duration=0


    finished_epoch=$(
        date '+%s'
    )

    finished_at=$(
        date '+%Y-%m-%dT%H:%M:%S%z'
    )


    if [[ "${LPD_RUN_START_EPOCH:-}" =~ ^[0-9]+$ ]]; then

        duration=$(( \
            finished_epoch - \
            LPD_RUN_START_EPOCH \
        ))

        if (( duration < 0 )); then
            duration=0
        fi
    fi


    local actions=""

    actions=$(
        lpd_actions_since_start
    )


    local remediations=""

    remediations=$(
        lpd_remediations_since_start
    )


    LPD_REPORT_MD="$ROOT_DIR/reports/lpd-${LPD_RUN_ID}.md"
    LPD_REPORT_JSON="$ROOT_DIR/reports/lpd-${LPD_RUN_ID}.json"


    if ! lpd_report_write_markdown \
        "$LPD_REPORT_MD" \
        "$finished_at" \
        "$duration" \
        "$actions" \
        "$remediations"
    then

        fail "Markdown report generation failed"

        return 1
    fi


    if ! lpd_report_write_json \
        "$LPD_REPORT_JSON" \
        "$finished_at" \
        "$duration" \
        "$actions" \
        "$remediations"
    then

        fail "JSON report generation failed"

        return 1
    fi


    lpd_audit \
        "INFO" \
        "report" \
        "REPORT_CREATED" \
        "markdown=$LPD_REPORT_MD json=$LPD_REPORT_JSON exit_code=$LPD_OVERALL_EXIT_CODE status=$LPD_OVERALL_STATUS scope=$(lpd_report_scope)"


    section "Reports"

    ok "Markdown report: $LPD_REPORT_MD"
    ok "JSON report:     $LPD_REPORT_JSON"

    return 0
}
