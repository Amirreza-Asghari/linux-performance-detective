#!/usr/bin/env bash


#
# ------------------------------------------------------------
# CPU STAT SAMPLE
# ------------------------------------------------------------
#

lpd_evidence_cpu_stat_sample() {

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


    total=$(( \
        user_cpu + \
        nice_cpu + \
        system_cpu + \
        idle_cpu + \
        iowait_cpu + \
        irq_cpu + \
        softirq_cpu + \
        steal_cpu \
    ))


    idle_total=$(( \
        idle_cpu + \
        iowait_cpu \
    ))


    printf "%s %s\n" \
        "$total" \
        "$idle_total"


    return 0
}


#
# ------------------------------------------------------------
# CPU EVIDENCE
# ------------------------------------------------------------
#

lpd_collect_cpu_evidence() {

    LPD_EVIDENCE_CPU_COUNT="N/A"
    LPD_EVIDENCE_CPU_BUSY="N/A"

    LPD_EVIDENCE_CPU_LOAD1="N/A"
    LPD_EVIDENCE_CPU_PSI="N/A"

    LPD_EVIDENCE_CPU_TOP_PID="N/A"
    LPD_EVIDENCE_CPU_TOP_COMMAND="N/A"
    LPD_EVIDENCE_CPU_TOP_USAGE="N/A"


    #
    # CPU count
    #

    if command_exists nproc; then

        local cpu_count=""

        cpu_count=$(
            nproc 2>/dev/null
        )


        if [[ "$cpu_count" =~ ^[0-9]+$ ]] &&
           (( cpu_count > 0 )); then

            LPD_EVIDENCE_CPU_COUNT="$cpu_count"

        fi

    fi


    if [[ "$LPD_EVIDENCE_CPU_COUNT" == "N/A" ]] &&
       [[ -r /proc/stat ]]; then

        local fallback_count=""

        fallback_count=$(
            awk '
                /^cpu[0-9]+[[:space:]]/ {
                    count++
                }

                END {
                    print count + 0
                }
            ' /proc/stat 2>/dev/null
        )


        if [[ "$fallback_count" =~ ^[0-9]+$ ]] &&
           (( fallback_count > 0 )); then

            LPD_EVIDENCE_CPU_COUNT="$fallback_count"

        fi

    fi


    #
    # Load
    #

    if [[ -r /proc/loadavg ]]; then

        local load1=""

        if read -r load1 _ < /proc/loadavg &&
           [[ "$load1" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

            LPD_EVIDENCE_CPU_LOAD1="$load1"

        fi

    fi


    #
    # CPU busy
    #

    local sample_1=""
    local sample_2=""


    if sample_1=$(
        lpd_evidence_cpu_stat_sample
    ); then

        local total_1=0
        local idle_1=0


        read -r \
            total_1 \
            idle_1 \
            <<< "$sample_1"


        sleep 1


        if sample_2=$(
            lpd_evidence_cpu_stat_sample
        ); then

            local total_2=0
            local idle_2=0


            read -r \
                total_2 \
                idle_2 \
                <<< "$sample_2"


            local total_delta=0
            local idle_delta=0


            total_delta=$((total_2 - total_1))
            idle_delta=$((idle_2 - idle_1))


            if (( total_delta > 0 &&
                  idle_delta >= 0 &&
                  idle_delta <= total_delta )); then

                LPD_EVIDENCE_CPU_BUSY=$(
                    awk \
                        -v total="$total_delta" \
                        -v idle="$idle_delta" \
                        'BEGIN {
                            printf "%.1f", ((total - idle) * 100) / total
                        }'
                )

            fi

        fi

    fi


    #
    # CPU PSI
    #

    if [[ -r /proc/pressure/cpu ]]; then

        local psi=""

        psi=$(
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


        if [[ "$psi" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

            LPD_EVIDENCE_CPU_PSI="$psi"

        fi

    fi


    #
    # Stable top CPU process.
    #
    # Excludes short-lived collection helpers.
    #

    if command_exists ps; then

        local candidates=""

        candidates=$(
            ps -eo pid=,comm=,pcpu= \
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

                        print $1,$2,$3

                        count++

                        if (count >= 10)
                            exit
                    }
                '
        )


        local pid=""
        local command=""
        local cpu_usage=""


        while read -r \
            pid \
            command \
            cpu_usage
        do

            [[ "$pid" =~ ^[0-9]+$ ]] || continue


            if declare -F lpd_capture_pid_identity >/dev/null 2>&1; then

                if ! lpd_capture_pid_identity \
                    "$pid" \
                    "$command" \
                    >/dev/null
                then
                    continue
                fi

            fi


            LPD_EVIDENCE_CPU_TOP_PID="$pid"
            LPD_EVIDENCE_CPU_TOP_COMMAND="$command"
            LPD_EVIDENCE_CPU_TOP_USAGE="$cpu_usage"

            break

        done <<< "$candidates"

    fi


    return 0
}


#
# ------------------------------------------------------------
# MEMORY EVIDENCE
# ------------------------------------------------------------
#

lpd_collect_memory_evidence() {

    LPD_EVIDENCE_MEMORY_AVAILABLE="N/A"
    LPD_EVIDENCE_MEMORY_SWAP_USED="N/A"

    LPD_EVIDENCE_MEMORY_PSI_SOME="N/A"
    LPD_EVIDENCE_MEMORY_PSI_FULL="N/A"

    LPD_EVIDENCE_MEMORY_TOP_PID="N/A"
    LPD_EVIDENCE_MEMORY_TOP_COMMAND="N/A"

    LPD_EVIDENCE_MEMORY_TOP_PERCENT="N/A"
    LPD_EVIDENCE_MEMORY_TOP_RSS_MB="N/A"


    #
    # meminfo
    #

    if [[ -r /proc/meminfo ]]; then

        local values=""

        values=$(
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

                    swap_used_pct=0

                    if (have_swap_total && have_swap_free && swap_total > 0) {

                        if (swap_free < 0) exit 1
                        if (swap_free > swap_total) exit 1

                        swap_used_pct=((swap_total - swap_free) * 100) / swap_total
                    }

                    printf "%.1f %.1f\n", available_pct, swap_used_pct
                }
            ' /proc/meminfo 2>/dev/null
        )


        if [[ -n "$values" ]]; then

            read -r \
                LPD_EVIDENCE_MEMORY_AVAILABLE \
                LPD_EVIDENCE_MEMORY_SWAP_USED \
                <<< "$values"

        fi

    fi


    #
    # Memory PSI
    #

    if [[ -r /proc/pressure/memory ]]; then

        local psi_some=""
        local psi_full=""


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
            ' /proc/pressure/memory 2>/dev/null
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
            ' /proc/pressure/memory 2>/dev/null
        )


        if [[ "$psi_some" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

            LPD_EVIDENCE_MEMORY_PSI_SOME="$psi_some"

        fi


        if [[ "$psi_full" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

            LPD_EVIDENCE_MEMORY_PSI_FULL="$psi_full"

        fi

    fi


    #
    # Stable largest RSS process
    #

    if command_exists ps; then

        local candidates=""

        candidates=$(
            ps -eo pid=,comm=,pmem=,rss= \
                --sort=-rss \
                2>/dev/null |
            awk \
                -v self="$$" \
                -v parent="$PPID" '
                    $1 != self &&
                    $1 != parent &&
                    $2 != "ps" &&
                    $2 != "awk" {

                        print $1,$2,$3,$4

                        count++

                        if (count >= 10)
                            exit
                    }
                '
        )


        local pid=""
        local command=""

        local memory_percent=""
        local rss_kb=""


        while read -r \
            pid \
            command \
            memory_percent \
            rss_kb
        do

            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            [[ "$rss_kb" =~ ^[0-9]+$ ]] || continue


            if declare -F lpd_capture_pid_identity >/dev/null 2>&1; then

                if ! lpd_capture_pid_identity \
                    "$pid" \
                    "$command" \
                    >/dev/null
                then
                    continue
                fi

            fi


            LPD_EVIDENCE_MEMORY_TOP_PID="$pid"
            LPD_EVIDENCE_MEMORY_TOP_COMMAND="$command"

            LPD_EVIDENCE_MEMORY_TOP_PERCENT="$memory_percent"


            LPD_EVIDENCE_MEMORY_TOP_RSS_MB=$(
                awk \
                    -v rss="$rss_kb" \
                    'BEGIN {
                        printf "%.1f", rss / 1024
                    }'
            )


            break

        done <<< "$candidates"

    fi


    return 0
}


#
# ------------------------------------------------------------
# DISK EVIDENCE
# ------------------------------------------------------------
#

lpd_collect_disk_evidence() {

    LPD_EVIDENCE_ROOT_USAGE="N/A"
    LPD_EVIDENCE_LAB_USAGE="N/A"

    LPD_EVIDENCE_DISK_DEVICE="N/A"

    LPD_EVIDENCE_DISK_UTIL="N/A"
    LPD_EVIDENCE_DISK_RAWAIT="N/A"
    LPD_EVIDENCE_DISK_WAWAIT="N/A"
    LPD_EVIDENCE_DISK_QUEUE="N/A"


    if command_exists df; then

        local root_usage=""

        root_usage=$(
            df -P / 2>/dev/null |
            awk '
                NR == 2 {
                    gsub("%","",$5)

                    print $5

                    exit
                }
            '
        )


        if [[ "$root_usage" =~ ^[0-9]+$ ]]; then
            LPD_EVIDENCE_ROOT_USAGE="$root_usage"
        fi


        local project_usage=""

        project_usage=$(
            df -P "$ROOT_DIR" 2>/dev/null |
            awk '
                NR == 2 {
                    gsub("%","",$5)

                    print $5

                    exit
                }
            '
        )


        if [[ "$project_usage" =~ ^[0-9]+$ ]]; then
            LPD_EVIDENCE_LAB_USAGE="$project_usage"
        fi

    fi


    if ! command_exists iostat; then
        return 0
    fi


    local io_data=""

    io_data=$(
        LC_ALL=C iostat -dx 1 2 2>/dev/null |
        awk '
            /^Device/ {
                report++

                if (report == 2) {

                    delete column

                    for (i = 1; i <= NF; i++)
                        column[$i]=i
                }

                next
            }

            report == 2 && NF > 1 {

                device=$1

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

                print device,rawait,wawait,queue,util
            }
        '
    )


    local best_util="-1"

    local device=""
    local rawait="0"
    local wawait="0"

    local queue="0"
    local util="0"


    while read -r \
        device \
        rawait \
        wawait \
        queue \
        util
    do

        [[ -n "$device" ]] || continue

        [[ -e "/sys/block/$device" ]] || continue


        case "$device" in

            loop*|sr*)
                continue
                ;;

        esac


        if awk \
            -v current="$util" \
            -v best="$best_util" \
            'BEGIN {
                if (current > best) exit 0
                exit 1
            }'
        then

            best_util="$util"

            LPD_EVIDENCE_DISK_DEVICE="$device"

            LPD_EVIDENCE_DISK_RAWAIT="$rawait"
            LPD_EVIDENCE_DISK_WAWAIT="$wawait"

            LPD_EVIDENCE_DISK_QUEUE="$queue"
            LPD_EVIDENCE_DISK_UTIL="$util"

        fi

    done <<< "$io_data"


    return 0
}


#
# ------------------------------------------------------------
# NETWORK EVIDENCE
# ------------------------------------------------------------
#

lpd_collect_network_evidence() {

    LPD_EVIDENCE_NETWORK_ESTABLISHED="N/A"
    LPD_EVIDENCE_NETWORK_TIME_WAIT="N/A"

    LPD_EVIDENCE_NETWORK_SYN_SENT="N/A"
    LPD_EVIDENCE_NETWORK_SYN_RECV="N/A"

    LPD_EVIDENCE_NETWORK_RETRANS="${LPD_NETWORK_BEFORE_RETRANS:-N/A}"

    LPD_EVIDENCE_NETWORK_TRACE_STATUS="${LPD_NETWORK_TRACE_STATUS:-NOT_RUN}"

    LPD_EVIDENCE_NETWORK_CONNECTS="${LPD_NETWORK_TOTAL_CONNECTS:-N/A}"

    LPD_EVIDENCE_NETWORK_TOP_PID="${LPD_NETWORK_PID:-N/A}"
    LPD_EVIDENCE_NETWORK_TOP_COMMAND="${LPD_NETWORK_COMMAND:-N/A}"


    #
    # Prefer shared trusted helper.
    #

    if declare -F network_ss_count >/dev/null 2>&1; then

        local value=""


        if value=$(network_ss_count established); then
            LPD_EVIDENCE_NETWORK_ESTABLISHED="$value"
        fi


        if value=$(network_ss_count time-wait); then
            LPD_EVIDENCE_NETWORK_TIME_WAIT="$value"
        fi


        if value=$(network_ss_count syn-sent); then
            LPD_EVIDENCE_NETWORK_SYN_SENT="$value"
        fi


        if value=$(network_ss_count syn-recv); then
            LPD_EVIDENCE_NETWORK_SYN_RECV="$value"
        fi


        return 0
    fi


    if ! command_exists ss; then
        return 0
    fi


    local output=""


    if output=$(ss -Htan state established 2>/dev/null); then

        LPD_EVIDENCE_NETWORK_ESTABLISHED=$(
            awk 'END {print NR + 0}' <<< "$output"
        )

    fi


    if output=$(ss -Htan state time-wait 2>/dev/null); then

        LPD_EVIDENCE_NETWORK_TIME_WAIT=$(
            awk 'END {print NR + 0}' <<< "$output"
        )

    fi


    if output=$(ss -Htan state syn-sent 2>/dev/null); then

        LPD_EVIDENCE_NETWORK_SYN_SENT=$(
            awk 'END {print NR + 0}' <<< "$output"
        )

    fi


    if output=$(ss -Htan state syn-recv 2>/dev/null); then

        LPD_EVIDENCE_NETWORK_SYN_RECV=$(
            awk 'END {print NR + 0}' <<< "$output"
        )

    fi


    return 0
}


#
# ------------------------------------------------------------
# FD EVIDENCE
# ------------------------------------------------------------
#

lpd_evidence_fd_count() {

    local pid="${1:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || {

        echo 0

        return 0
    }


    [[ -d "/proc/$pid/fd" ]] || {

        echo 0

        return 0
    }


    (
        shopt -s nullglob

        local descriptors=(
            /proc/"$pid"/fd/*
        )

        printf "%s\n" "${#descriptors[@]}"
    )
}


lpd_collect_fd_evidence() {

    LPD_EVIDENCE_FD_PID="N/A"
    LPD_EVIDENCE_FD_COMMAND="N/A"

    LPD_EVIDENCE_FD_COUNT=0
    LPD_EVIDENCE_FD_SOFT=0

    LPD_EVIDENCE_FD_RATIO="0.0"


    local highest_ratio="0.0"

    local proc_dir=""
    local pid=""


    for proc_dir in /proc/[0-9]*; do

        pid="${proc_dir##*/}"


        [[ -r "$proc_dir/limits" ]] || continue
        [[ -d "$proc_dir/fd" ]] || continue


        local soft=""

        soft=$(
            awk '
                $1 == "Max" &&
                $2 == "open" &&
                $3 == "files" {

                    print $4

                    exit
                }
            ' "$proc_dir/limits" 2>/dev/null
        )


        [[ "$soft" =~ ^[0-9]+$ ]] || continue

        (( soft > 0 )) || continue


        local count=0

        count=$(
            lpd_evidence_fd_count "$pid"
        )


        [[ "$count" =~ ^[0-9]+$ ]] || continue


        local ratio="0.0"

        ratio=$(
            awk \
                -v count="$count" \
                -v limit="$soft" \
                'BEGIN {
                    if (limit <= 0) {
                        print "0.0"
                        exit
                    }

                    printf "%.1f", (count * 100) / limit
                }'
        )


        if awk \
            -v current="$ratio" \
            -v highest="$highest_ratio" \
            'BEGIN {
                if (current > highest) exit 0
                exit 1
            }'
        then

            local command=""


            if declare -F lpd_pid_command >/dev/null 2>&1; then

                command=$(
                    lpd_pid_command "$pid" 2>/dev/null
                ) || continue

            else

                command=$(
                    cat "$proc_dir/comm" 2>/dev/null
                )


                [[ -n "$command" ]] || continue

            fi


            highest_ratio="$ratio"

            LPD_EVIDENCE_FD_PID="$pid"
            LPD_EVIDENCE_FD_COMMAND="$command"

            LPD_EVIDENCE_FD_COUNT="$count"
            LPD_EVIDENCE_FD_SOFT="$soft"

            LPD_EVIDENCE_FD_RATIO="$ratio"

        fi

    done


    return 0
}


#
# ------------------------------------------------------------
# COLLECT ALL POST-RUN EVIDENCE
# ------------------------------------------------------------
#

lpd_collect_all_evidence() {

    local failures=0


    lpd_collect_cpu_evidence ||
        failures=$((failures + 1))


    lpd_collect_memory_evidence ||
        failures=$((failures + 1))


    lpd_collect_disk_evidence ||
        failures=$((failures + 1))


    lpd_collect_network_evidence ||
        failures=$((failures + 1))


    lpd_collect_fd_evidence ||
        failures=$((failures + 1))


    if (( failures > 0 )); then

        lpd_audit \
            "WARNING" \
            "evidence" \
            "EVIDENCE_PARTIAL" \
            "failed_collectors=$failures"


        return 1
    fi


    lpd_audit \
        "INFO" \
        "evidence" \
        "EVIDENCE_COLLECTED" \
        "post-run system snapshot collected"


    return 0
}
