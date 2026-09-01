#!/usr/bin/env bash


network_stop_tracer() {

    local pid="${1:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 0


    lpd_runtime_stop_pid "$pid"

    lpd_runtime_unregister_pid "$pid"


    return 0
}


#
# ------------------------------------------------------------
# TCP CONNECT TRACE
# ------------------------------------------------------------
#

network_trace_connectors() {

    local sample_seconds="${1:-5}"
    local startup_timeout="${2:-30}"


    LPD_NETWORK_TRACE_STATUS="UNAVAILABLE"

    LPD_NETWORK_TRACE_TOTAL=0

    LPD_NETWORK_TRACE_TOP_PID="N/A"
    LPD_NETWORK_TRACE_TOP_COMMAND="N/A"

    LPD_NETWORK_TRACE_TOP_COUNT=0

    LPD_NETWORK_TRACE_ERROR=""


    if ! lpd_command_available tcpconnect-bpfcc; then

        LPD_NETWORK_TRACE_ERROR="tcpconnect-bpfcc is unavailable"

        return 3
    fi


    if (( EUID != 0 )); then

        LPD_NETWORK_TRACE_ERROR="root privileges are required for BCC tracing"

        return 3
    fi


    local trace_file=""

    trace_file=$(
        mktemp /tmp/lpd-tcpconnect.XXXXXX
    ) || {

        LPD_NETWORK_TRACE_ERROR="unable to create temporary trace file"

        return 3
    }


    lpd_runtime_register_file "$trace_file"


    PYTHONUNBUFFERED=1 \
        tcpconnect-bpfcc \
        > "$trace_file" \
        2>&1 &


    local tracer_pid=$!


    lpd_runtime_register_pid "$tracer_pid"


    local ready=0
    local waited=0


    LPD_NETWORK_TRACE_STATUS="STARTING"


    while (( waited < startup_timeout )); do

        if grep -q "^Tracing connect" "$trace_file" 2>/dev/null; then

            ready=1

            break
        fi


        if ! lpd_runtime_pid_alive "$tracer_pid"; then

            wait "$tracer_pid" 2>/dev/null || true

            lpd_runtime_unregister_pid "$tracer_pid"


            LPD_NETWORK_TRACE_STATUS="FAILED"


            LPD_NETWORK_TRACE_ERROR=$(
                tail -n 12 "$trace_file" 2>/dev/null |
                tr '\n' ' '
            )


            rm -f -- "$trace_file"

            lpd_runtime_unregister_file "$trace_file"


            return 3
        fi


        sleep 1

        waited=$((waited + 1))

    done


    if (( ready == 0 )); then

        network_stop_tracer "$tracer_pid"


        LPD_NETWORK_TRACE_STATUS="FAILED"

        LPD_NETWORK_TRACE_ERROR="tcpconnect-bpfcc did not become ready within ${startup_timeout} seconds"


        rm -f -- "$trace_file"

        lpd_runtime_unregister_file "$trace_file"


        return 3
    fi


    LPD_NETWORK_TRACE_STATUS="SAMPLING"


    sleep "$sample_seconds"


    network_stop_tracer "$tracer_pid"


    LPD_NETWORK_TRACE_TOTAL=$(
        awk '
            $1 ~ /^[0-9]+$/ {
                count++
            }

            END {
                print count + 0
            }
        ' "$trace_file"
    )


    local top_connector=""

    top_connector=$(
        awk '
            $1 ~ /^[0-9]+$/ {
                key=$1 " " $2

                count[key]++
            }

            END {
                for (key in count)
                    print count[key],key
            }
        ' "$trace_file" |
        sort -nr |
        head -n 1
    )


    if [[ -n "$top_connector" ]]; then

        read -r \
            LPD_NETWORK_TRACE_TOP_COUNT \
            LPD_NETWORK_TRACE_TOP_PID \
            LPD_NETWORK_TRACE_TOP_COMMAND \
            <<< "$top_connector"

    fi


    LPD_NETWORK_TRACE_STATUS="OK"


    rm -f -- "$trace_file"

    lpd_runtime_unregister_file "$trace_file"


    return 0
}


#
# ------------------------------------------------------------
# NETWORK DEEP DIAGNOSIS
# ------------------------------------------------------------
#

