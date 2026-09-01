#!/usr/bin/env bash


#
# ------------------------------------------------------------
# CAPTURE IONICE STATE
# ------------------------------------------------------------
#
# Results:
#
#   LPD_IONICE_CAPTURE_CLASS
#   LPD_IONICE_CAPTURE_DATA
#   LPD_IONICE_CAPTURE_RAW
#
# Classes:
#
#   0 = none
#   1 = realtime
#   2 = best-effort
#   3 = idle
#

disk_capture_ionice_state() {

    local pid="${1:-}"


    LPD_IONICE_CAPTURE_CLASS=""
    LPD_IONICE_CAPTURE_DATA="N/A"
    LPD_IONICE_CAPTURE_RAW=""


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1


    if ! command_exists ionice; then
        return 1
    fi


    local output=""

    output=$(
        LC_ALL=C ionice -p "$pid" 2>/dev/null
    ) || return 1


    [[ -n "$output" ]] || return 1


    LPD_IONICE_CAPTURE_RAW="$output"


    case "$output" in

        none:*|none)

            LPD_IONICE_CAPTURE_CLASS="0"
            ;;


        realtime:*|realtime)

            LPD_IONICE_CAPTURE_CLASS="1"
            ;;


        best-effort:*|best-effort)

            LPD_IONICE_CAPTURE_CLASS="2"
            ;;


        idle:*|idle)

            LPD_IONICE_CAPTURE_CLASS="3"
            ;;


        *)

            return 1
            ;;

    esac


    if [[ "$output" =~ prio[[:space:]]+([0-7]) ]]; then

        LPD_IONICE_CAPTURE_DATA="${BASH_REMATCH[1]}"

    fi


    return 0
}


#
# ------------------------------------------------------------
# CHECK IONICE STATE
# ------------------------------------------------------------
#

disk_ionice_state_matches() {

    local pid="${1:-}"
    local expected_class="${2:-}"
    local expected_data="${3:-N/A}"


    if ! disk_capture_ionice_state "$pid"; then
        return 1
    fi


    if [[ "$LPD_IONICE_CAPTURE_CLASS" != "$expected_class" ]]; then
        return 1
    fi


    #
    # Class 1 and 2 use class data / priority.
    #

    case "$expected_class" in

        1|2)

            if [[ "$LPD_IONICE_CAPTURE_DATA" != "$expected_data" ]]; then
                return 1
            fi
            ;;

    esac


    return 0
}


#
# ------------------------------------------------------------
# RESTORE PREVIOUS IONICE STATE
# ------------------------------------------------------------
#

