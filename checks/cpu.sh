#!/usr/bin/env bash


#
# ------------------------------------------------------------
# READ TRUSTED CPU STAT SAMPLE
# ------------------------------------------------------------
#

cpu_read_stat_sample() {

    [[ -r /proc/stat ]] || return 1


    local label=""

    local user_cpu=0
    local nice_cpu=0
    local system_cpu=0

    local idle_cpu=0
    local iowait_cpu=0

    local irq_cpu=0
    local softirq_cpu=0

    local steal_cpu=0


    if ! read -r \
        label \
        user_cpu \
        nice_cpu \
        system_cpu \
        idle_cpu \
        iowait_cpu \
        irq_cpu \
        softirq_cpu \
        steal_cpu \
        _ \
        < /proc/stat
    then

        return 1
    fi


    [[ "$label" == "cpu" ]] || return 1


    local value=""


    for value in \
        "$user_cpu" \
        "$nice_cpu" \
        "$system_cpu" \
        "$idle_cpu" \
        "$iowait_cpu" \
        "$irq_cpu" \
        "$softirq_cpu" \
        "$steal_cpu"
    do

        [[ "$value" =~ ^[0-9]+$ ]] || return 1

    done


    local total=0
    local idle_total=0


    total=$(
        awk \
            -v usr="$user_cpu" \
            -v nic="$nice_cpu" \
            -v syscpu="$system_cpu" \
            -v idle="$idle_cpu" \
            -v iowait="$iowait_cpu" \
            -v irq="$irq_cpu" \
            -v softirq="$softirq_cpu" \
            -v steal="$steal_cpu" \
            'BEGIN {
                printf "%.0f", usr + nic + syscpu + idle + iowait + irq + softirq + steal
            }'
    )


    idle_total=$(
        awk \
            -v idle="$idle_cpu" \
            -v iowait="$iowait_cpu" \
            'BEGIN {
                printf "%.0f", idle + iowait
            }'
    )


    [[ "$total" =~ ^[0-9]+$ ]] || return 1
    [[ "$idle_total" =~ ^[0-9]+$ ]] || return 1


    printf "%s %s\n" \
        "$total" \
        "$idle_total"
}


#
# ------------------------------------------------------------
# LOAD AVERAGE
# ------------------------------------------------------------
#

