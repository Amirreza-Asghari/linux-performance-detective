#!/usr/bin/env bash


fd_verify() {

    section "File Descriptor Verification"


    local process_warn="${FD_PROCESS_WARN_PCT:-80}"

    local pid="${LPD_FD_PID:-N/A}"
    local command="${LPD_FD_COMMAND:-N/A}"

    local expected_start="${LPD_FD_PID_START:-N/A}"

    local action="${LPD_FD_ACTION:-UNKNOWN}"


    local before_open="${LPD_FD_BEFORE_OPEN:-${LPD_FD_OPEN:-0}}"

    local before_soft="${LPD_FD_BEFORE_SOFT:-${LPD_FD_SOFT_LIMIT:-N/A}}"

    local before_ratio="${LPD_FD_BEFORE_RATIO:-${LPD_FD_RATIO:-0}}"


    info "Waiting for file descriptor state to settle..."

    sleep 2


    #
    # ------------------------------------------------------------
    # ORIGINAL TARGET STATE
    # ------------------------------------------------------------
    #

    local target_gone=0
    local target_state="unknown"


    if [[ "$pid" =~ ^[0-9]+$ ]] &&
       [[ "$expected_start" =~ ^[0-9]+$ ]]; then

        if lpd_pid_identity_valid \
            "$pid" \
            "$expected_start" \
            "$command"
        then

            target_state="running"

            warn "Original target process is still running"

        else

            target_state="terminated_or_reused"

            target_gone=1

            ok "Original target process identity is no longer active"
        fi

    fi


    #
    # ------------------------------------------------------------
    # RESCAN ALL PROCESSES
    # ------------------------------------------------------------
    #

    local highest_ratio="0.0"

    local highest_pid="N/A"
    local highest_command="N/A"

    local highest_open=0

    local highest_soft="N/A"
    local highest_hard="N/A"


    local processes_scanned=0


    local proc=""
    local current_pid=""

    local current_command=""

    local fd_dir=""
    local fd=""

    local fd_count=0

    local soft_limit=""
    local hard_limit=""

    local ratio="0.0"


    for proc in /proc/[0-9]*; do

        [[ -d "$proc" ]] || continue


        current_pid="${proc##*/}"


        [[ "$current_pid" =~ ^[0-9]+$ ]] || continue


        fd_dir="$proc/fd"


        [[ -d "$fd_dir" ]] || continue
        [[ -r "$proc/limits" ]] || continue


        current_command=$(
            cat "$proc/comm" 2>/dev/null
        )


        [[ -n "$current_command" ]] || continue


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


        if [[ ! "$soft_limit" =~ ^[0-9]+$ ]]; then
            continue
        fi


        (( soft_limit > 0 )) || continue


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

            highest_pid="$current_pid"
            highest_command="$current_command"

            highest_open="$fd_count"

            highest_soft="$soft_limit"
            highest_hard="$hard_limit"
        fi

    done


    if (( processes_scanned == 0 )); then

        fail "Unable to rescan process file descriptor state"


        lpd_record_remediation \
            "fd" \
            "FILE_DESCRIPTOR_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "open=${before_open};soft_limit=${before_soft};ratio=${before_ratio}%" \
            "verification_scan=unavailable;target_state=${target_state}" \
            "UNKNOWN" \
            "UNKNOWN"


        return 3
    fi


    echo

    printf "Original target:     %s (%s)\n" "$pid" "$command"

    printf "Before open FDs:     %s\n" "$before_open"
    printf "Before soft limit:   %s\n" "$before_soft"

    printf "Before utilization:  %s%%\n" "$before_ratio"


    echo
    echo "Highest utilization after remediation:"

    printf "PID:                 %s\n" "$highest_pid"
    printf "Command:             %s\n" "$highest_command"

    printf "Open FDs:            %s\n" "$highest_open"

    printf "Soft limit:          %s\n" "$highest_soft"
    printf "Hard limit:          %s\n" "$highest_hard"

    printf "Utilization:         %s%%\n" "$highest_ratio"


    local before_record=""

    before_record="open=${before_open};soft_limit=${before_soft};ratio=${before_ratio}%;pid=${pid};command=${command}"


    local after_record=""

    after_record="highest_pid=${highest_pid};highest_command=${highest_command};open=${highest_open};soft_limit=${highest_soft};ratio=${highest_ratio}%;target_state=${target_state}"


    #
    # ------------------------------------------------------------
    # HEALTHY AFTER STATE
    # ------------------------------------------------------------
    #

    local fd_healthy=0


    if awk \
        -v ratio="$highest_ratio" \
        -v warning="$process_warn" \
        'BEGIN {
            if (ratio < warning)
                exit 0

            exit 1
        }'
    then

        fd_healthy=1
    fi


    #
    # ------------------------------------------------------------
    # RESOLVED
    # ------------------------------------------------------------
    #

    if [[ "$action" == "SIGTERM" ]] &&
       (( target_gone == 1 )) &&
       (( fd_healthy == 1 )); then

        echo

        ok "RESOLVED - file descriptor pressure cleared"


        lpd_record_remediation \
            "fd" \
            "FILE_DESCRIPTOR_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "$after_record" \
            "RESOLVED" \
            "SUCCESS"


        return 0
    fi


    #
    # ------------------------------------------------------------
    # MITIGATED
    # ------------------------------------------------------------
    #
    # Important case:
    #
    # original offender is gone, but another process is still
    # above the configured warning threshold.
    #

    if (( target_gone == 1 )) &&
       awk \
           -v before="$before_ratio" \
           -v after="$highest_ratio" \
           'BEGIN {
               if (after < before)
                   exit 0

               exit 1
           }'
    then

        echo

        warn "MITIGATED - original offender is gone, but another process still has elevated FD utilization"


        lpd_record_remediation \
            "fd" \
            "FILE_DESCRIPTOR_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "$after_record" \
            "MITIGATED" \
            "PARTIAL"


        return 1
    fi


    #
    # A healthy state after a non-SIGTERM action can still be
    # observed, but we do not pretend an unperformed remediation
    # caused it.
    #

    if (( fd_healthy == 1 )); then

        echo

        warn "MITIGATED - current FD state is healthy, but expected remediation state was not fully verified"


        lpd_record_remediation \
            "fd" \
            "FILE_DESCRIPTOR_PRESSURE" \
            "$pid" \
            "$command" \
            "$action" \
            "$before_record" \
            "$after_record" \
            "MITIGATED" \
            "PARTIAL"


        return 1
    fi


    #
    # ------------------------------------------------------------
    # FAILED
    # ------------------------------------------------------------
    #

    echo

    fail "FAILED - file descriptor pressure remains"


    lpd_record_remediation \
        "fd" \
        "FILE_DESCRIPTOR_PRESSURE" \
        "$pid" \
        "$command" \
        "$action" \
        "$before_record" \
        "$after_record" \
        "FAILED" \
        "FAILED"


    return 2
}