disk_restore_ionice() {

    local pid="${LPD_DISK_PID:-N/A}"
    local command="${LPD_DISK_COMMAND:-N/A}"

    local expected_start="${LPD_DISK_PID_START:-N/A}"

    local previous_class="${LPD_DISK_IONICE_BEFORE_CLASS:-}"
    local previous_data="${LPD_DISK_IONICE_BEFORE_DATA:-N/A}"


    LPD_DISK_ROLLBACK_STATUS="NOT_ATTEMPTED"


    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then

        LPD_DISK_ROLLBACK_STATUS="NO_TARGET"

        return 10
    fi


    if [[ ! "$previous_class" =~ ^[0-3]$ ]]; then

        LPD_DISK_ROLLBACK_STATUS="NO_SAVED_STATE"

        return 10
    fi


    #
    # If the original process identity no longer exists, there is
    # no persistent ionice change left to restore.
    #

    if ! lpd_pid_identity_valid \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        LPD_DISK_ROLLBACK_STATUS="TARGET_GONE"

        info "Rollback not required because the original process identity is gone"

        return 10
    fi


    #
    # Safety check immediately before changing scheduling state.
    #

    if ! lpd_signal_target_safe \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        LPD_DISK_ROLLBACK_STATUS="SAFETY_ABORT"

        fail "Rollback blocked by PID safety validation"

        return 3
    fi


    info "Restoring previous I/O scheduling state..."


    local restore_rc=1


    case "$previous_class" in

        0)

            ionice \
                -c 0 \
                -p "$pid" \
                >/dev/null 2>&1

            restore_rc=$?
            ;;


        1|2)

            if [[ ! "$previous_data" =~ ^[0-7]$ ]]; then

                LPD_DISK_ROLLBACK_STATUS="INVALID_SAVED_STATE"

                fail "Saved ionice priority is invalid"

                return 3
            fi


            ionice \
                -c "$previous_class" \
                -n "$previous_data" \
                -p "$pid" \
                >/dev/null 2>&1

            restore_rc=$?
            ;;


        3)

            ionice \
                -c 3 \
                -p "$pid" \
                >/dev/null 2>&1

            restore_rc=$?
            ;;

    esac


    if (( restore_rc != 0 )); then

        LPD_DISK_ROLLBACK_STATUS="FAILED"

        fail "Unable to restore previous I/O scheduling state"


        lpd_audit \
            "ERROR" \
            "disk" \
            "IONICE_ROLLBACK_FAILED" \
            "pid=$pid command=$command"


        return 2
    fi


    #
    # Never trust only ionice exit code.
    # Read the state again and verify it.
    #

    if ! disk_ionice_state_matches \
        "$pid" \
        "$previous_class" \
        "$previous_data"
    then

        LPD_DISK_ROLLBACK_STATUS="VERIFY_FAILED"

        fail "Rollback command completed, but restored state could not be verified"


        lpd_audit \
            "ERROR" \
            "disk" \
            "IONICE_ROLLBACK_VERIFY_FAILED" \
            "pid=$pid command=$command"


        return 2
    fi


    LPD_DISK_ROLLBACK_STATUS="SUCCESS"


    ok "Previous I/O scheduling state restored"


    printf "%s DISK IONICE_ROLLBACK pid=%s command=%s class=%s priority=%s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$pid" \
        "$command" \
        "$previous_class" \
        "$previous_data" \
        >> "$ROOT_DIR/logs/actions.log"


    lpd_audit \
        "INFO" \
        "disk" \
        "IONICE_ROLLBACK_SUCCESS" \
        "pid=$pid command=$command class=$previous_class priority=$previous_data"


    return 0
}


#
# ------------------------------------------------------------
# DISK REMEDIATION
# ------------------------------------------------------------
#

