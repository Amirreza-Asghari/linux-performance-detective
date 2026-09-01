#!/usr/bin/env bash


#
# ------------------------------------------------------------
# TRUSTED SS COUNTER
# ------------------------------------------------------------
#

network_ss_count() {

    local state="${1:-}"


    [[ -n "$state" ]] || return 1


    local output=""


    if ! output=$(
        ss -Htan state "$state" 2>/dev/null
    ); then

        return 1
    fi


    if [[ -z "$output" ]]; then

        printf "0\n"

        return 0
    fi


    printf "%s\n" "$output" |
    awk '
        END {
            print NR + 0
        }
    '
}


#
# ------------------------------------------------------------
# RETRANSMISSION COUNTER
# ------------------------------------------------------------
#

network_retrans_counter() {

    local output=""


    if ! output=$(
        nstat -az TcpRetransSegs 2>/dev/null
    ); then

        return 1
    fi


    local value=""

    value=$(
        awk '
            $1 == "TcpRetransSegs" {
                print $2
                exit
            }
        ' <<< "$output"
    )


    [[ "$value" =~ ^[0-9]+$ ]] || return 1


    printf "%s\n" "$value"
}


#
# ------------------------------------------------------------
# NETWORK QUICK CHECK
# ------------------------------------------------------------
#

