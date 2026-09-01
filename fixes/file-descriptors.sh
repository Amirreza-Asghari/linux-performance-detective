#!/usr/bin/env bash


#
# ------------------------------------------------------------
# DISPLAY FILE DESCRIPTORS
# ------------------------------------------------------------
#

fd_print_first_descriptors() {

    local pid="${1:-}"
    local max_items="${2:-60}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ "$max_items" =~ ^[0-9]+$ ]] || return 1

    [[ -d "/proc/$pid/fd" ]] || return 1


    local shown=0

    local fd=""
    local target=""


    shopt -s nullglob


    local descriptors=(
        /proc/"$pid"/fd/*
    )


    shopt -u nullglob


    for fd in "${descriptors[@]}"; do

        target="N/A"


        if command_exists readlink; then

            target=$(
                readlink "$fd" 2>/dev/null
            )

            target="${target:-N/A}"

        fi


        printf "%-8s -> %s\n" \
            "${fd##*/}" \
            "$target"


        shown=$((shown + 1))


        if (( shown >= max_items )); then
            break
        fi

    done


    if (( shown == 0 )); then

        info "No file descriptors are currently visible for this process."

    fi


    return 0
}


#
# ------------------------------------------------------------
# FILE DESCRIPTOR REMEDIATION
# ------------------------------------------------------------
#

fd_remediate() {

    section "File Descriptor Remediation"


    local pid="${LPD_FD_PID:-N/A}"
    local command="${LPD_FD_COMMAND:-N/A}"

    local count="${LPD_FD_COUNT:-${LPD_FD_OPEN:-0}}"

    local soft="${LPD_FD_SOFT_LIMIT:-0}"
    local hard="${LPD_FD_HARD_LIMIT:-0}"

    local ratio="${LPD_FD_RATIO:-0}"

    local expected_start="${LPD_FD_PID_START:-N/A}"


    printf "Target PID:          %s\n" "$pid"
    printf "Command:             %s\n" "$command"

    printf "Open descriptors:    %s\n" "$count"

    printf "Soft limit:          %s\n" "$soft"
    printf "Hard limit:          %s\n" "$hard"

    printf "Limit usage:         %s%%\n" "$ratio"

    echo


    #
    # ------------------------------------------------------------
    # BASIC INPUT VALIDATION
    # ------------------------------------------------------------
    #

    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then

        warn "No valid process target is available."

        LPD_FD_ACTION="NO_TARGET"

        return 10
    fi


    if [[ "$expected_start" == "N/A" ||
          -z "$expected_start" ]]; then

        warn "Process identity information is incomplete."

        info "Remediation has been blocked."

        LPD_FD_ACTION="STALE_PID"

        return 10
    fi


    #
    # ------------------------------------------------------------
    # SHARED PID IDENTITY VALIDATION
    # ------------------------------------------------------------
    #
    # Do not parse /proc/PID/stat here.
    #
    # lib/safety.sh owns that logic and correctly handles the
    # parenthesized comm field and PID-reuse races.
    #

    if ! lpd_pid_identity_valid \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        warn "The suspected process is no longer safely identifiable."

        info "Automatic remediation has been blocked."

        LPD_FD_ACTION="STALE_PID"

        return 10
    fi


    #
    # ------------------------------------------------------------
    # PROTECTED TARGET POLICY
    # ------------------------------------------------------------
    #

    if (( pid == $$ || pid == PPID )); then

        warn "LPD will not terminate itself or its parent shell."

        LPD_FD_ACTION="PROTECTED"

        return 10
    fi


    if lpd_process_is_protected "$command"; then

        warn "Process $pid ($command) is system-sensitive."

        info "LPD will not automatically terminate this process."

        info "Recommendation: inspect the service and its file descriptor usage."

        LPD_FD_ACTION="PROTECTED"

        return 10
    fi


    #
    # ------------------------------------------------------------
    # RECHECK CURRENT PRESSURE
    # ------------------------------------------------------------
    #

    if ! awk \
        -v ratio="$ratio" \
        'BEGIN {
            if (ratio >= 80)
                exit 0

            exit 1
        }'
    then

        info "The process is no longer close enough to its limit to justify remediation."

        LPD_FD_ACTION="NO_ACTION"

        return 10
    fi


    #
    # ------------------------------------------------------------
    # POLICY
    # ------------------------------------------------------------
    #
    # LPD intentionally does NOT raise RLIMIT_NOFILE.
    #
    # Raising a limit blindly can hide a descriptor leak and
    # permanent service limits belong in service-specific
    # configuration.
    #

    info "LPD will not automatically raise the file descriptor limit."

    info "If the workload legitimately requires more descriptors, review its service configuration separately."

    echo


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
            # Revalidate before inspecting /proc.
            #

            if ! lpd_pid_identity_valid \
                "$pid" \
                "$expected_start" \
                "$command"
            then

                warn "Process identity changed before inspection."

                LPD_FD_ACTION="STALE_PID"

                return 10
            fi


            echo


            if command_exists ps; then

                ps -fp "$pid" 2>/dev/null || true

                echo

            fi


            info "First file descriptors:"


            fd_print_first_descriptors \
                "$pid" \
                60 ||
                warn "Unable to inspect the process file descriptors."


            LPD_FD_ACTION="INSPECT"

            return 10
            ;;


        2)

            echo

            warn "This action will request process $pid ($command) to terminate."

            warn "Any workload handled by this process may be interrupted."

            echo


            local confirmation=""


            read -r -p "Apply this remediation? [y/N]: " confirmation


            case "$confirmation" in

                y|Y|yes|YES)
                    ;;


                *)

                    info "Remediation cancelled"

                    LPD_FD_ACTION="CANCELLED"

                    return 10
                    ;;

            esac


            #
            # ----------------------------------------------------
            # FINAL SIGNAL SAFETY CHECK
            # ----------------------------------------------------
            #
            # This shared helper revalidates:
            #
            # - PID still exists
            # - starttime still matches
            # - command still matches
            # - target is not zombie
            # - target is not LPD itself / parent
            # - target is not protected
            #

            if ! lpd_signal_target_safe \
                "$pid" \
                "$expected_start" \
                "$command"
            then

                fail "Target is no longer safe to signal."

                fail "Action aborted to avoid terminating the wrong process."

                LPD_FD_ACTION="STALE_OR_PROTECTED"

                return 3
            fi


            mkdir -p "$ROOT_DIR/logs"


            printf "%s FD SIGTERM pid=%s command=%s open=%s soft=%s ratio=%s\n" \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$pid" \
                "$command" \
                "$count" \
                "$soft" \
                "$ratio" \
                >> "$ROOT_DIR/logs/actions.log"


            if kill -TERM "$pid" 2>/dev/null; then

                ok "SIGTERM sent to process $pid"

                LPD_FD_ACTION="SIGTERM"

                return 0
            fi


            fail "Failed to send SIGTERM to process $pid"

            LPD_FD_ACTION="SIGTERM_FAILED"

            return 2
            ;;


        3)

            info "Remediation skipped"

            LPD_FD_ACTION="SKIP"

            return 10
            ;;


        *)

            fail "Invalid selection"

            LPD_FD_ACTION="INVALID_SELECTION"

            return 3
            ;;

    esac
}