disk_remediate() {

    section "Disk Remediation"


    local pid="${LPD_DISK_PID:-N/A}"
    local command="${LPD_DISK_COMMAND:-N/A}"

    local confidence="${LPD_DISK_CONFIDENCE:-LOW}"

    local expected_start="${LPD_DISK_PID_START:-N/A}"


    LPD_DISK_ACTION="NONE"

    LPD_DISK_ROLLBACK_STATUS="NOT_APPLICABLE"

    LPD_DISK_IONICE_BEFORE_CLASS=""
    LPD_DISK_IONICE_BEFORE_DATA="N/A"
    LPD_DISK_IONICE_BEFORE_RAW=""

    LPD_DISK_IONICE_AFTER_CLASS=""
    LPD_DISK_IONICE_AFTER_DATA="N/A"
    LPD_DISK_IONICE_AFTER_RAW=""


    printf "Device:              %s\n" "${LPD_DISK_DEVICE:-N/A}"

    printf "Suspected PID:       %s\n" "$pid"
    printf "Command:             %s\n" "$command"

    printf "Confidence:          %s\n" "$confidence"

    echo


    #
    # No safe user-space target.
    #

    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then

        warn "No active user-space process can be safely targeted."

        info "Recommendation: inspect storage, workload concurrency and application I/O behavior."


        LPD_DISK_ACTION="RECOMMENDATION"

        return 10
    fi


    #
    # Initial PID identity validation.
    #

    if ! lpd_pid_identity_valid \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        warn "The diagnosed I/O process is no longer safely identifiable."

        info "Automatic remediation has been blocked."


        LPD_DISK_ACTION="STALE_PID"

        return 10
    fi


    #
    # Protect LPD itself and its shell.
    #

    if (( pid == $$ || pid == PPID )); then

        warn "LPD will not modify or terminate itself or its parent shell."

        LPD_DISK_ACTION="PROTECTED"

        return 10
    fi


    if lpd_process_is_protected "$command"; then

        warn "Process $pid ($command) is system-sensitive."

        info "Automatic remediation will not be offered."


        LPD_DISK_ACTION="PROTECTED"

        return 10
    fi


    if [[ "$confidence" == "LOW" ]]; then

        warn "Culprit confidence is too low for automatic process remediation."

        info "Manual investigation is recommended."


        LPD_DISK_ACTION="LOW_CONFIDENCE"

        return 10
    fi


    echo "Available actions:"
    echo

    echo "  1) Inspect process"


    if command_exists ionice; then

        echo "  2) Lower I/O priority"
        echo "  3) Send SIGTERM (graceful termination)"
        echo "  4) Skip"

    else

        echo "  2) Send SIGTERM (graceful termination)"
        echo "  3) Skip"

    fi


    echo


    local choice=""

    read -r -p "Select action: " choice


    #
    # ------------------------------------------------------------
    # INSPECT
    # ------------------------------------------------------------
    #

    if [[ "$choice" == "1" ]]; then

        echo

        ps -fp "$pid"

        echo


        if [[ -r "/proc/$pid/io" ]]; then
            cat "/proc/$pid/io"
        fi


        if command_exists ionice; then

            echo
            echo "Current I/O scheduling:"

            LC_ALL=C ionice -p "$pid" 2>/dev/null || true
        fi


        LPD_DISK_ACTION="INSPECT"

        return 10
    fi


    #
    # ------------------------------------------------------------
    # IONICE AVAILABLE
    # ------------------------------------------------------------
    #

    if command_exists ionice; then


        #
        # --------------------------------------------------------
        # LOWER I/O PRIORITY
        # --------------------------------------------------------
        #

        if [[ "$choice" == "2" ]]; then

            echo

            warn "LPD will reduce I/O priority for process $pid ($command)."

            info "The process will continue running."

            echo


            local confirmation=""

            read -r -p "Apply this remediation? [y/N]: " confirmation


            case "$confirmation" in

                y|Y|yes|YES)
                    ;;

                *)

                    info "Remediation cancelled"

                    LPD_DISK_ACTION="CANCELLED"

                    return 10
                    ;;

            esac


            #
            # Revalidate immediately before touching the process.
            #

            if ! lpd_signal_target_safe \
                "$pid" \
                "$expected_start" \
                "$command"
            then

                fail "Process identity changed before remediation."

                fail "ionice blocked to avoid modifying the wrong process."


                LPD_DISK_ACTION="SAFETY_ABORT"

                return 3
            fi


            #
            # Capture exact previous scheduling state immediately
            # before the change.
            #

            if ! disk_capture_ionice_state "$pid"; then

                fail "Unable to capture the current I/O scheduling state"

                fail "Reversible remediation cannot be performed safely"


                LPD_DISK_ACTION="IONICE_STATE_UNKNOWN"

                return 3
            fi


            LPD_DISK_IONICE_BEFORE_CLASS="$LPD_IONICE_CAPTURE_CLASS"

            LPD_DISK_IONICE_BEFORE_DATA="$LPD_IONICE_CAPTURE_DATA"

            LPD_DISK_IONICE_BEFORE_RAW="$LPD_IONICE_CAPTURE_RAW"


            echo

            printf "Current I/O state:   %s\n" \
                "$LPD_DISK_IONICE_BEFORE_RAW"


            #
            # Idle class is already lower priority than our
            # best-effort:7 target.
            #

            if [[ "$LPD_DISK_IONICE_BEFORE_CLASS" == "3" ]]; then

                warn "Process is already using the idle I/O class."

                info "LPD will not raise its I/O priority to best-effort."


                LPD_DISK_ACTION="IONICE_ALREADY_LOW"

                return 10
            fi


            #
            # No pointless mutation if already at our target.
            #

            if [[ "$LPD_DISK_IONICE_BEFORE_CLASS" == "2" &&
                  "$LPD_DISK_IONICE_BEFORE_DATA" == "7" ]]; then

                info "Process already uses best-effort I/O priority 7."

                LPD_DISK_ACTION="IONICE_ALREADY_LOW"

                return 10
            fi


            #
            # Apply lower priority.
            #

            if ! ionice \
                -c 2 \
                -n 7 \
                -p "$pid" \
                >/dev/null 2>&1
            then

                fail "Unable to change I/O priority"

                LPD_DISK_ACTION="IONICE_FAILED"

                return 2
            fi


            #
            # Verify the mutation itself before claiming success.
            #

            if ! disk_ionice_state_matches \
                "$pid" \
                "2" \
                "7"
            then

                fail "ionice returned successfully, but the new state could not be verified"

                LPD_DISK_ACTION="IONICE"


                #
                # We captured the old state, so restore it.
                #

                disk_restore_ionice || true


                return 2
            fi


            LPD_DISK_IONICE_AFTER_CLASS="$LPD_IONICE_CAPTURE_CLASS"

            LPD_DISK_IONICE_AFTER_DATA="$LPD_IONICE_CAPTURE_DATA"

            LPD_DISK_IONICE_AFTER_RAW="$LPD_IONICE_CAPTURE_RAW"


            LPD_DISK_ACTION="IONICE"

            LPD_DISK_ROLLBACK_STATUS="AVAILABLE"


            ok "I/O priority reduced for process $pid"

            printf "New I/O state:       %s\n" \
                "$LPD_DISK_IONICE_AFTER_RAW"


            mkdir -p "$ROOT_DIR/logs"


            printf "%s DISK IONICE pid=%s command=%s before_class=%s before_priority=%s after_class=2 after_priority=7\n" \
                "$(date '+%Y-%m-%d %H:%M:%S')" \
                "$pid" \
                "$command" \
                "$LPD_DISK_IONICE_BEFORE_CLASS" \
                "$LPD_DISK_IONICE_BEFORE_DATA" \
                >> "$ROOT_DIR/logs/actions.log"


            lpd_audit \
                "INFO" \
                "disk" \
                "IONICE_APPLIED" \
                "pid=$pid command=$command before_class=$LPD_DISK_IONICE_BEFORE_CLASS before_priority=$LPD_DISK_IONICE_BEFORE_DATA after_class=2 after_priority=7 rollback=available"


            return 0
        fi


        #
        # SIGTERM
        #

        if [[ "$choice" == "3" ]]; then

            disk_sigterm \
                "$pid" \
                "$command" \
                "$expected_start"

            return $?
        fi


        if [[ "$choice" == "4" ]]; then

            info "Remediation skipped"

            LPD_DISK_ACTION="SKIP"

            return 10
        fi


    #
    # ------------------------------------------------------------
    # IONICE UNAVAILABLE
    # ------------------------------------------------------------
    #

    else

        if [[ "$choice" == "2" ]]; then

            disk_sigterm \
                "$pid" \
                "$command" \
                "$expected_start"

            return $?
        fi


        if [[ "$choice" == "3" ]]; then

            info "Remediation skipped"

            LPD_DISK_ACTION="SKIP"

            return 10
        fi

    fi


    fail "Invalid selection"

    return 3
}


