#!/usr/bin/env bash


#
# ------------------------------------------------------------
# NETWORK REMEDIATION
# ------------------------------------------------------------
#

network_remediate() {

    section "Network Remediation"


    local pid="${LPD_NETWORK_PID:-N/A}"
    local command="${LPD_NETWORK_COMMAND:-N/A}"

    local connection_count="${LPD_NETWORK_CONNECT_COUNT:-0}"
    local confidence="${LPD_NETWORK_CONFIDENCE:-LOW}"

    local expected_start="${LPD_NETWORK_PID_START:-N/A}"


    printf "Suspected PID:       %s\n" "$pid"
    printf "Command:             %s\n" "$command"
    printf "Sample connections:  %s\n" "$connection_count"
    printf "Confidence:          %s\n" "$confidence"

    echo


    #
    # ------------------------------------------------------------
    # NO TARGET
    # ------------------------------------------------------------
    #

    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then

        warn "No active connection-generating process was identified."

        info "Automatic remediation is unavailable."

        info "TIME-WAIT sockets should not be forcibly cleared."

        info "Recommendation: inspect application connection reuse and request rate."


        LPD_NETWORK_ACTION="RECOMMENDATION"


        return 10
    fi


    #
    # ------------------------------------------------------------
    # IDENTITY DATA MUST EXIST
    # ------------------------------------------------------------
    #

    if [[ "$expected_start" == "N/A" ||
          -z "$expected_start" ]]; then

        warn "Process identity information is incomplete."

        info "Automatic remediation has been blocked."


        LPD_NETWORK_ACTION="STALE_PID"


        return 10
    fi


    #
    # ------------------------------------------------------------
    # SHARED PID IDENTITY VALIDATION
    # ------------------------------------------------------------
    #
    # Never parse /proc/PID/stat locally.
    #
    # lib/safety.sh owns this logic and validates:
    #
    # - PID existence
    # - process starttime
    # - command identity
    # - zombie state
    # - PID reuse races
    #

    if ! lpd_pid_identity_valid \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        warn "The suspected process is no longer safely identifiable."

        info "Automatic remediation will not be attempted."


        LPD_NETWORK_ACTION="STALE_PID"


        return 10
    fi


    #
    # ------------------------------------------------------------
    # SELF / PARENT PROTECTION
    # ------------------------------------------------------------
    #

    if (( pid == $$ || pid == PPID )); then

        warn "LPD will not terminate its own process or parent shell."


        LPD_NETWORK_ACTION="PROTECTED"


        return 10
    fi


    #
    # ------------------------------------------------------------
    # SYSTEM-SENSITIVE PROCESS PROTECTION
    # ------------------------------------------------------------
    #

    if lpd_process_is_protected "$command"; then

        warn "Process $pid ($command) is system-sensitive."

        info "Automatic termination will not be offered."

        info "Recommendation: inspect the service and its network behavior manually."


        LPD_NETWORK_ACTION="PROTECTED"


        return 10
    fi


    #
    # ------------------------------------------------------------
    # CONFIDENCE POLICY
    # ------------------------------------------------------------
    #

    if [[ "$confidence" == "LOW" ]]; then

        warn "Culprit confidence is too low for automatic remediation."

        info "Use diagnosis evidence to investigate manually."


        LPD_NETWORK_ACTION="LOW_CONFIDENCE"


        return 10
    fi


    #
    # ------------------------------------------------------------
    # ACTION MENU
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

            #
            # Revalidate before inspecting process state.
            #

            if ! lpd_pid_identity_valid \
                "$pid" \
                "$expected_start" \
                "$command"
            then

                warn "Process identity changed before inspection."

                LPD_NETWORK_ACTION="STALE_PID"

                return 10
            fi


            echo


            if command_exists ps; then

                ps -fp "$pid" 2>/dev/null || true

                echo

            fi


            info "Active sockets owned by PID $pid:"


            if command_exists ss; then

                ss -Htanp 2>/dev/null |
                grep -F "pid=$pid," ||
                true

            else

                warn "ss is unavailable; socket inspection cannot be displayed."

            fi


            LPD_NETWORK_ACTION="INSPECT"


            return 10
            ;;


        2)

            echo

            warn "This action will request process $pid ($command) to terminate."

            warn "Active network activity from this process may be interrupted."

            echo


            local confirmation=""


            read -r -p "Apply this remediation? [y/N]: " confirmation


            case "$confirmation" in

                y|Y|yes|YES)
                    ;;


                *)

                    info "Remediation cancelled"


                    LPD_NETWORK_ACTION="CANCELLED"


                    return 10
                    ;;

            esac


            #
            # ----------------------------------------------------
            # FINAL PRE-SIGNAL SAFETY CHECK
            # ----------------------------------------------------
            #
            # This is intentionally stronger than checking that
            # /proc/PID still exists.
            #
            # It revalidates:
            #
            # - PID
            # - starttime
            # - command
            # - zombie state
            # - self / parent
            # - protected-process policy
            #
            # immediately before SIGTERM.
            #

            if ! lpd_signal_target_safe \
                "$pid" \
                "$expected_start" \
                "$command"
            then

                fail "Target is no longer safe to signal."

                fail "Action aborted to avoid affecting the wrong process."


                LPD_NETWORK_ACTION="STALE_OR_PROTECTED"


                return 3
            fi


            #
            # ----------------------------------------------------
            # LEGACY ACTION LOG
            # ----------------------------------------------------
            #

            if ! mkdir -p "$ROOT_DIR/logs"; then

                fail "Unable to access the log directory."

                LPD_NETWORK_ACTION="LOG_FAILURE"

                return 3
            fi


            printf "%s NETWORK SIGTERM pid=%s command=%s connections=%s\n" \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$pid" \
                "$command" \
                "$connection_count" \
                >> "$ROOT_DIR/logs/actions.log"


            #
            # ----------------------------------------------------
            # SIGNAL
            # ----------------------------------------------------
            #

            if kill -TERM "$pid" 2>/dev/null; then

                ok "SIGTERM sent to process $pid"


                LPD_NETWORK_ACTION="SIGTERM"


                return 0
            fi


            fail "Failed to send SIGTERM to process $pid"


            LPD_NETWORK_ACTION="SIGTERM_FAILED"


            return 2
            ;;


        3)

            info "Remediation skipped"


            LPD_NETWORK_ACTION="SKIP"


            return 10
            ;;


        *)

            fail "Invalid selection"


            LPD_NETWORK_ACTION="INVALID_SELECTION"


            return 3
            ;;

    esac
}
