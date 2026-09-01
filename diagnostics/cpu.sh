#!/usr/bin/env bash


cpu_diagnose() {

    section "CPU Deep Diagnosis"


    local saturation_threshold="${CPU_PROCESS_SATURATION_PCT:-90}"


    if ! command_exists ps; then

        fail "ps is required for CPU process diagnosis"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # CANDIDATE LIST
    # ------------------------------------------------------------
    #
    # We inspect several candidates instead of trusting one PID.
    #
    # A short-lived process may disappear between ps and /proc.
    #

    local candidates=""

    candidates=$(
        ps -eo pid=,comm=,pcpu=,stat=,ni= \
            --sort=-pcpu \
            2>/dev/null |
        awk '
            $2 != "ps" &&
            $2 != "awk" &&
            $2 != "head" {

                print $1,$2,$3,$4,$5

                count++

                if (count >= 8)
                    exit
            }
        '
    )


    if [[ -z "$candidates" ]]; then

        fail "Unable to obtain CPU process candidates"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # FIND FIRST STABLE CANDIDATE
    # ------------------------------------------------------------
    #

    local pid="N/A"
    local command="N/A"

    local cpu_usage="0"

    local state="N/A"
    local nice_value="0"

    local start_time="N/A"

    local candidate_pid=""
    local candidate_command=""

    local candidate_cpu="0"

    local candidate_state=""
    local candidate_nice="0"

    local unstable_candidates=0


    while read -r \
        candidate_pid \
        candidate_command \
        candidate_cpu \
        candidate_state \
        candidate_nice
    do

        [[ "$candidate_pid" =~ ^[0-9]+$ ]] || continue


        #
        # LPD must never diagnose itself as the culprit.
        #

        if (( candidate_pid == $$ ||
              candidate_pid == PPID )); then

            continue
        fi


        local candidate_start=""

        candidate_start=$(
            lpd_capture_pid_identity \
                "$candidate_pid" \
                "$candidate_command"
        ) || {

            unstable_candidates=$((unstable_candidates + 1))

            continue
        }


        pid="$candidate_pid"
        command="$candidate_command"

        cpu_usage="$candidate_cpu"

        state="$candidate_state"
        nice_value="$candidate_nice"

        start_time="$candidate_start"


        break

    done <<< "$candidates"


    #
    # Every observed candidate disappeared or became inaccessible.
    #

    if [[ "$pid" == "N/A" ]]; then

        fail "No stable CPU process identity could be captured"


        if declare -F lpd_audit >/dev/null 2>&1; then

            lpd_audit \
                "WARNING" \
                "cpu" \
                "TARGET_UNSTABLE" \
                "candidates_failed=$unstable_candidates"

        fi


        return 3
    fi


    #
    # ------------------------------------------------------------
    # OPTIONAL CMDLINE
    # ------------------------------------------------------------
    #

    local cmdline="N/A"


    if [[ -r "/proc/$pid/cmdline" ]]; then

        cmdline=$(
            tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null
        )

        cmdline="${cmdline:-N/A}"

    fi


    #
    # ------------------------------------------------------------
    # SAVE EVIDENCE
    # ------------------------------------------------------------
    #

    LPD_CPU_PID="$pid"
    LPD_CPU_COMMAND="$command"

    LPD_CPU_USAGE="$cpu_usage"

    LPD_CPU_STATE="$state"
    LPD_CPU_NICE="$nice_value"

    LPD_CPU_PID_START="$start_time"


    #
    # ------------------------------------------------------------
    # OUTPUT
    # ------------------------------------------------------------
    #

    echo

    printf "PID:                 %s\n" "$pid"
    printf "Command:             %s\n" "$command"

    printf "CPU usage:           %s%%\n" "$cpu_usage"

    printf "State:               %s\n" "$state"
    printf "Nice value:          %s\n" "$nice_value"

    printf "Command line:        %s\n" "$cmdline"


    #
    # ------------------------------------------------------------
    # CLASSIFICATION
    # ------------------------------------------------------------
    #

    if awk \
        -v cpu="$cpu_usage" \
        -v threshold="$saturation_threshold" \
        'BEGIN {
            if (cpu >= threshold)
                exit 0

            exit 1
        }'
    then

        echo

        echo "Diagnosis:           Single-process CPU saturation"
        echo "Culprit confidence:  HIGH"

        warn "One process is consuming approximately one full CPU core"


        return 1
    fi


    echo

    echo "Diagnosis:           No dominant CPU culprit identified"
    echo "Culprit confidence:  LOW"

    info "No actionable single-process CPU saturation detected"


    return 0
}
