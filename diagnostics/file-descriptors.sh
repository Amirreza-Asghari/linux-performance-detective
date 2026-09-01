#!/usr/bin/env bash


fd_diagnose() {

    section "File Descriptor Deep Diagnosis"


    #
    # ------------------------------------------------------------
    # CONFIG
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

    if [[ ! -r /proc/sys/fs/file-nr ]]; then

        fail "Unable to read system file handle counters"

        return 3
    fi


    local allocated=0
    local unused=0
    local maximum=0

    local in_use=0


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


    local system_ratio="N/A"
    local system_percent_check=1


    case "$maximum" in

        9223372036854775807|18446744073709551615)

            system_percent_check=0
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

        else

            fail "Invalid system file handle maximum"

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


        if (( fd_count > highest_count )); then

            highest_count="$fd_count"

            highest_count_pid="$pid"
            highest_count_command="$command"
        fi


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


    if (( processes_scanned == 0 )); then

        fail "No process file descriptor information could be collected"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # CAPTURE TARGET IDENTITY
    # ------------------------------------------------------------
    #

    local start_time="N/A"


    if [[ "$highest_ratio_pid" =~ ^[0-9]+$ ]]; then

        start_time=$(
            lpd_capture_pid_identity \
                "$highest_ratio_pid" \
                "$highest_ratio_command"
        ) || start_time="N/A"

    fi


    #
    # ------------------------------------------------------------
    # SAVE EVIDENCE
    # ------------------------------------------------------------
    #

    LPD_FD_PID="$highest_ratio_pid"
    LPD_FD_COMMAND="$highest_ratio_command"

    LPD_FD_OPEN="$highest_ratio_count"

    LPD_FD_SOFT_LIMIT="$highest_ratio_soft"
    LPD_FD_HARD_LIMIT="$highest_ratio_hard"

    LPD_FD_RATIO="$highest_ratio"

    LPD_FD_PID_START="$start_time"


    #
    # Compatibility aliases for existing remediation/verification
    # code paths.
    #

    LPD_FD_OPEN_COUNT="$highest_ratio_count"
    LPD_FD_UTILIZATION="$highest_ratio"

    LPD_FD_BEFORE_OPEN="$highest_ratio_count"
    LPD_FD_BEFORE_SOFT="$highest_ratio_soft"
    LPD_FD_BEFORE_RATIO="$highest_ratio"


    #
    # ------------------------------------------------------------
    # OUTPUT
    # ------------------------------------------------------------
    #

    echo "Finding: FILE_DESCRIPTOR_PRESSURE"

    echo

    echo "System file handles:"

    printf "In use:              %s\n" "$in_use"
    printf "Maximum:             %s\n" "$maximum"


    if (( system_percent_check == 1 )); then

        printf "System utilization:  %s%%\n" "$system_ratio"

    else

        printf "System utilization:  N/A\n"

        info "System file handle maximum is effectively very large; percentage check skipped"
    fi


    echo

    printf "Processes scanned:    %s\n" "$processes_scanned"


    echo
    echo "Highest absolute FD count:"

    printf "PID:                 %s\n" "$highest_count_pid"
    printf "Command:             %s\n" "$highest_count_command"

    printf "Open FDs:            %s\n" "$highest_count"


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
    # CLASSIFICATION
    # ------------------------------------------------------------
    #

    local severity="OK"

    local diagnosis="No actionable file descriptor pressure detected"

    local confidence="LOW"


    if awk \
        -v ratio="$highest_ratio" \
        -v critical="$process_critical" \
        'BEGIN {
            if (ratio >= critical)
                exit 0

            exit 1
        }'
    then

        severity="CRITICAL"

        diagnosis="Critical per-process file descriptor exhaustion risk detected"

        confidence="HIGH"


    elif awk \
        -v ratio="$highest_ratio" \
        -v warning="$process_warn" \
        'BEGIN {
            if (ratio >= warning)
                exit 0

            exit 1
        }'
    then

        severity="WARNING"

        diagnosis="High per-process file descriptor utilization detected"

        confidence="HIGH"

    fi


    #
    # System-wide pressure can independently raise severity.
    #

    if (( system_percent_check == 1 )); then

        if awk \
            -v ratio="$system_ratio" \
            -v critical="$system_critical" \
            'BEGIN {
                if (ratio >= critical)
                    exit 0

                exit 1
            }'
        then

            severity="CRITICAL"

            diagnosis="Critical system-wide file handle pressure detected"


        elif [[ "$severity" == "OK" ]] &&
             awk \
                 -v ratio="$system_ratio" \
                 -v warning="$system_warn" \
                 'BEGIN {
                     if (ratio >= warning)
                         exit 0

                     exit 1
                 }'
        then

            severity="WARNING"

            diagnosis="Elevated system-wide file handle utilization detected"
        fi

    fi


    LPD_FD_CONFIDENCE="$confidence"


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
