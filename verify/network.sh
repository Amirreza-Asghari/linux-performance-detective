#!/usr/bin/env bash


network_verify() {

    section "Network Verification"


    local time_wait_warn="${NETWORK_TIME_WAIT_WARN:-1000}"
    local time_wait_critical="${NETWORK_TIME_WAIT_CRITICAL:-5000}"

    local retrans_warn="${NETWORK_RETRANS_WARN:-10}"
    local retrans_critical="${NETWORK_RETRANS_CRITICAL:-100}"

    local syn_warn="${NETWORK_SYN_WARN:-100}"
    local syn_critical="${NETWORK_SYN_CRITICAL:-500}"

    local verify_connect_max="${NETWORK_VERIFY_CONNECT_MAX_3S:-5}"


    local pid="${LPD_NETWORK_PID:-N/A}"
    local command="${LPD_NETWORK_COMMAND:-N/A}"

    local expected_start="${LPD_NETWORK_PID_START:-N/A}"

    local action="${LPD_NETWORK_ACTION:-UNKNOWN}"


    local before_time_wait="${LPD_NETWORK_BEFORE_TIME_WAIT:-0}"
    local before_retrans="${LPD_NETWORK_BEFORE_RETRANS:-N/A}"

    local before_connects="${LPD_NETWORK_TOTAL_CONNECTS:-0}"


    if ! lpd_require_command \
        "network" \
        "ss" \
        "network remediation verification"
    then

        return 3
    fi


    local retrans_valid=0


    if lpd_command_available nstat; then
        retrans_valid=1
    fi


    info "Waiting for network state to settle..."

    sleep 2


    #
    # ------------------------------------------------------------
    # TARGET STATE
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
    # RETRANSMISSION BEFORE
    # ------------------------------------------------------------
    #

    local retrans_before_sample=0
    local retrans_after_sample=0

    local retrans_delta=0


    if (( retrans_valid == 1 )); then

        if ! retrans_before_sample=$(
            network_retrans_counter
        ); then

            retrans_valid=0
        fi

    fi


    #
    # ------------------------------------------------------------
    # ACTIVE VERIFICATION TRACE
    # ------------------------------------------------------------
    #

    info "Running post-remediation TCP observation..."


    if ! network_trace_connectors 3 30; then

        fail "Network verifier could not obtain a trusted TCP trace"


        local unknown_after=""

        unknown_after="tracer_status=${LPD_NETWORK_TRACE_STATUS:-FAILED};process_state=${process_state}"


        lpd_record_remediation \
            "network" \
            "NETWORK_CONNECTION_ANOMALY" \
            "$pid" \
            "$command" \
            "$action" \
            "time_wait=${before_time_wait};retrans=${before_retrans};connections=${before_connects}" \
            "$unknown_after" \
            "UNKNOWN" \
            "UNKNOWN"


        return 3
    fi


    local after_connects="${LPD_NETWORK_TRACE_TOTAL:-0}"


    #
    # ------------------------------------------------------------
    # RETRANSMISSION AFTER
    # ------------------------------------------------------------
    #

    if (( retrans_valid == 1 )); then

        if retrans_after_sample=$(
            network_retrans_counter
        ); then

            retrans_delta=$((retrans_after_sample - retrans_before_sample))

            (( retrans_delta >= 0 )) || retrans_delta=0

        else

            retrans_valid=0
        fi

    fi


    #
    # ------------------------------------------------------------
    # SOCKET STATES
    # ------------------------------------------------------------
    #

    local established=0
    local time_wait=0

    local syn_sent=0
    local syn_recv=0


    if ! established=$(network_ss_count established) ||
       ! time_wait=$(network_ss_count time-wait) ||
       ! syn_sent=$(network_ss_count syn-sent) ||
       ! syn_recv=$(network_ss_count syn-recv)
    then

        fail "Network verifier could not obtain trusted socket-state telemetry"


        lpd_record_remediation \
            "network" \
            "NETWORK_CONNECTION_ANOMALY" \
            "$pid" \
            "$command" \
            "$action" \
            "time_wait=${before_time_wait};retrans=${before_retrans};connections=${before_connects}" \
            "socket_state=unavailable;process_state=${process_state}" \
            "UNKNOWN" \
            "UNKNOWN"


        return 3
    fi


    echo

    printf "TIME-WAIT before:    %s\n" "$before_time_wait"
    printf "TIME-WAIT after:     %s\n" "$time_wait"

    printf "Retrans before:      %s\n" "$before_retrans"


    if (( retrans_valid == 1 )); then

        printf "Retrans after:       %s\n" "$retrans_delta"

    else

        printf "Retrans after:       N/A\n"

    fi


    printf "Connections before:  %s / 5 sec\n" "$before_connects"
    printf "Connections after:   %s / 3 sec\n" "$after_connects"

    printf "ESTABLISHED after:   %s\n" "$established"

    printf "SYN-SENT after:      %s\n" "$syn_sent"
    printf "SYN-RECV after:      %s\n" "$syn_recv"


    local before_record=""

    before_record="time_wait=${before_time_wait};retrans=${before_retrans};connections_5s=${before_connects};pid=${pid};command=${command}"


    local after_record=""

    after_record="time_wait=${time_wait};established=${established};syn_sent=${syn_sent};syn_recv=${syn_recv};retrans=$(
        if (( retrans_valid == 1 )); then
            printf "%s" "$retrans_delta"
        else
            printf "N/A"
        fi
    );new_connections_3s=${after_connects};process_state=${process_state};tracer_status=${LPD_NETWORK_TRACE_STATUS:-UNKNOWN}"


    #
    # ------------------------------------------------------------
    # HEALTH TEST
    # ------------------------------------------------------------
    #

    local network_healthy=0


    if awk \
        -v timewait="$time_wait" \
        -v retrans="$retrans_delta" \
        -v retransvalid="$retrans_valid" \
        -v synsent="$syn_sent" \
        -v synrecv="$syn_recv" \
        -v connects="$after_connects" \
        -v twwarn="$time_wait_warn" \
        -v retranswarn="$retrans_warn" \
        -v synwarn="$syn_warn" \
        -v connectmax="$verify_connect_max" \
        'BEGIN {
            if (timewait >= twwarn) exit 1

            if (retransvalid == 1 &&
                retrans >= retranswarn)
                exit 1

            if (synsent >= synwarn) exit 1
            if (synrecv >= synwarn) exit 1
            if (connects > connectmax) exit 1

            exit 0
        }'
    then

        network_healthy=1
    fi


    #
    # ------------------------------------------------------------
    # RESOLVED
    # ------------------------------------------------------------
    #

    if [[ "$action" == "SIGTERM" ]] &&
       (( process_gone == 1 )) &&
       (( network_healthy == 1 )); then

        echo

        ok "RESOLVED - network connection anomaly cleared"


        lpd_record_remediation \
            "network" \
            "NETWORK_CONNECTION_ANOMALY" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "$after_record" \
            "RESOLVED" \
            "SUCCESS"


        return 0
    fi


    #
    # ------------------------------------------------------------
    # CRITICAL AFTER STATE
    # ------------------------------------------------------------
    #

    local critical_after=0


    if awk \
        -v timewait="$time_wait" \
        -v retrans="$retrans_delta" \
        -v retransvalid="$retrans_valid" \
        -v synsent="$syn_sent" \
        -v synrecv="$syn_recv" \
        -v twcrit="$time_wait_critical" \
        -v retranscrit="$retrans_critical" \
        -v syncrit="$syn_critical" \
        'BEGIN {
            if (timewait >= twcrit) exit 0

            if (retransvalid == 1 &&
                retrans >= retranscrit)
                exit 0

            if (synsent >= syncrit) exit 0
            if (synrecv >= syncrit) exit 0

            exit 1
        }'
    then

        critical_after=1
    fi


    #
    # ------------------------------------------------------------
    # MITIGATED
    # ------------------------------------------------------------
    #

    local activity_improved=0


    if awk \
        -v before="$before_connects" \
        -v after="$after_connects" \
        'BEGIN {
            if (before > 0 && after < before)
                exit 0

            exit 1
        }'
    then

        activity_improved=1
    fi


    if (( critical_after == 0 )) &&
       (( process_gone == 1 ||
          activity_improved == 1 )); then

        echo

        warn "MITIGATED - network activity improved but healthy verification criteria are not fully satisfied"


        lpd_record_remediation \
            "network" \
            "NETWORK_CONNECTION_ANOMALY" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "$after_record" \
            "MITIGATED" \
            "PARTIAL"


        return 1
    fi


    echo

    fail "FAILED - network anomaly remains"


    lpd_record_remediation \
        "network" \
        "NETWORK_CONNECTION_ANOMALY" \
        "$pid" \
        "$command" \
        "$action" \
        "$before_record" \
        "$after_record" \
        "FAILED" \
        "FAILED"


    return 2
}
