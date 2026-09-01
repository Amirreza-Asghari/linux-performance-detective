#!/usr/bin/env bash


#
# ------------------------------------------------------------
# TRUSTED MEMINFO
# ------------------------------------------------------------
#

memory_read_meminfo() {

    [[ -r /proc/meminfo ]] || return 1


    local result=""


    result=$(
        awk '
            /^MemTotal:/ {
                total=$2
                have_total=1
            }

            /^MemAvailable:/ {
                available=$2
                have_available=1
            }

            /^SwapTotal:/ {
                swap_total=$2
                have_swap_total=1
            }

            /^SwapFree:/ {
                swap_free=$2
                have_swap_free=1
            }

            END {
                if (!have_total) exit 1
                if (!have_available) exit 1

                if (total <= 0) exit 1
                if (available < 0) exit 1
                if (available > total) exit 1

                available_pct=(available * 100) / total

                swap_pct=0

                if (have_swap_total && have_swap_free && swap_total > 0) {
                    if (swap_free < 0) exit 1
                    if (swap_free > swap_total) exit 1

                    swap_pct=((swap_total - swap_free) * 100) / swap_total
                }

                printf "%.0f %.0f\n", available_pct, swap_pct
            }
        ' /proc/meminfo 2>/dev/null
    ) || return 1


    [[ -n "$result" ]] || return 1


    printf "%s\n" "$result"
}


#
# ------------------------------------------------------------
# TRUSTED VMSTAT SAMPLE
# ------------------------------------------------------------
#

memory_read_vmstat_swap() {

    command_exists vmstat || return 1


    local result=""


    result=$(
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
    ) || return 1


    [[ -n "$result" ]] || return 1


    local si=""
    local so=""


    read -r si so <<< "$result"


    [[ "$si" =~ ^[0-9]+$ ]] || return 1
    [[ "$so" =~ ^[0-9]+$ ]] || return 1


    printf "%s %s\n" "$si" "$so"
}


#
# ------------------------------------------------------------
# MEMORY PSI
# ------------------------------------------------------------
#

