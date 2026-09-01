#!/usr/bin/env bash


cpu_verify_busy_sample() {

    local cpu_label=""

    local user=0
    local nice=0
    local system=0
    local idle=0
    local iowait=0
    local irq=0
    local softirq=0
    local steal=0

    local total_1=0
    local idle_1=0

    local total_2=0
    local idle_2=0


    read -r \
        cpu_label \
        user \
        nice \
        system \
        idle \
        iowait \
        irq \
        softirq \
        steal \
        _ \
        < /proc/stat


    total_1=$((user + nice + system + idle + iowait + irq + softirq + steal))

    idle_1=$((idle + iowait))


    sleep 1


    user=0
    nice=0
    system=0
    idle=0
    iowait=0
    irq=0
    softirq=0
    steal=0


    read -r \
        cpu_label \
        user \
        nice \
        system \
        idle \
        iowait \
        irq \
        softirq \
        steal \
        _ \
        < /proc/stat


    total_2=$((user + nice + system + idle + iowait + irq + softirq + steal))

    idle_2=$((idle + iowait))


    local total_delta=$((total_2 - total_1))

    local idle_delta=$((idle_2 - idle_1))


    if (( total_delta <= 0 )); then

        echo "0.0"

        return 0
    fi


    awk \
        -v total="$total_delta" \
        -v idle="$idle_delta" \
        'BEGIN {
            printf "%.1f", ((total - idle) * 100) / total
        }'
}


cpu_verify() {

    section "CPU Verification"


    local healthy_busy="${CPU_VERIFY_HEALTHY_BUSY_PCT:-85}"


    local pid="${LPD_CPU_PID:-N/A}"
    local command="${LPD_CPU_COMMAND:-N/A}"

    local action="${LPD_CPU_ACTION:-UNKNOWN}"

    local before_process_cpu="${LPD_CPU_USAGE:-N/A}"


    info "Waiting for CPU state to settle..."

    sleep 2


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


    local cpu_busy="0"

    cpu_busy="$(
        cpu_verify_busy_sample
    )"


    local cpu_count=1


    if command_exists nproc; then
        cpu_count="$(nproc)"
    fi


    local load1=0


    if [[ -r /proc/loadavg ]]; then
        read -r load1 _ < /proc/loadavg
    fi


    local load_per_cpu="0.00"


    load_per_cpu=$(
        awk \
            -v load="$load1" \
            -v cpus="$cpu_count" \
            'BEGIN {
                if (cpus <= 0)
                    cpus=1

                printf "%.2f", load / cpus
            }'
    )


    echo

    printf "CPU busy after fix:  %s%%\n" "$cpu_busy"
    printf "Load per CPU:        %s\n" "$load_per_cpu"


    local before_record

    before_record="process_cpu=${before_process_cpu}%;pid=${pid};command=${command}"


    local after_record

    after_record="system_cpu_busy=${cpu_busy}%;load_per_cpu=${load_per_cpu};process_state=${process_state}"


    if [[ "$action" == "SIGTERM" ]] &&
       (( process_gone == 1 )) &&
       awk \
           -v busy="$cpu_busy" \
           -v threshold="$healthy_busy" \
           'BEGIN {
               if (busy < threshold)
                   exit 0

               exit 1
           }'
    then

        echo

        ok "RESOLVED - CPU saturation cleared"


        lpd_record_remediation \
            "cpu" \
            "CPU_SATURATION" \
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
        -v busy="$cpu_busy" \
        -v threshold="$healthy_busy" \
        'BEGIN {
            if (busy < threshold)
                exit 0

            exit 1
        }'
    then

        echo

        warn "MITIGATED - CPU pressure decreased but target process state did not fully match the expected result"


        lpd_record_remediation \
            "cpu" \
            "CPU_SATURATION" \
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

    fail "FAILED - CPU pressure remains"


    lpd_record_remediation \
        "cpu" \
        "CPU_SATURATION" \
        "$pid" \
        "$command" \
        "$action" \
        "$before_record" \
        "$after_record" \
        "FAILED" \
        "FAILED"


    return 2
}
