#!/usr/bin/env bash


cpu_remediate() {

    section "CPU Remediation"


    local pid="${LPD_CPU_PID:-N/A}"
    local command="${LPD_CPU_COMMAND:-N/A}"
    local cpu_usage="${LPD_CPU_USAGE:-N/A}"
    local expected_start="${LPD_CPU_PID_START:-N/A}"

    local saturation_count="${LPD_CPU_SATURATION_COUNT:-1}"


    printf "Target PID:          %s\n" "$pid"
    printf "Command:             %s\n" "$command"
    printf "CPU usage:           %s%%\n" "$cpu_usage"
    printf "Saturated processes: %s\n" "$saturation_count"

    echo


    #
    # ------------------------------------------------------------
    # MULTI-PROCESS SAFETY POLICY
    # ------------------------------------------------------------
    #
    # LPD intentionally does not translate a multi-process CPU
    # incident into a blind single-PID termination.
    #
    # Multiple CPU-heavy processes may belong to independent
    # workloads, services or process groups. A wider remediation
    # requires operator understanding of that relationship first.
    #

    if [[ "$saturation_count" =~ ^[0-9]+$ ]] &&
       (( saturation_count >= 2 )); then

        warn "Multi-process CPU saturation was diagnosed."

        warn "Single-PID automatic remediation has been blocked."

        info "Review the related workload, service, process group or parent process before taking action."


        # Consumed by the interactive workflow after this function returns.
        # shellcheck disable=SC2034
        LPD_CPU_ACTION="MULTI_PROCESS_BLOCKED"


        return 10
    fi


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

        # Consumed by the interactive workflow after this function returns.
        # shellcheck disable=SC2034
        LPD_CPU_ACTION="STALE_PID"

        return 10
    fi


    if (( pid == $$ || pid == PPID )); then

        warn "LPD will not terminate itself or its parent shell."

        # Consumed by the interactive workflow after this function returns.
        # shellcheck disable=SC2034
        LPD_CPU_ACTION="PROTECTED"

        return 10
    fi


    if lpd_process_is_protected "$command"; then

        warn "Process $pid ($command) is system-sensitive."

        info "Automatic termination will not be offered."

        # Consumed by the interactive workflow after this function returns.
        # shellcheck disable=SC2034
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


            # Consumed by the interactive workflow after this function returns.
            # shellcheck disable=SC2034
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

                    # Consumed by the interactive workflow after this function returns.
                    # shellcheck disable=SC2034
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

                # Consumed by the interactive workflow after this function returns.
                # shellcheck disable=SC2034
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

                # Consumed by verification after this function returns.
                # shellcheck disable=SC2034
                LPD_CPU_ACTION="SIGTERM"

                return 0

            fi


            fail "Failed to send SIGTERM to process $pid"

            return 2
            ;;


        3)

            info "Remediation skipped"

            # Consumed by the interactive workflow after this function returns.
            # shellcheck disable=SC2034
            LPD_CPU_ACTION="SKIP"

            return 10
            ;;


        *)

            fail "Invalid selection"

            return 3
            ;;

    esac
}