memory_read_psi() {

    [[ -r /proc/pressure/memory ]] || return 1


    local result=""


    result=$(
        awk '
            /^some/ {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^avg10=/) {
                        split($i,a,"=")
                        some=a[2]
                    }
                }
            }

            /^full/ {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^avg10=/) {
                        split($i,a,"=")
                        full=a[2]
                    }
                }
            }

            END {
                if (some == "") exit 1
                if (full == "") exit 1

                print some,full
            }
        ' /proc/pressure/memory 2>/dev/null
    ) || return 1


    [[ -n "$result" ]] || return 1


    local some=""
    local full=""


    read -r some full <<< "$result"


    [[ "$some" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    [[ "$full" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1


    printf "%s %s\n" "$some" "$full"
}


#
# ------------------------------------------------------------
# MEMORY QUICK CHECK
# ------------------------------------------------------------
#

memory_check() {

    section "Memory"


    local available_warn="${MEM_AVAILABLE_WARN_PCT:-25}"
    local available_swap_critical="${MEM_AVAILABLE_SWAP_CRITICAL_PCT:-15}"
    local available_critical="${MEM_AVAILABLE_CRITICAL_PCT:-8}"

    local swap_warn="${MEM_SWAP_ACTIVITY_WARN_KB:-1024}"
    local swap_critical="${MEM_SWAP_ACTIVITY_CRITICAL_KB:-4096}"

    local psi_some_warn="${MEM_PSI_SOME_WARN_PCT:-10}"
    local psi_some_critical="${MEM_PSI_SOME_CRITICAL_PCT:-25}"

    local psi_full_critical="${MEM_PSI_FULL_CRITICAL_PCT:-10}"


    #
    # ------------------------------------------------------------
    # REQUIRED MEMORY TELEMETRY
    # ------------------------------------------------------------
    #

    local memory_values=""


    if ! memory_values=$(
        memory_read_meminfo
    ); then

        fail "Unable to collect trusted memory telemetry from /proc/meminfo"


        lpd_audit \
            "ERROR" \
            "memory" \
            "TELEMETRY_UNAVAILABLE" \
            "source=/proc/meminfo"


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
    # ACTIVE SWAP - OPTIONAL
    # ------------------------------------------------------------
    #

    local swap_in="N/A"
    local swap_out="N/A"

    local swap_valid=0

    local swap_sample=""


    if swap_sample=$(
        memory_read_vmstat_swap
    ); then

        read -r \
            swap_in \
            swap_out \
            <<< "$swap_sample"

        swap_valid=1

    else

        info "Active swap-rate telemetry is unavailable; continuing with MemAvailable and available pressure telemetry"


        lpd_audit \
            "WARNING" \
            "memory" \
            "OPTIONAL_TELEMETRY_UNAVAILABLE" \
            "source=vmstat metrics=si,so"

    fi


    #
    # ------------------------------------------------------------
    # PSI - OPTIONAL
    # ------------------------------------------------------------
    #

    local psi_some="N/A"
    local psi_full="N/A"

    local psi_valid=0

    local psi_sample=""


    if psi_sample=$(
        memory_read_psi
    ); then

        read -r \
            psi_some \
            psi_full \
            <<< "$psi_sample"

        psi_valid=1

    else

        info "Memory PSI telemetry is unavailable; continuing with MemAvailable and swap telemetry"


        lpd_audit \
            "WARNING" \
            "memory" \
            "OPTIONAL_TELEMETRY_UNAVAILABLE" \
            "source=/proc/pressure/memory"

    fi


    #
    # ------------------------------------------------------------
    # TOP PROCESS - ATTRIBUTION ONLY
    # ------------------------------------------------------------
    #

    local top_pid="N/A"
    local top_command="N/A"

    local top_memory="N/A"
    local top_rss="N/A"

    local top_state="N/A"


    if command_exists ps; then

        local candidates=""


        candidates=$(
            ps -eo pid=,comm=,pmem=,rss=,stat= \
                --sort=-rss \
                2>/dev/null |
            awk \
                -v self="$$" \
                -v parent="$PPID" '
                    $1 != self &&
                    $1 != parent {

                        print $1,$2,$3,$4,$5

                        count++

                        if (count >= 8)
                            exit
                    }
                '
        )


        local candidate_pid=""
        local candidate_command=""

        local candidate_memory=""
        local candidate_rss=""

        local candidate_state=""


        while read -r \
            candidate_pid \
            candidate_command \
            candidate_memory \
            candidate_rss \
            candidate_state
        do

            [[ "$candidate_pid" =~ ^[0-9]+$ ]] || continue


            if lpd_capture_pid_identity \
                "$candidate_pid" \
                "$candidate_command" \
                >/dev/null
            then

                top_pid="$candidate_pid"
                top_command="$candidate_command"

                top_memory="$candidate_memory"


                top_rss=$(
                    awk \
                        -v rss="$candidate_rss" \
                        'BEGIN {
                            printf "%.1f", rss / 1024
                        }'
                )


                top_state="$candidate_state"


                break
            fi

        done <<< "$candidates"

    fi


    #
    # Process attribution is optional for the quick memory
    # health classification.
    #

    if [[ "$top_pid" == "N/A" ]]; then

        info "Stable per-process memory attribution is unavailable"

    fi


    #
    # ------------------------------------------------------------
    # DISPLAY
    # ------------------------------------------------------------
    #

    printf "Memory available:    %s%%\n" "$available"
    printf "Swap used:           %s%%\n" "$swap_used"


    if (( swap_valid == 1 )); then

        printf "Swap-in:             %s KB/s\n" "$swap_in"
        printf "Swap-out:            %s KB/s\n" "$swap_out"

    else

        printf "Swap-in:             N/A\n"
        printf "Swap-out:            N/A\n"

    fi


    if (( psi_valid == 1 )); then

        printf "Memory PSI some:     %s%%\n" "$psi_some"
        printf "Memory PSI full:     %s%%\n" "$psi_full"

    else

        printf "Memory PSI some:     N/A\n"
        printf "Memory PSI full:     N/A\n"

    fi


    echo
    echo "Top memory process:"

    printf "PID:                 %s\n" "$top_pid"
    printf "Command:             %s\n" "$top_command"

    printf "Memory:              %s%%\n" "$top_memory"

    printf "RSS:                 %s MB\n" "$top_rss"
    printf "State:               %s\n" "$top_state"


    #
    # ------------------------------------------------------------
    # SAFE NUMERIC VALUES
    # ------------------------------------------------------------
    #

    local swap_in_value=0
    local swap_out_value=0

    local psi_some_value=0
    local psi_full_value=0


    if (( swap_valid == 1 )); then

        swap_in_value="$swap_in"
        swap_out_value="$swap_out"

    fi


    if (( psi_valid == 1 )); then

        psi_some_value="$psi_some"
        psi_full_value="$psi_full"

    fi


    #
    # ------------------------------------------------------------
    # CRITICAL
    # ------------------------------------------------------------
    #

    if awk \
        -v available="$available" \
        -v full="$psi_full_value" \
        -v some="$psi_some_value" \
        -v psivalid="$psi_valid" \
        -v si="$swap_in_value" \
        -v so="$swap_out_value" \
        -v swapvalid="$swap_valid" \
        -v availablecrit="$available_critical" \
        -v swapsafe="$available_swap_critical" \
        -v psicrit="$psi_some_critical" \
        -v fullcrit="$psi_full_critical" \
        -v swapcrit="$swap_critical" \
        'BEGIN {
            if (available <= availablecrit) exit 0

            if (psivalid == 1) {
                if (full >= fullcrit) exit 0
                if (some >= psicrit) exit 0
            }

            if (swapvalid == 1) {
                if (available <= swapsafe) {
                    if (si >= swapcrit) exit 0
                    if (so >= swapcrit) exit 0
                }
            }

            exit 1
        }'
    then

        echo

        fail "Critical memory pressure detected"

        return 2
    fi


    #
    # ------------------------------------------------------------
    # WARNING
    # ------------------------------------------------------------
    #

    if awk \
        -v available="$available" \
        -v some="$psi_some_value" \
        -v psivalid="$psi_valid" \
        -v si="$swap_in_value" \
        -v so="$swap_out_value" \
        -v swapvalid="$swap_valid" \
        -v availablewarn="$available_warn" \
        -v psiwarn="$psi_some_warn" \
        -v swapwarn="$swap_warn" \
        'BEGIN {
            if (available <= availablewarn) exit 0

            if (swapvalid == 1) {
                if (si >= swapwarn) exit 0
                if (so >= swapwarn) exit 0
            }

            if (psivalid == 1) {
                if (some >= psiwarn) exit 0
            }

            exit 1
        }'
    then

        echo

        warn "Memory pressure or reduced memory headroom detected"

        return 1
    fi


    #
    # Residual swap alone is not active pressure.
    #

    if (( swap_used > 0 )); then

        info "Swap contains allocated pages, but active pressure was not confirmed"

    fi


    echo

    ok "No memory pressure detected"

    return 0
}