network_check() {

    section "Network"


    local time_wait_warn="${NETWORK_TIME_WAIT_WARN:-1000}"
    local time_wait_critical="${NETWORK_TIME_WAIT_CRITICAL:-5000}"

    local retrans_warn="${NETWORK_RETRANS_WARN:-10}"
    local retrans_critical="${NETWORK_RETRANS_CRITICAL:-100}"

    local syn_warn="${NETWORK_SYN_WARN:-100}"
    local syn_critical="${NETWORK_SYN_CRITICAL:-500}"


    #
    # ss is essential for this detector.
    #

    if ! lpd_require_command \
        "network" \
        "ss" \
        "TCP socket state inspection"
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
        "continue without TCP retransmission telemetry"
    then

        retrans_valid=1
    fi


    #
    # ------------------------------------------------------------
    # INTERFACE SAMPLE
    # ------------------------------------------------------------
    #

    echo "Active interfaces:"
    echo


    printf "%-12s %-8s %-10s %-10s %-10s %-10s\n" \
        "Interface" \
        "State" \
        "RXerr/s" \
        "RXdrop/s" \
        "TXerr/s" \
        "TXdrop/s"


    printf "%-12s %-8s %-10s %-10s %-10s %-10s\n" \
        "------------" \
        "--------" \
        "----------" \
        "----------" \
        "----------" \
        "----------"


    declare -A rxerr_before=()
    declare -A rxdrop_before=()
    declare -A txerr_before=()
    declare -A txdrop_before=()

    declare -A interface_state=()


    local active_interfaces=()

    local path=""
    local interface=""
    local state=""


    for path in /sys/class/net/*; do

        [[ -e "$path" ]] || continue


        interface="${path##*/}"


        [[ "$interface" != "lo" ]] || continue


        state=$(
            cat "$path/operstate" 2>/dev/null
        )


        [[ "$state" == "up" ]] || continue


        active_interfaces+=("$interface")

        interface_state["$interface"]="$state"


        rxerr_before["$interface"]=$(
            cat "$path/statistics/rx_errors" 2>/dev/null
        )

        rxdrop_before["$interface"]=$(
            cat "$path/statistics/rx_dropped" 2>/dev/null
        )

        txerr_before["$interface"]=$(
            cat "$path/statistics/tx_errors" 2>/dev/null
        )

        txdrop_before["$interface"]=$(
            cat "$path/statistics/tx_dropped" 2>/dev/null
        )

    done


    #
    # ------------------------------------------------------------
    # RETRANSMISSION BEFORE SAMPLE
    # ------------------------------------------------------------
    #

    local retrans_before=0
    local retrans_after=0

    local retrans_delta=0


    if (( retrans_valid == 1 )); then

        if ! retrans_before=$(
            network_retrans_counter
        ); then

            retrans_valid=0

            warn "TCP retransmission telemetry could not be collected"

            lpd_audit \
                "WARNING" \
                "network" \
                "TELEMETRY_UNAVAILABLE" \
                "metric=TcpRetransSegs stage=before"

        fi

    fi


    sleep 1


    #
    # ------------------------------------------------------------
    # INTERFACE DELTAS
    # ------------------------------------------------------------
    #

    local rxerr_after=0
    local rxdrop_after=0

    local txerr_after=0
    local txdrop_after=0

    local rxerr_delta=0
    local rxdrop_delta=0

    local txerr_delta=0
    local txdrop_delta=0

    local interface_anomaly=0


    for interface in "${active_interfaces[@]}"; do

        rxerr_after=$(
            cat "/sys/class/net/$interface/statistics/rx_errors" 2>/dev/null
        )

        rxdrop_after=$(
            cat "/sys/class/net/$interface/statistics/rx_dropped" 2>/dev/null
        )

        txerr_after=$(
            cat "/sys/class/net/$interface/statistics/tx_errors" 2>/dev/null
        )

        txdrop_after=$(
            cat "/sys/class/net/$interface/statistics/tx_dropped" 2>/dev/null
        )


        rxerr_after="${rxerr_after:-0}"
        rxdrop_after="${rxdrop_after:-0}"

        txerr_after="${txerr_after:-0}"
        txdrop_after="${txdrop_after:-0}"


        rxerr_delta=$((rxerr_after - ${rxerr_before[$interface]:-0}))
        rxdrop_delta=$((rxdrop_after - ${rxdrop_before[$interface]:-0}))

        txerr_delta=$((txerr_after - ${txerr_before[$interface]:-0}))
        txdrop_delta=$((txdrop_after - ${txdrop_before[$interface]:-0}))


        (( rxerr_delta >= 0 )) || rxerr_delta=0
        (( rxdrop_delta >= 0 )) || rxdrop_delta=0

        (( txerr_delta >= 0 )) || txerr_delta=0
        (( txdrop_delta >= 0 )) || txdrop_delta=0


        printf "%-12s %-8s %-10s %-10s %-10s %-10s\n" \
            "$interface" \
            "${interface_state[$interface]}" \
            "$rxerr_delta" \
            "$rxdrop_delta" \
            "$txerr_delta" \
            "$txdrop_delta"


        if (( rxerr_delta > 0 ||
              rxdrop_delta > 0 ||
              txerr_delta > 0 ||
              txdrop_delta > 0 )); then

            interface_anomaly=1
        fi

    done


    if (( ${#active_interfaces[@]} == 0 )); then

        warn "No active non-loopback network interface detected"

    fi


    #
    # ------------------------------------------------------------
    # RETRANSMISSION AFTER SAMPLE
    # ------------------------------------------------------------
    #

    if (( retrans_valid == 1 )); then

        if retrans_after=$(
            network_retrans_counter
        ); then

            retrans_delta=$((retrans_after - retrans_before))

            (( retrans_delta >= 0 )) || retrans_delta=0

        else

            retrans_valid=0

            warn "TCP retransmission telemetry became unavailable"

            lpd_audit \
                "WARNING" \
                "network" \
                "TELEMETRY_UNAVAILABLE" \
                "metric=TcpRetransSegs stage=after"

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

    local listen_count=0


    if ! established=$(network_ss_count established) ||
       ! time_wait=$(network_ss_count time-wait) ||
       ! syn_sent=$(network_ss_count syn-sent) ||
       ! syn_recv=$(network_ss_count syn-recv) ||
       ! listen_count=$(network_ss_count listening)
    then

        fail "Unable to collect trusted TCP socket state data"


        lpd_audit \
            "ERROR" \
            "network" \
            "TELEMETRY_FAILURE" \
            "source=ss"


        return 3
    fi


    echo
    echo "TCP socket states:"

    printf "ESTABLISHED:          %s\n" "$established"
    printf "TIME-WAIT:            %s\n" "$time_wait"

    printf "SYN-SENT:             %s\n" "$syn_sent"
    printf "SYN-RECV:             %s\n" "$syn_recv"

    printf "LISTEN:               %s\n" "$listen_count"


    if (( retrans_valid == 1 )); then

        printf "TCP retransmits/sec:  %s\n" "$retrans_delta"

    else

        printf "TCP retransmits/sec:  N/A\n"

    fi


    #
    # ------------------------------------------------------------
    # CRITICAL
    # ------------------------------------------------------------
    #

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

        echo

        fail "Critical network anomaly detected"

        return 2
    fi


    #
    # ------------------------------------------------------------
    # WARNING
    # ------------------------------------------------------------
    #

    if awk \
        -v timewait="$time_wait" \
        -v retrans="$retrans_delta" \
        -v retransvalid="$retrans_valid" \
        -v synsent="$syn_sent" \
        -v synrecv="$syn_recv" \
        -v twwarn="$time_wait_warn" \
        -v retranswarn="$retrans_warn" \
        -v synwarn="$syn_warn" \
        'BEGIN {
            if (timewait >= twwarn) exit 0

            if (retransvalid == 1 &&
                retrans >= retranswarn)
                exit 0

            if (synsent >= synwarn) exit 0
            if (synrecv >= synwarn) exit 0

            exit 1
        }'
    then

        echo

        warn "Network pressure or abnormal TCP state detected"

        return 1
    fi


    if (( interface_anomaly == 1 )); then

        echo

        warn "Network interface errors or packet drops increased during the sample"

        return 1
    fi


    if (( time_wait > 0 )); then

        info "A small TIME-WAIT population is present; this alone is not considered a fault"

    fi


    echo

    ok "No significant network anomaly detected"

    echo

    ok "Network subsystem is healthy"


    return 0
}
