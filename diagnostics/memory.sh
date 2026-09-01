#!/usr/bin/env bash


memory_diagnose() {

    section "Memory Deep Diagnosis"


    local available_warn="${MEM_AVAILABLE_WARN_PCT:-25}"
    local available_swap_critical="${MEM_AVAILABLE_SWAP_CRITICAL_PCT:-15}"
    local available_critical="${MEM_AVAILABLE_CRITICAL_PCT:-8}"

    local swap_warn="${MEM_SWAP_ACTIVITY_WARN_KB:-1024}"
    local swap_critical="${MEM_SWAP_ACTIVITY_CRITICAL_KB:-4096}"

    local psi_some_warn="${MEM_PSI_SOME_WARN_PCT:-10}"
    local psi_some_critical="${MEM_PSI_SOME_CRITICAL_PCT:-25}"

    local psi_full_critical="${MEM_PSI_FULL_CRITICAL_PCT:-10}"

    local medium_confidence="${MEM_PROCESS_MEDIUM_CONFIDENCE_PCT:-20}"
    local high_confidence="${MEM_PROCESS_HIGH_CONFIDENCE_PCT:-40}"


    #
    # ------------------------------------------------------------
    # SYSTEM MEMORY
    # ------------------------------------------------------------
    #

    if [[ ! -r /proc/meminfo ]]; then

        fail "Unable to read /proc/meminfo"

        return 3
    fi


    local memory_values=""

    memory_values=$(
        awk '
            /^MemTotal:/ {
                total=$2
            }

            /^MemAvailable:/ {
                available=$2
            }

            /^SwapTotal:/ {
                swap_total=$2
            }

            /^SwapFree:/ {
                swap_free=$2
            }

            END {
                if (total <= 0)
                    exit 1

                available_pct=(available * 100) / total

                swap_pct=0

                if (swap_total > 0)
                    swap_pct=((swap_total - swap_free) * 100) / swap_total

                printf "%.0f %.0f\n",
                    available_pct,
                    swap_pct
            }
        ' /proc/meminfo
    )


    if [[ -z "$memory_values" ]]; then

        fail "Unable to calculate trusted memory metrics"

        return 3
    fi


    local available=0
    local swap_used=0


    read -r \
        available \
        swap_used \
        <<< "$memory_values"


    #
    # ------------------------------------------------------------
    # ACTIVE SWAP
    # ------------------------------------------------------------
    #

    local swap_in=0
    local swap_out=0


    if command_exists vmstat; then

        local vmstat_sample=""

        vmstat_sample=$(
            vmstat 1 2 2>/dev/null |
            awk '
                /^[[:space:]]*[0-9]/ {
                    sample++

                    if (sample == 2) {
                        print $7,$8
                        exit
                    }
                }
            '
        )


        if [[ -n "$vmstat_sample" ]]; then

            read -r \
                swap_in \
                swap_out \
                <<< "$vmstat_sample"

        fi

    fi


    swap_in="${swap_in:-0}"
    swap_out="${swap_out:-0}"


    #
    # ------------------------------------------------------------
    # PSI
    # ------------------------------------------------------------
    #

    local psi_some="0.00"
    local psi_full="0.00"


    if [[ -r /proc/pressure/memory ]]; then

        psi_some=$(
            awk '
                /^some/ {
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^avg10=/) {
                            split($i,a,"=")
                            print a[2]
                            exit
                        }
                    }
                }
            ' /proc/pressure/memory
        )


        psi_full=$(
            awk '
                /^full/ {
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^avg10=/) {
                            split($i,a,"=")
                            print a[2]
                            exit
                        }
                    }
                }
            ' /proc/pressure/memory
        )

    fi


    psi_some="${psi_some:-0.00}"
    psi_full="${psi_full:-0.00}"


    #
    # ------------------------------------------------------------
    # STABLE PROCESS CANDIDATE
    # ------------------------------------------------------------
    #

    local pid="N/A"
    local command="N/A"

    local process_pct="0"
    local rss_kb=0

    local state="N/A"

    local start_time="N/A"


    if command_exists ps; then

        local candidates=""

        candidates=$(
            ps -eo pid=,comm=,pmem=,rss=,stat= \
                --sort=-rss \
                2>/dev/null |
            awk '
                {
                    print $1,$2,$3,$4,$5

                    count++

                    if (count >= 8)
                        exit
                }
            '
        )


        local candidate_pid=""
        local candidate_command=""

        local candidate_pct="0"
        local candidate_rss=0

        local candidate_state=""


        while read -r \
            candidate_pid \
            candidate_command \
            candidate_pct \
            candidate_rss \
            candidate_state
        do

            [[ "$candidate_pid" =~ ^[0-9]+$ ]] || continue


            if (( candidate_pid == $$ ||
                  candidate_pid == PPID )); then

                continue
            fi


            local candidate_start=""

            candidate_start=$(
                lpd_capture_pid_identity \
                    "$candidate_pid" \
                    "$candidate_command"
            ) || continue


            pid="$candidate_pid"
            command="$candidate_command"

            process_pct="$candidate_pct"

            rss_kb="$candidate_rss"

            state="$candidate_state"

            start_time="$candidate_start"


            break

        done <<< "$candidates"

    fi


    #
    # System diagnosis remains valid even if culprit attribution
    # cannot be trusted.
    #

    if [[ "$pid" == "N/A" ]]; then

        warn "No stable memory-consuming process identity could be captured"

        info "System memory diagnosis will continue without automatic culprit attribution"


        if declare -F lpd_audit >/dev/null 2>&1; then

            lpd_audit \
                "WARNING" \
                "memory" \
                "TARGET_UNAVAILABLE" \
                "system_metrics=trusted culprit=unavailable"

        fi

    fi


    local rss_mb="0.0"


    if [[ "$rss_kb" =~ ^[0-9]+$ ]]; then

        rss_mb=$(
            awk \
                -v rss="$rss_kb" \
                'BEGIN {
                    printf "%.1f", rss / 1024
                }'
        )

    fi


    #
    # ------------------------------------------------------------
    # SAVE EVIDENCE
    # ------------------------------------------------------------
    #

    LPD_MEMORY_PID="$pid"
    LPD_MEMORY_COMMAND="$command"

    LPD_MEMORY_PROCESS_PCT="$process_pct"

    LPD_MEMORY_BEFORE_AVAILABLE="$available"

    LPD_MEMORY_BEFORE_SWAP_IN="$swap_in"
    LPD_MEMORY_BEFORE_SWAP_OUT="$swap_out"

    LPD_MEMORY_BEFORE_PSI_SOME="$psi_some"
    LPD_MEMORY_BEFORE_PSI_FULL="$psi_full"

    LPD_MEMORY_PID_START="$start_time"


    #
    # ------------------------------------------------------------
    # OUTPUT
    # ------------------------------------------------------------
    #

    echo "Finding: MEMORY_PRESSURE"

    echo

    printf "Memory available:    %s%%\n" "$available"
    printf "Swap used:           %s%%\n" "$swap_used"

    printf "Swap-in:             %s KB/s\n" "$swap_in"
    printf "Swap-out:            %s KB/s\n" "$swap_out"

    printf "Memory PSI some:     %s%%\n" "$psi_some"
    printf "Memory PSI full:     %s%%\n" "$psi_full"


    echo
    echo "Largest stable memory process:"

    printf "PID:                 %s\n" "$pid"
    printf "Command:             %s\n" "$command"

    printf "Memory:              %s%%\n" "$process_pct"
    printf "RSS:                 %s MB\n" "$rss_mb"

    printf "State:               %s\n" "$state"


    #
    # ------------------------------------------------------------
    # CULPRIT CONFIDENCE
    # ------------------------------------------------------------
    #

    local confidence="LOW"


    if [[ "$pid" != "N/A" ]]; then

        if awk \
            -v pct="$process_pct" \
            -v threshold="$high_confidence" \
            'BEGIN {
                if (pct >= threshold)
                    exit 0

                exit 1
            }'
        then

            confidence="HIGH"


        elif awk \
            -v pct="$process_pct" \
            -v threshold="$medium_confidence" \
            'BEGIN {
                if (pct >= threshold)
                    exit 0

                exit 1
            }'
        then

            confidence="MEDIUM"

        fi

    fi


    LPD_MEMORY_CONFIDENCE="$confidence"


    #
    # ------------------------------------------------------------
    # CLASSIFICATION
    # ------------------------------------------------------------
    #

    local severity="OK"

    local diagnosis="No actionable memory pressure detected"


    if awk \
        -v available="$available" \
        -v full="$psi_full" \
        -v some="$psi_some" \
        -v si="$swap_in" \
        -v so="$swap_out" \
        -v availablecrit="$available_critical" \
        -v swapsafe="$available_swap_critical" \
        -v psicrit="$psi_some_critical" \
        -v fullcrit="$psi_full_critical" \
        -v swapcrit="$swap_critical" \
        'BEGIN {
            if (available <= availablecrit) exit 0
            if (full >= fullcrit) exit 0
            if (some >= psicrit) exit 0

            if (available <= swapsafe && si >= swapcrit) exit 0
            if (available <= swapsafe && so >= swapcrit) exit 0

            exit 1
        }'
    then

        severity="CRITICAL"

        diagnosis="Severe memory pressure detected"


    elif awk \
        -v available="$available" \
        -v some="$psi_some" \
        -v si="$swap_in" \
        -v so="$swap_out" \
        -v availablewarn="$available_warn" \
        -v psiwarn="$psi_some_warn" \
        -v swapwarn="$swap_warn" \
        'BEGIN {
            if (available <= availablewarn) exit 0
            if (si >= swapwarn) exit 0
            if (so >= swapwarn) exit 0
            if (some >= psiwarn) exit 0

            exit 1
        }'
    then

        severity="WARNING"

        diagnosis="Memory pressure or reduced memory headroom detected"

    fi


    echo

    printf "Diagnosis:           %s\n" "$diagnosis"
    printf "Culprit confidence:  %s\n" "$confidence"


    case "$severity" in

        OK)

            info "$diagnosis"

            return 0
            ;;


        WARNING)

            warn "$diagnosis"

            return 1
            ;;


        CRITICAL)

            fail "$diagnosis"

            return 2
            ;;

    esac


    return 3
}
