#!/usr/bin/env bash


memory_verify() {

    section "Memory Verification"


    local min_available="${MEM_VERIFY_MIN_AVAILABLE_PCT:-25}"

    local max_psi="${MEM_VERIFY_MAX_PSI_PCT:-10}"

    local max_swap="${MEM_VERIFY_MAX_SWAP_KB:-1024}"

    local mitigation_improvement="${MEM_MITIGATION_IMPROVEMENT_PCT:-5}"


    local pid="${LPD_MEMORY_PID:-N/A}"
    local command="${LPD_MEMORY_COMMAND:-N/A}"

    local action="${LPD_MEMORY_ACTION:-UNKNOWN}"

    local before_available="${LPD_MEMORY_BEFORE_AVAILABLE:-0}"


    info "Waiting for memory state to settle..."

    sleep 3


    local process_gone=0
    local process_state="running"


    if [[ "$pid" =~ ^[0-9]+$ ]]; then

        if [[ -d "/proc/$pid" ]]; then

            warn "Process $pid is still running"

        else

            ok "Process $pid has terminated"

            process_gone=1
            process_state="terminated"

        fi

    fi


    local current_available=0

    current_available=$(
        awk '
            /^MemTotal:/ {
                total=$2
            }

            /^MemAvailable:/ {
                available=$2
            }

            END {
                if (total > 0)
                    printf "%.0f", (available * 100) / total
                else
                    print 0
            }
        ' /proc/meminfo
    )


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
                        print $7, $8
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


    local improvement=$((current_available - before_available))


    echo

    printf "Memory before:       %s%% available\n" "$before_available"
    printf "Memory after:        %s%% available\n" "$current_available"

    printf "Improvement:         %+d%%\n" "$improvement"

    printf "Swap-in after:       %s KB/s\n" "$swap_in"
    printf "Swap-out after:      %s KB/s\n" "$swap_out"

    printf "Memory PSI some:     %s%%\n" "$psi_some"
    printf "Memory PSI full:     %s%%\n" "$psi_full"


    local memory_healthy=0


    if awk \
        -v available="$current_available" \
        -v some="$psi_some" \
        -v full="$psi_full" \
        -v si="$swap_in" \
        -v so="$swap_out" \
        -v minavailable="$min_available" \
        -v maxpsi="$max_psi" \
        -v maxswap="$max_swap" \
        'BEGIN {
            if (available < minavailable) exit 1
            if (some >= maxpsi) exit 1
            if (full >= maxpsi) exit 1
            if (si >= maxswap) exit 1
            if (so >= maxswap) exit 1

            exit 0
        }'
    then

        memory_healthy=1

    fi


    local before_record

    before_record="memory_available=${before_available}%;pid=${pid};command=${command}"


    local after_record

    after_record="memory_available=${current_available}%;improvement=${improvement}%;swap_in=${swap_in}KB/s;swap_out=${swap_out}KB/s;psi_some=${psi_some}%;psi_full=${psi_full}%;process_state=${process_state}"


    if [[ "$action" == "SIGTERM" ]] &&
       (( process_gone == 1 )) &&
       (( memory_healthy == 1 )); then

        echo

        ok "RESOLVED - memory condition returned to healthy state"


        lpd_record_remediation \
            "memory" \
            "MEMORY_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "$after_record" \
            "RESOLVED" \
            "SUCCESS"


        return 0
    fi


    if [[ "$action" != "SIGTERM" ]] &&
       (( memory_healthy == 1 )); then

        echo

        ok "RESOLVED - memory condition returned to healthy state"


        lpd_record_remediation \
            "memory" \
            "MEMORY_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "$after_record" \
            "RESOLVED" \
            "SUCCESS"


        return 0
    fi


    if awk \
        -v improvement="$improvement" \
        -v threshold="$mitigation_improvement" \
        'BEGIN {
            if (improvement >= threshold)
                exit 0

            exit 1
        }'
    then

        echo

        warn "MITIGATED - memory condition improved but verification criteria are not fully satisfied"


        lpd_record_remediation \
            "memory" \
            "MEMORY_PRESSURE" \
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

    fail "FAILED - memory pressure remains"


    lpd_record_remediation \
        "memory" \
        "MEMORY_PRESSURE" \
        "$pid" \
        "$command" \
        "$action" \
        "$before_record" \
        "$after_record" \
        "FAILED" \
        "FAILED"


    return 2
}
