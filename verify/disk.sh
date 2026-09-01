#!/usr/bin/env bash


disk_verify() {

    section "Disk Verification"


    local util_warn="${DISK_UTIL_WARN_PCT:-80}"

    local await_warn="${DISK_AWAIT_WARN_MS:-20}"

    local queue_warn="${DISK_QUEUE_WARN:-1}"


    local device="${LPD_DISK_DEVICE:-N/A}"

    local pid="${LPD_DISK_PID:-N/A}"
    local command="${LPD_DISK_COMMAND:-N/A}"

    local expected_start="${LPD_DISK_PID_START:-N/A}"

    local action="${LPD_DISK_ACTION:-UNKNOWN}"


    local before_rawait="${LPD_DISK_BEFORE_RAWAIT:-0}"
    local before_wawait="${LPD_DISK_BEFORE_WAWAIT:-0}"

    local before_queue="${LPD_DISK_BEFORE_QUEUE:-0}"
    local before_util="${LPD_DISK_BEFORE_UTIL:-0}"


    local ionice_before="${LPD_DISK_IONICE_BEFORE_RAW:-N/A}"
    local ionice_after="${LPD_DISK_IONICE_AFTER_RAW:-N/A}"


    #
    # ------------------------------------------------------------
    # ROLLBACK HELPER FOR FAILED/UNKNOWN VERIFICATION
    # ------------------------------------------------------------
    #

    disk_verify_attempt_rollback() {

        if [[ "$action" != "IONICE" ]]; then
            return 10
        fi


        if ! declare -F disk_restore_ionice >/dev/null 2>&1; then

            LPD_DISK_ROLLBACK_STATUS="HELPER_MISSING"

            fail "Rollback helper is unavailable"

            return 3
        fi


        warn "Verification did not establish a successful remediation."

        warn "Rolling back the ionice change."


        disk_restore_ionice

        return $?
    }


    #
    # ------------------------------------------------------------
    # BASIC VALIDATION
    # ------------------------------------------------------------
    #

    if [[ "$device" == "N/A" || -z "$device" ]]; then

        fail "No target disk is available for verification"


        disk_verify_attempt_rollback || true


        return 3
    fi


    if ! command_exists iostat; then

        fail "iostat is unavailable; disk verification cannot be trusted"


        disk_verify_attempt_rollback || true


        local rollback_status="${LPD_DISK_ROLLBACK_STATUS:-NOT_APPLICABLE}"


        lpd_record_remediation \
            "disk" \
            "DISK_IO_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "device=${device};util=${before_util}%;queue=${before_queue};read_await=${before_rawait}ms;write_await=${before_wawait}ms;ionice_before=${ionice_before}" \
            "verification_metrics=unavailable;rollback=${rollback_status}" \
            "UNKNOWN" \
            "$rollback_status"


        return 3
    fi


    info "Waiting for I/O state to settle..."

    sleep 2


    #
    # ------------------------------------------------------------
    # ORIGINAL PROCESS IDENTITY
    # ------------------------------------------------------------
    #

    local process_gone=0
    local process_state="unknown"


    if [[ "$pid" =~ ^[0-9]+$ ]] &&
       [[ "$expected_start" =~ ^[0-9]+$ ]]; then

        if lpd_pid_identity_valid \
            "$pid" \
            "$expected_start" \
            "$command"
        then

            process_state="running"

            info "Original target process is still running"

        else

            process_state="terminated_or_reused"

            process_gone=1

            ok "Original target process identity is no longer active"
        fi

    fi


    #
    # ------------------------------------------------------------
    # POST-ACTION DEVICE SAMPLE
    # ------------------------------------------------------------
    #

    local result=""

    result=$(
        LC_ALL=C iostat -dx 1 2 2>/dev/null |
        awk \
            -v target="$device" '
                /^Device/ {
                    report++

                    if (report == 2) {
                        delete column

                        for (i = 1; i <= NF; i++)
                            column[$i]=i
                    }

                    next
                }

                report == 2 && $1 == target {
                    rawait=0
                    wawait=0

                    queue=0
                    util=0

                    if (column["r_await"])
                        rawait=$(column["r_await"])

                    if (column["w_await"])
                        wawait=$(column["w_await"])

                    if (column["aqu-sz"])
                        queue=$(column["aqu-sz"])

                    if (column["%util"])
                        util=$(column["%util"])

                    print rawait,wawait,queue,util

                    exit
                }
            '
    )


    if [[ -z "$result" ]]; then

        fail "Unable to collect verification metrics for $device"


        disk_verify_attempt_rollback || true


        local rollback_status="${LPD_DISK_ROLLBACK_STATUS:-NOT_APPLICABLE}"


        lpd_record_remediation \
            "disk" \
            "DISK_IO_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "device=${device};util=${before_util}%;queue=${before_queue};read_await=${before_rawait}ms;write_await=${before_wawait}ms;ionice_before=${ionice_before}" \
            "verification_metrics=unavailable;process_state=${process_state};rollback=${rollback_status}" \
            "UNKNOWN" \
            "$rollback_status"


        return 3
    fi


    local after_rawait=0
    local after_wawait=0

    local after_queue=0
    local after_util=0


    read -r \
        after_rawait \
        after_wawait \
        after_queue \
        after_util \
        <<< "$result"


    #
    # Current ionice state, if applicable.
    #

    if [[ "$action" == "IONICE" ]] &&
       (( process_gone == 0 )) &&
       declare -F disk_capture_ionice_state >/dev/null 2>&1
    then

        if disk_capture_ionice_state "$pid"; then
            ionice_after="$LPD_IONICE_CAPTURE_RAW"
        fi

    fi


    echo

    printf "Device:              %s\n" "$device"

    printf "Util before:         %s%%\n" "$before_util"
    printf "Util after:          %s%%\n" "$after_util"

    printf "Queue before:        %s\n" "$before_queue"
    printf "Queue after:         %s\n" "$after_queue"

    printf "Read await before:   %s ms\n" "$before_rawait"
    printf "Read await after:    %s ms\n" "$after_rawait"

    printf "Write await before:  %s ms\n" "$before_wawait"
    printf "Write await after:   %s ms\n" "$after_wawait"


    if [[ "$action" == "IONICE" ]]; then

        echo

        printf "I/O priority before: %s\n" "$ionice_before"
        printf "I/O priority after:  %s\n" "$ionice_after"

    elif [[ "$action" == "SIGTERM" ]]; then

        echo

        printf "Reversible:          no\n"

    fi


    local before_record=""

    before_record="device=${device};util=${before_util}%;queue=${before_queue};read_await=${before_rawait}ms;write_await=${before_wawait}ms;ionice_before=${ionice_before}"


    local after_record=""

    after_record="device=${device};util=${after_util}%;queue=${after_queue};read_await=${after_rawait}ms;write_await=${after_wawait}ms;process_state=${process_state};ionice_after=${ionice_after}"


    #
    # ------------------------------------------------------------
    # HEALTH TEST
    # ------------------------------------------------------------
    #

    local disk_healthy=0


    if awk \
        -v util="$after_util" \
        -v r="$after_rawait" \
        -v w="$after_wawait" \
        -v q="$after_queue" \
        -v utilwarn="$util_warn" \
        -v awaitwarn="$await_warn" \
        -v queuewarn="$queue_warn" \
        'BEGIN {
            if (util >= utilwarn) exit 1
            if (r >= awaitwarn) exit 1
            if (w >= awaitwarn) exit 1
            if (q >= queuewarn) exit 1

            exit 0
        }'
    then

        disk_healthy=1
    fi


    #
    # ------------------------------------------------------------
    # RESOLVED - SIGTERM
    # ------------------------------------------------------------
    #

    if [[ "$action" == "SIGTERM" ]] &&
       (( process_gone == 1 )) &&
       (( disk_healthy == 1 )); then

        echo

        ok "RESOLVED - disk I/O condition returned to healthy state"


        lpd_record_remediation \
            "disk" \
            "DISK_IO_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "${after_record};rollback=NOT_REVERSIBLE" \
            "RESOLVED" \
            "SUCCESS"


        return 0
    fi


    #
    # ------------------------------------------------------------
    # RESOLVED - IONICE
    # ------------------------------------------------------------
    #

    if [[ "$action" == "IONICE" ]] &&
       (( disk_healthy == 1 )); then

        echo

        ok "RESOLVED - disk I/O condition returned to healthy state"

        info "ionice change retained because verification succeeded"


        LPD_DISK_ROLLBACK_STATUS="AVAILABLE_NOT_USED"


        lpd_record_remediation \
            "disk" \
            "DISK_IO_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "${after_record};rollback=AVAILABLE_NOT_USED" \
            "RESOLVED" \
            "SUCCESS"


        return 0
    fi


    #
    # ------------------------------------------------------------
    # MITIGATED
    # ------------------------------------------------------------
    #

    if awk \
        -v beforeutil="$before_util" \
        -v afterutil="$after_util" \
        -v beforeq="$before_queue" \
        -v afterq="$after_queue" \
        -v beforer="$before_rawait" \
        -v afterr="$after_rawait" \
        -v beforew="$before_wawait" \
        -v afterw="$after_wawait" \
        'BEGIN {
            if (afterutil >= beforeutil) exit 1
            if (afterq > beforeq) exit 1
            if (afterr > beforer) exit 1
            if (afterw > beforew) exit 1

            exit 0
        }'
    then

        echo

        warn "MITIGATED - disk pressure improved but remains above healthy thresholds"


        if [[ "$action" == "IONICE" ]]; then

            LPD_DISK_ROLLBACK_STATUS="AVAILABLE_NOT_USED"

            info "ionice change retained because measurable improvement was observed"

        fi


        lpd_record_remediation \
            "disk" \
            "DISK_IO_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "${after_record};rollback=${LPD_DISK_ROLLBACK_STATUS:-NOT_APPLICABLE}" \
            "MITIGATED" \
            "PARTIAL"


        return 1
    fi


    #
    # ------------------------------------------------------------
    # FAILED
    # ------------------------------------------------------------
    #

    echo

    fail "FAILED - disk I/O pressure remains"


    if [[ "$action" == "IONICE" ]]; then

        disk_verify_attempt_rollback || true

    fi


    local rollback_status="${LPD_DISK_ROLLBACK_STATUS:-NOT_APPLICABLE}"


    lpd_record_remediation \
        "disk" \
        "DISK_IO_PRESSURE" \
        "$pid" \
        "$command" \
        "$action" \
        "$before_record" \
        "${after_record};rollback=${rollback_status}" \
        "FAILED" \
        "$rollback_status"


    return 2
}
