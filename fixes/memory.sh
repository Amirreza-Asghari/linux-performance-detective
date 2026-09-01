#!/usr/bin/env bash


memory_remediate() {

    section "Memory Remediation"


    local remediate_min="${MEM_PROCESS_REMEDIATE_MIN_PCT:-20}"


    local pid="${LPD_MEMORY_PID:-N/A}"
    local command="${LPD_MEMORY_COMMAND:-N/A}"

    local process_pct="${LPD_MEMORY_PROCESS_PCT:-0}"

    local confidence="${LPD_MEMORY_CONFIDENCE:-LOW}"

    local expected_start="${LPD_MEMORY_PID_START:-N/A}"


    printf "Target:\n"

    printf "PID:                 %s\n" "$pid"
    printf "Command:             %s\n" "$command"

    printf "Memory usage:        %s%%\n" "$process_pct"
    printf "Confidence:          %s\n" "$confidence"

    echo


    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then

        warn "No valid process target is available."

        LPD_MEMORY_ACTION="NO_TARGET"

        return 10
    fi


    if ! lpd_pid_identity_valid \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        warn "The diagnosed process is no longer safely identifiable."

        info "Automatic remediation has been blocked."

        LPD_MEMORY_ACTION="STALE_PID"

        return 10
    fi


    if (( pid == $$ || pid == PPID )); then

        warn "LPD will not terminate itself or its parent shell."

        LPD_MEMORY_ACTION="PROTECTED"

        return 10
    fi


    local allow_termination=1


    if lpd_process_is_protected "$command"; then

        allow_termination=0

        warn "Process $pid ($command) is system-sensitive."

        info "Automatic termination will not be offered."

    fi


    if ! awk \
        -v pct="$process_pct" \
        -v threshold="$remediate_min" \
        'BEGIN {
            if (pct >= threshold)
                exit 0

            exit 1
        }'
    then

        allow_termination=0

        warn "The largest process does not account for enough memory to justify automatic termination."

    fi


    echo "Available actions:"

    echo


    if (( allow_termination == 1 )); then

        echo "  1) Inspect process"
        echo "  2) Send SIGTERM (graceful termination)"
        echo "  3) Skip"

    else

        echo "  1) Inspect process"
        echo "  2) Skip"

    fi


    echo


    local choice=""

    read -r -p "Select action: " choice


    if [[ "$choice" == "1" ]]; then

        echo

        ps -fp "$pid"

        echo


        if [[ -r "/proc/$pid/status" ]]; then

            grep -E \
                '^(Name|State|Pid|PPid|Threads|VmRSS|VmSize|VmSwap):' \
                "/proc/$pid/status" \
                2>/dev/null ||
                true

        fi


        LPD_MEMORY_ACTION="INSPECT"

        return 10
    fi


    if (( allow_termination == 1 )); then

        if [[ "$choice" == "2" ]]; then

            echo

            warn "This action will request process $pid ($command) to terminate."

            warn "This may interrupt an application, job or service."

            echo


            local confirmation=""

            read -r -p "Apply this remediation? [y/N]: " confirmation


            case "$confirmation" in

                y|Y|yes|YES)
                    ;;

                *)

                    info "Remediation cancelled"

                    LPD_MEMORY_ACTION="CANCELLED"

                    return 10
                    ;;

            esac


            if ! lpd_signal_target_safe \
                "$pid" \
                "$expected_start" \
                "$command"
            then

                fail "Process identity changed before remediation."

                fail "SIGTERM blocked to avoid affecting the wrong process."

                LPD_MEMORY_ACTION="SAFETY_ABORT"

                return 3
            fi


            mkdir -p "$ROOT_DIR/logs"


            printf "%s MEMORY SIGTERM pid=%s command=%s memory=%s confidence=%s\n" \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$pid" \
                "$command" \
                "$process_pct" \
                "$confidence" \
                >> "$ROOT_DIR/logs/actions.log"


            if kill -TERM "$pid" 2>/dev/null; then

                ok "SIGTERM sent to process $pid"

                LPD_MEMORY_ACTION="SIGTERM"

                return 0
            fi


            fail "Failed to send SIGTERM to process $pid"

            return 2
        fi


        if [[ "$choice" == "3" ]]; then

            info "Remediation skipped"

            LPD_MEMORY_ACTION="SKIP"

            return 10
        fi


    else

        if [[ "$choice" == "2" ]]; then

            info "Remediation skipped"

            LPD_MEMORY_ACTION="SKIP"

            return 10
        fi

    fi


    fail "Invalid selection"

    return 3
}