cpu_read_load1() {

    [[ -r /proc/loadavg ]] || return 1


    local load1=""


    read -r load1 _ < /proc/loadavg || return 1


    [[ "$load1" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1


    printf "%s\n" "$load1"
}


#
# ------------------------------------------------------------
# CPU PSI
# ------------------------------------------------------------
#

cpu_read_psi() {

    [[ -r /proc/pressure/cpu ]] || return 1


    local value=""

    value=$(
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
        ' /proc/pressure/cpu 2>/dev/null
    )


    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1


    printf "%s\n" "$value"
}


#
# ------------------------------------------------------------
# CPU QUICK CHECK
# ------------------------------------------------------------
#

cpu_check() {

    section "CPU"


    local busy_warn="${CPU_BUSY_WARN_PCT:-85}"
    local busy_critical="${CPU_BUSY_CRITICAL_PCT:-95}"

    local load_warn="${CPU_LOAD_PER_CPU_WARN:-1.00}"
    local load_critical="${CPU_LOAD_PER_CPU_CRITICAL:-2.00}"

    local process_warn="${CPU_PROCESS_SATURATION_PCT:-90}"

    local psi_warn="${CPU_PSI_WARN_PCT:-10}"
    local psi_critical="${CPU_PSI_CRITICAL_PCT:-25}"


    #
    # ------------------------------------------------------------
    # REQUIRED TELEMETRY
    # ------------------------------------------------------------
    #

    if [[ ! -r /proc/stat ]]; then

        fail "Required CPU telemetry is unavailable: /proc/stat"

        lpd_audit \
            "ERROR" \
            "cpu" \
            "TELEMETRY_UNAVAILABLE" \
            "source=/proc/stat"

        return 3
    fi


    if [[ ! -r /proc/loadavg ]]; then

        fail "Required CPU telemetry is unavailable: /proc/loadavg"

        lpd_audit \
            "ERROR" \
            "cpu" \
            "TELEMETRY_UNAVAILABLE" \
            "source=/proc/loadavg"

        return 3
    fi


    if ! lpd_require_command \
        "cpu" \
        "ps" \
        "per-process CPU attribution"
    then

        return 3
    fi


    #
    # ------------------------------------------------------------
    # CPU COUNT
    # ------------------------------------------------------------
    #

    local cpu_count=0


    if command_exists nproc; then

        cpu_count=$(
            nproc 2>/dev/null
        )

    fi


    if [[ ! "$cpu_count" =~ ^[0-9]+$ ]] ||
       (( cpu_count <= 0 )); then

        cpu_count=$(
            awk '
                /^cpu[0-9]+[[:space:]]/ {
                    count++
                }

                END {
                    print count + 0
                }
            ' /proc/stat
        )

    fi


    if [[ ! "$cpu_count" =~ ^[0-9]+$ ]] ||
       (( cpu_count <= 0 )); then

        fail "Unable to determine CPU count reliably"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # LOAD
    # ------------------------------------------------------------
    #

    local load1=""


    if ! load1=$(
        cpu_read_load1
    ); then

        fail "Unable to collect trusted load-average telemetry"

        return 3
    fi


    local load_per_cpu="0.00"


    load_per_cpu=$(
        awk \
            -v load="$load1" \
            -v cpus="$cpu_count" \
            'BEGIN {
                if (cpus <= 0) exit 1
                printf "%.2f", load / cpus
            }'
    )


    #
    # ------------------------------------------------------------
    # CPU BUSY SAMPLE
    # ------------------------------------------------------------
    #

    local first_sample=""


    if ! first_sample=$(
        cpu_read_stat_sample
    ); then

        fail "Unable to collect the first trusted CPU sample"

        return 3
    fi


    local total_1=0
    local idle_1=0


    read -r \
        total_1 \
        idle_1 \
        <<< "$first_sample"


    sleep 1


    local second_sample=""


    if ! second_sample=$(
        cpu_read_stat_sample
    ); then

        fail "Unable to collect the second trusted CPU sample"

        return 3
    fi


    local total_2=0
    local idle_2=0


    read -r \
        total_2 \
        idle_2 \
        <<< "$second_sample"


    local total_delta=0
    local idle_delta=0


    total_delta=$(
        awk \
            -v after="$total_2" \
            -v before="$total_1" \
            'BEGIN {
                printf "%.0f", after - before
            }'
    )


    idle_delta=$(
        awk \
            -v after="$idle_2" \
            -v before="$idle_1" \
            'BEGIN {
                printf "%.0f", after - before
            }'
    )


    if [[ ! "$total_delta" =~ ^[0-9]+$ ]] ||
       (( total_delta <= 0 )); then

        fail "CPU counters did not advance; telemetry cannot be trusted"

        return 3
    fi


    if [[ ! "$idle_delta" =~ ^[0-9]+$ ]]; then

        fail "Invalid CPU idle delta"

        return 3
    fi


    if (( idle_delta > total_delta )); then

        fail "CPU telemetry counters are internally inconsistent"

        return 3
    fi


    local cpu_busy="0.0"


    cpu_busy=$(
        awk \
            -v total="$total_delta" \
            -v idle="$idle_delta" \
            'BEGIN {
                printf "%.1f", ((total - idle) * 100) / total
            }'
    )


    #
    # ------------------------------------------------------------
    # PSI - OPTIONAL
    # ------------------------------------------------------------
    #

    local psi="0.00"
    local psi_valid=0


    if psi=$(
        cpu_read_psi
    ); then

        psi_valid=1

    else

        psi="N/A"

        info "CPU PSI telemetry is unavailable; continuing with CPU counters, load and process telemetry"


        lpd_audit \
            "WARNING" \
            "cpu" \
            "OPTIONAL_TELEMETRY_UNAVAILABLE" \
            "source=/proc/pressure/cpu"

    fi


    #
    # ------------------------------------------------------------
    # STABLE TOP PROCESS
    # ------------------------------------------------------------
    #

    local candidates=""


    if ! candidates=$(
        ps -eo pid=,comm=,pcpu=,stat= \
            --sort=-pcpu \
            2>/dev/null |
        awk \
            -v self="$$" \
            -v parent="$PPID" '
                $1 != self &&
                $1 != parent &&
                $2 != "ps" &&
                $2 != "awk" &&
                $2 != "head" {

                    print $1,$2,$3,$4

                    count++

                    if (count >= 8)
                        exit
                }
            '
    ); then

        fail "ps failed while collecting CPU process telemetry"

        return 3
    fi


    if [[ -z "$candidates" ]]; then

        fail "No CPU process candidates could be collected"

        return 3
    fi


    local top_pid="N/A"
    local top_command="N/A"

    local top_cpu="0"
    local top_state="N/A"


    local candidate_pid=""
    local candidate_command=""

    local candidate_cpu="0"
    local candidate_state=""


    while read -r \
        candidate_pid \
        candidate_command \
        candidate_cpu \
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

            top_cpu="$candidate_cpu"
            top_state="$candidate_state"

            break
        fi

    done <<< "$candidates"


    if [[ "$top_pid" == "N/A" ]]; then

        fail "No stable CPU process identity could be captured"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # DISPLAY
    # ------------------------------------------------------------
    #

    printf "CPU count:           %s\n" "$cpu_count"
    printf "1-minute load:       %s\n" "$load1"
    printf "Load per CPU:        %s\n" "$load_per_cpu"

    printf "CPU busy:            %s%%\n" "$cpu_busy"


    if (( psi_valid == 1 )); then

        printf "CPU PSI avg10:       %s%%\n" "$psi"

    else

        printf "CPU PSI avg10:       N/A\n"

    fi


    echo
    echo "Top CPU process:"

    printf "PID:                 %s\n" "$top_pid"
    printf "Command:             %s\n" "$top_command"

    printf "CPU:                 %s%%\n" "$top_cpu"
    printf "State:               %s\n" "$top_state"


    #
    # ------------------------------------------------------------
    # CRITICAL
    # ------------------------------------------------------------
    #

    local psi_numeric=0


    if (( psi_valid == 1 )); then
        psi_numeric="$psi"
    fi


    if awk \
        -v busy="$cpu_busy" \
        -v load="$load_per_cpu" \
        -v psi="$psi_numeric" \
        -v psivalid="$psi_valid" \
        -v busycrit="$busy_critical" \
        -v loadcrit="$load_critical" \
        -v psicrit="$psi_critical" \
        'BEGIN {
            if (busy >= busycrit) exit 0
            if (load >= loadcrit) exit 0

            if (psivalid == 1) {
                if (psi >= psicrit) exit 0
            }

            exit 1
        }'
    then

        echo

        fail "Critical CPU pressure detected"

        return 2
    fi


    #
    # ------------------------------------------------------------
    # WARNING
    # ------------------------------------------------------------
    #

    if awk \
        -v busy="$cpu_busy" \
        -v load="$load_per_cpu" \
        -v process="$top_cpu" \
        -v psi="$psi_numeric" \
        -v psivalid="$psi_valid" \
        -v busywarn="$busy_warn" \
        -v loadwarn="$load_warn" \
        -v processwarn="$process_warn" \
        -v psiwarn="$psi_warn" \
        'BEGIN {
            if (busy >= busywarn) exit 0
            if (load >= loadwarn) exit 0
            if (process >= processwarn) exit 0

            if (psivalid == 1) {
                if (psi >= psiwarn) exit 0
            }

            exit 1
        }'
    then

        echo


        if awk \
            -v process="$top_cpu" \
            -v threshold="$process_warn" \
            'BEGIN {
                if (process >= threshold) exit 0
                exit 1
            }'
        then

            warn "Single-process CPU saturation detected"

        else

            warn "CPU pressure detected"

        fi


        return 1
    fi


    echo

    ok "No CPU pressure detected"

    return 0
}
