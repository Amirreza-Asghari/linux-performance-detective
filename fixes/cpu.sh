#!/usr/bin/env bash


cpu_remediate() {

    section "CPU Remediation"


    local pid="${LPD_CPU_PID:-N/A}"
    local command="${LPD_CPU_COMMAND:-N/A}"
    local cpu_usage="${LPD_CPU_USAGE:-N/A}"
    local expected_start="${LPD_CPU_PID_START:-N/A}"


    printf "Target PID:          %s\n" "$pid"
    printf "Command:             %s\n" "$command"
    printf "CPU usage:           %s%%\n" "$cpu_usage"

    echo


    #
    # ------------------------------------------------------------
    # SAFETY
    # ------------------------------------------------------------
    #

    if ! lpd_pid_identity_valid \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        warn "The diagnosed process is no longer safely identifiable."

        info "Automatic remediation has been blocked."

        LPD_CPU_ACTION="STALE_PID"

        return 10
    fi


    if (( pid == $$ || pid == PPID )); then

        warn "LPD will not terminate itself or its parent shell."

        LPD_CPU_ACTION="PROTECTED"

        return 10
    fi


    if lpd_process_is_protected "$command"; then

        warn "Process $pid ($command) is system-sensitive."

        info "Automatic termination will not be offered."

        LPD_CPU_ACTION="PROTECTED"

        return 10
    fi


    #
    # ------------------------------------------------------------
    # MENU
    # ------------------------------------------------------------
    #

    echo "Available actions:"
    echo
    echo "  1) Inspect process"
    echo "  2) Send SIGTERM (graceful termination)"
    echo "  3) Skip"
    echo


    local choice=""

    read -r -p "Select action [1-3]: " choice


    case "$choice" in

        1)

            echo

            ps -fp "$pid"

            echo

            if [[ -r "/proc/$pid/status" ]]; then

                grep -E \
                    '^(Name|State|Pid|PPid|Threads|VmRSS|VmSize):' \
                    "/proc/$pid/status" \
                    2>/dev/null ||
                    true

            fi


            LPD_CPU_ACTION="INSPECT"

            return 10
            ;;


        2)

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

                    LPD_CPU_ACTION="CANCELLED"

                    return 10
                    ;;

            esac


            #
            # ----------------------------------------------------
            # FINAL IDENTITY CHECK
            # ----------------------------------------------------
            #
            # Never trust an old PID after user interaction.
            #

            if ! lpd_signal_target_safe \
                "$pid" \
                "$expected_start" \
                "$command"
            then

                fail "Process identity changed before remediation."

                fail "SIGTERM blocked to avoid affecting the wrong process."

                LPD_CPU_ACTION="SAFETY_ABORT"

                return 3
            fi


            mkdir -p "$ROOT_DIR/logs"


            printf "%s CPU SIGTERM pid=%s command=%s cpu=%s\n" \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$pid" \
                "$command" \
                "$cpu_usage" \
                >> "$ROOT_DIR/logs/actions.log"


            if kill -TERM "$pid" 2>/dev/null; then

                ok "SIGTERM sent to process $pid"

                LPD_CPU_ACTION="SIGTERM"

                return 0

            fi


            fail "Failed to send SIGTERM to process $pid"

            return 2
            ;;


        3)

            info "Remediation skipped"

            LPD_CPU_ACTION="SKIP"

            return 10
            ;;


        *)

            fail "Invalid selection"

            return 3
            ;;

    esac
}