network_diagnose() {

    section "Network Deep Diagnosis"


    local time_wait_warn="${NETWORK_TIME_WAIT_WARN:-1000}"
    local time_wait_critical="${NETWORK_TIME_WAIT_CRITICAL:-5000}"

    local retrans_warn="${NETWORK_RETRANS_WARN:-10}"
    local retrans_critical="${NETWORK_RETRANS_CRITICAL:-100}"

    local syn_warn="${NETWORK_SYN_WARN:-100}"
    local syn_critical="${NETWORK_SYN_CRITICAL:-500}"

    local connect_warn="${NETWORK_CONNECT_WARN_5S:-20}"
    local connect_critical="${NETWORK_CONNECT_CRITICAL_5S:-500}"

    local connector_medium="${NETWORK_TOP_CONNECT_MEDIUM_5S:-5}"
    local connector_high="${NETWORK_TOP_CONNECT_HIGH_5S:-20}"


    if ! lpd_require_command \
        "network" \
        "ss" \
        "trusted TCP socket-state diagnosis"
    then

        return 3
    fi


    #
    # nstat is optional.
    #

    local retrans_valid=0


    if lpd_optional_command \
        "network" \
        "nstat" \
        "continue without retransmission telemetry"
    then

        retrans_valid=1
    fi


    #
    # tcpconnect-bpfcc is optional, but deep diagnosis becomes
    # incomplete when it is unavailable.
    #

    local tracer_expected=0


    if lpd_optional_command \
        "network" \
        "tcpconnect-bpfcc" \
        "use TCP socket snapshot only; healthy deep diagnosis will remain UNKNOWN"
    then

        tracer_expected=1
    fi


    local retrans_before=0
    local retrans_after=0

    local retrans_delta=0


    if (( retrans_valid == 1 )); then

        if ! retrans_before=$(
            network_retrans_counter
        ); then

            retrans_valid=0

            warn "Retransmission baseline could not be collected"

        fi

    fi


    #
    # ------------------------------------------------------------
    # ACTIVE TRACE
    # ------------------------------------------------------------
    #

    local tracer_valid=0


    if (( tracer_expected == 1 )); then

        info "Starting TCP connection tracer..."

        info "BCC startup may take several seconds on virtual machines."


        if network_trace_connectors 5 30; then

            tracer_valid=1

            ok "TCP observation completed"

        else

            warn "Advanced TCP connection tracing failed"


            if [[ -n "${LPD_NETWORK_TRACE_ERROR:-}" ]]; then

                info "Tracer error: $LPD_NETWORK_TRACE_ERROR"

            fi


            lpd_audit \
                "WARNING" \
                "network" \
                "ACTIVE_TRACE_UNAVAILABLE" \
                "reason=${LPD_NETWORK_TRACE_ERROR:-unknown}"

        fi


    else

        LPD_NETWORK_TRACE_STATUS="UNAVAILABLE"

        info "Using socket-state fallback because active BCC tracing is unavailable"

    fi


    #
    # Retransmission after sample.
    #

    if (( retrans_valid == 1 )); then

        if retrans_after=$(
            network_retrans_counter
        ); then

            retrans_delta=$((retrans_after - retrans_before))

            (( retrans_delta >= 0 )) || retrans_delta=0

        else

            retrans_valid=0

            warn "Retransmission telemetry became unavailable"

        fi

    fi


    #
    # ------------------------------------------------------------
    # TRUSTED SOCKET SNAPSHOT
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

        fail "Unable to collect trusted TCP socket state data"


        lpd_audit \
            "ERROR" \
            "network" \
            "TELEMETRY_FAILURE" \
            "source=ss"


        return 3
    fi


    local total_connections="${LPD_NETWORK_TRACE_TOTAL:-0}"

    local connection_count="${LPD_NETWORK_TRACE_TOP_COUNT:-0}"

    local pid="${LPD_NETWORK_TRACE_TOP_PID:-N/A}"
    local command="${LPD_NETWORK_TRACE_TOP_COMMAND:-N/A}"


    local start_time="N/A"


    if [[ "$pid" =~ ^[0-9]+$ ]]; then

        start_time=$(
            lpd_capture_pid_identity \
                "$pid" \
                "$command"
        ) || start_time="N/A"

    fi


    echo
    echo "Finding: NETWORK_CONNECTION_ANOMALY"

    echo

    printf "ESTABLISHED:          %s\n" "$established"
    printf "TIME-WAIT:            %s\n" "$time_wait"

    printf "SYN-SENT:             %s\n" "$syn_sent"
    printf "SYN-RECV:             %s\n" "$syn_recv"


    if (( retrans_valid == 1 )); then

        printf "Retransmits/sample:   %s\n" "$retrans_delta"

    else

        printf "Retransmits/sample:   N/A\n"

    fi


    echo
    echo "Connection activity sample:"

    printf "Tracer status:        %s\n" "${LPD_NETWORK_TRACE_STATUS:-UNKNOWN}"


    if (( tracer_valid == 1 )); then

        printf "Total connects/5 sec: %s\n" "$total_connections"
        printf "Top connector PID:   %s\n" "$pid"
        printf "Command:             %s\n" "$command"
        printf "PID connects/5 sec:  %s\n" "$connection_count"

    else

        printf "Total connects/5 sec: N/A\n"
        printf "Top connector PID:   N/A\n"
        printf "Command:             N/A\n"
        printf "PID connects/5 sec:  N/A\n"

    fi


    LPD_NETWORK_BEFORE_TIME_WAIT="$time_wait"

    LPD_NETWORK_BEFORE_RETRANS="$(
        if (( retrans_valid == 1 )); then
            printf "%s" "$retrans_delta"
        else
            printf "N/A"
        fi
    )"

    LPD_NETWORK_BEFORE_ESTABLISHED="$established"

    LPD_NETWORK_PID="$pid"
    LPD_NETWORK_COMMAND="$command"

    LPD_NETWORK_CONNECT_COUNT="$connection_count"
    LPD_NETWORK_TOTAL_CONNECTS="$total_connections"

    LPD_NETWORK_PID_START="$start_time"


    #
    # ------------------------------------------------------------
    # CLASSIFICATION
    # ------------------------------------------------------------
    #

    local severity="OK"

    local diagnosis="No actionable network anomaly detected"

    local confidence="LOW"


    if awk \
        -v timewait="$time_wait" \
        -v retrans="$retrans_delta" \
        -v retransvalid="$retrans_valid" \
        -v synsent="$syn_sent" \
        -v synrecv="$syn_recv" \
        -v connects="$total_connections" \
        -v tracevalid="$tracer_valid" \
        -v twcrit="$time_wait_critical" \
        -v retranscrit="$retrans_critical" \
        -v syncrit="$syn_critical" \
        -v connectcrit="$connect_critical" \
        'BEGIN {
            if (timewait >= twcrit) exit 0

            if (retransvalid == 1 &&
                retrans >= retranscrit)
                exit 0

            if (synsent >= syncrit) exit 0
            if (synrecv >= syncrit) exit 0

            if (tracevalid == 1 &&
                connects >= connectcrit)
                exit 0

            exit 1
        }'
    then

        severity="CRITICAL"

        diagnosis="Severe network anomaly detected"


    elif awk \
        -v timewait="$time_wait" \
        -v retrans="$retrans_delta" \
        -v retransvalid="$retrans_valid" \
        -v synsent="$syn_sent" \
        -v synrecv="$syn_recv" \
        -v connects="$total_connections" \
        -v tracevalid="$tracer_valid" \
        -v twwarn="$time_wait_warn" \
        -v retranswarn="$retrans_warn" \
        -v synwarn="$syn_warn" \
        -v connectwarn="$connect_warn" \
        'BEGIN {
            if (timewait >= twwarn) exit 0

            if (retransvalid == 1 &&
                retrans >= retranswarn)
                exit 0

            if (synsent >= synwarn) exit 0
            if (synrecv >= synwarn) exit 0

            if (tracevalid == 1 &&
                connects >= connectwarn)
                exit 0

            exit 1
        }'
    then

        severity="WARNING"

        diagnosis="Elevated network activity or abnormal TCP state detected"

    fi


    #
    # Culprit attribution only exists when active trace is trusted.
    #

    if (( tracer_valid == 1 )) &&
       [[ "$pid" =~ ^[0-9]+$ ]] &&
       [[ "$start_time" != "N/A" ]]; then


        if awk \
            -v count="$connection_count" \
            -v threshold="$connector_high" \
            'BEGIN {
                if (count >= threshold) exit 0
                exit 1
            }'
        then

            confidence="HIGH"


        elif awk \
            -v count="$connection_count" \
            -v threshold="$connector_medium" \
            'BEGIN {
                if (count >= threshold) exit 0
                exit 1
            }'
        then

            confidence="MEDIUM"

        fi

    fi


    LPD_NETWORK_CONFIDENCE="$confidence"


    echo

    printf "Diagnosis:           %s\n" "$diagnosis"
    printf "Culprit confidence:  %s\n" "$confidence"


    case "$severity" in

        CRITICAL)

            fail "$diagnosis"

            return 2
            ;;


        WARNING)

            warn "$diagnosis"

            return 1
            ;;

    esac


    #
    # This is the important hardening behavior:
    #
    # Snapshot looks healthy, but active trace did not work.
    # We refuse to claim a trusted healthy deep diagnosis.
    #

    if (( tracer_valid == 0 )); then

        warn "No snapshot anomaly was detected, but active connection tracing is unavailable."

        warn "Deep network diagnosis status is UNKNOWN."


        lpd_audit \
            "WARNING" \
            "network" \
            "DIAGNOSIS_LIMITED" \
            "status=UNKNOWN reason=active_trace_unavailable"


        return 3
    fi


    info "$diagnosis"

    return 0
}
