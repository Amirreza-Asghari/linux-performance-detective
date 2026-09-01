#!/usr/bin/env bash


file_descriptor_check() {

    section "File Descriptors"


    #
    # ------------------------------------------------------------
    # CONFIGURATION
    # ------------------------------------------------------------
    #

    local process_warn="${FD_PROCESS_WARN_PCT:-80}"
    local process_critical="${FD_PROCESS_CRITICAL_PCT:-95}"

    local system_warn="${FD_SYSTEM_WARN_PCT:-80}"
    local system_critical="${FD_SYSTEM_CRITICAL_PCT:-95}"


    #
    # ------------------------------------------------------------
    # SYSTEM FILE HANDLES
    # ------------------------------------------------------------
    #

    local allocated=0
    local unused=0
    local maximum=0

    local in_use=0


    if [[ ! -r /proc/sys/fs/file-nr ]]; then

        fail "Unable to read /proc/sys/fs/file-nr"

        return 3
    fi


    read -r \
        allocated \
        unused \
        maximum \
        < /proc/sys/fs/file-nr


    allocated="${allocated:-0}"
    unused="${unused:-0}"
    maximum="${maximum:-0}"


    in_use=$((allocated - unused))


    if (( in_use < 0 )); then
        in_use=0
    fi


    echo "System file handles:"

    printf "Allocated:           %s\n" "$allocated"
    printf "Unused allocated:    %s\n" "$unused"

    printf "In use:              %s\n" "$in_use"
    printf "Maximum:             %s\n" "$maximum"


    local system_ratio="N/A"
    local system_percent_check=1


    #
    # Some modern kernels expose an effectively-unbounded
    # file-max value such as signed/unsigned integer maxima.
    #
    # These are sentinel-like kernel values, not useful capacity
    # ceilings. Producing a tiny percentage from them would imply
    # precision that does not exist.
    #

    case "$maximum" in

        9223372036854775807|18446744073709551615)

            system_percent_check=0

            info "System file handle maximum is effectively very large; percentage check skipped"
            ;;

    esac


    if (( system_percent_check == 1 )); then

        if [[ "$maximum" =~ ^[0-9]+$ ]] &&
           (( maximum > 0 )); then

            system_ratio=$(
                awk \
                    -v used="$in_use" \
                    -v max="$maximum" \
                    'BEGIN {
                        printf "%.1f", (used * 100) / max
                    }'
            )


            printf "Utilization:         %s%%\n" "$system_ratio"

        else

            warn "System file handle maximum is invalid"

            return 3
        fi

    fi


    #
    # ------------------------------------------------------------
    # PROCESS SCAN
    # ------------------------------------------------------------
    #

    local highest_count=0
    local highest_count_pid="N/A"
    local highest_count_command="N/A"

    local highest_count_soft="N/A"
    local highest_count_hard="N/A"


    local highest_ratio="0.0"
    local highest_ratio_pid="N/A"
    local highest_ratio_command="N/A"

    local highest_ratio_count=0
    local highest_ratio_soft="N/A"
    local highest_ratio_hard="N/A"


    local processes_scanned=0


    local proc=""
    local pid=""

    local command=""

    local fd_dir=""
    local fd=""

    local fd_count=0

    local soft_limit=""
    local hard_limit=""

    local ratio="0.0"


    for proc in /proc/[0-9]*; do

        [[ -d "$proc" ]] || continue


        pid="${proc##*/}"


        [[ "$pid" =~ ^[0-9]+$ ]] || continue


        fd_dir="$proc/fd"


        [[ -d "$fd_dir" ]] || continue
        [[ -r "$proc/limits" ]] || continue


        command=$(
            cat "$proc/comm" 2>/dev/null
        )


        [[ -n "$command" ]] || continue


        fd_count=0


        for fd in "$fd_dir"/*; do

            [[ -e "$fd" ]] || continue

            fd_count=$((fd_count + 1))
        done


        local limits=""

        limits=$(
            awk '
                $1 == "Max" &&
                $2 == "open" &&
                $3 == "files" {

                    print $4,$5

                    exit
                }
            ' "$proc/limits" 2>/dev/null
        )


        [[ -n "$limits" ]] || continue


        read -r \
            soft_limit \
            hard_limit \
            <<< "$limits"


        processes_scanned=$((processes_scanned + 1))


        #
        # Highest absolute FD count
        #

        if (( fd_count > highest_count )); then

            highest_count="$fd_count"

            highest_count_pid="$pid"
            highest_count_command="$command"

            highest_count_soft="$soft_limit"
            highest_count_hard="$hard_limit"
        fi


        #
        # Ratio is meaningful only for a finite numeric soft limit.
        #

        if [[ "$soft_limit" =~ ^[0-9]+$ ]] &&
           (( soft_limit > 0 )); then

            ratio=$(
                awk \
                    -v open="$fd_count" \
                    -v limit="$soft_limit" \
                    'BEGIN {
                        printf "%.1f", (open * 100) / limit
                    }'
            )


            if awk \
                -v current="$ratio" \
                -v highest="$highest_ratio" \
                'BEGIN {
                    if (current > highest)
                        exit 0

                    exit 1
                }'
            then

                highest_ratio="$ratio"

                highest_ratio_pid="$pid"
                highest_ratio_command="$command"

                highest_ratio_count="$fd_count"

                highest_ratio_soft="$soft_limit"
                highest_ratio_hard="$hard_limit"
            fi

        fi

    done


    echo

    printf "Processes scanned:    %s\n" "$processes_scanned"


    if (( processes_scanned == 0 )); then

        fail "No process file descriptor information could be collected"

        return 3
    fi


    echo
    echo "Highest FD count:"

    printf "PID:                 %s\n" "$highest_count_pid"
    printf "Command:             %s\n" "$highest_count_command"

    printf "Open FDs:            %s\n" "$highest_count"

    printf "Soft limit:          %s\n" "$highest_count_soft"
    printf "Hard limit:          %s\n" "$highest_count_hard"


    echo
    echo "Highest FD utilization:"

    printf "PID:                 %s\n" "$highest_ratio_pid"
    printf "Command:             %s\n" "$highest_ratio_command"

    printf "Open FDs:            %s\n" "$highest_ratio_count"

    printf "Soft limit:          %s\n" "$highest_ratio_soft"
    printf "Hard limit:          %s\n" "$highest_ratio_hard"

    printf "Utilization:         %s%%\n" "$highest_ratio"


    #
    # ------------------------------------------------------------
    # CRITICAL
    # ------------------------------------------------------------
    #

    if awk \
        -v process="$highest_ratio" \
        -v processcrit="$process_critical" \
        'BEGIN {
            if (process >= processcrit)
                exit 0

            exit 1
        }'
    then

        echo

        fail "Critical process file descriptor pressure detected"

        return 2
    fi


    if (( system_percent_check == 1 )); then

        if awk \
            -v systempct="$system_ratio" \
            -v systemcrit="$system_critical" \
            'BEGIN {
                if (systempct >= systemcrit)
                    exit 0

                exit 1
            }'
        then

            echo

            fail "Critical system-wide file handle pressure detected"

            return 2
        fi

    fi


    #
    # ------------------------------------------------------------
    # WARNING
    # ------------------------------------------------------------
    #

    if awk \
        -v process="$highest_ratio" \
        -v processwarn="$process_warn" \
        'BEGIN {
            if (process >= processwarn)
                exit 0

            exit 1
        }'
    then

        echo

        warn "Process file descriptor utilization requires attention"

        return 1
    fi


    if (( system_percent_check == 1 )); then

        if awk \
            -v systempct="$system_ratio" \
            -v systemwarn="$system_warn" \
            'BEGIN {
                if (systempct >= systemwarn)
                    exit 0

                exit 1
            }'
        then

            echo

            warn "System-wide file handle utilization requires attention"

            return 1
        fi

    fi


    echo

    ok "No file descriptor pressure detected"

    echo

    ok "File descriptor subsystem is healthy"


    return 0
}