#
# ------------------------------------------------------------
# DISK SIGTERM
# ------------------------------------------------------------
#

disk_sigterm() {

    local pid="$1"
    local command="$2"
    local expected_start="$3"


    echo

    warn "This action will request process $pid ($command) to terminate."

    warn "Active reads/writes may be interrupted."

    echo


    local confirmation=""

    read -r -p "Apply this remediation? [y/N]: " confirmation


    case "$confirmation" in

        y|Y|yes|YES)
            ;;

        *)

            info "Remediation cancelled"

            LPD_DISK_ACTION="CANCELLED"

            return 10
            ;;

    esac


    if ! lpd_signal_target_safe \
        "$pid" \
        "$expected_start" \
        "$command"
    then

        fail "Process identity changed before remediation."

        fail "SIGTERM blocked to avoid terminating the wrong process."


        LPD_DISK_ACTION="SAFETY_ABORT"

        return 3
    fi


    mkdir -p "$ROOT_DIR/logs"


    printf "%s DISK SIGTERM pid=%s command=%s reversible=no\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$pid" \
        "$command" \
        >> "$ROOT_DIR/logs/actions.log"


    lpd_audit \
        "WARNING" \
        "disk" \
        "SIGTERM_APPLIED" \
        "pid=$pid command=$command reversible=no"


    if kill -TERM "$pid" 2>/dev/null; then

        ok "SIGTERM sent to process $pid"

        LPD_DISK_ACTION="SIGTERM"

        LPD_DISK_ROLLBACK_STATUS="NOT_REVERSIBLE"

        return 0
    fi


    fail "Failed to send SIGTERM to process $pid"

    return 2
}
