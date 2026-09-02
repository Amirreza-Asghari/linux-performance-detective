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
    # Inspect several CPU-heavy processes instead of trusting only
    # the first PID returned by ps.
    #
    # This allows LPD to distinguish between single-process and
    # multi-process CPU saturation.
    #
    # Every process candidate must also pass PID identity
    # validation before its observations are trusted.
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

                print $1, $2, $3, $4, $5

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
    # STABLE CANDIDATE ANALYSIS
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
    local candidate_start=""

    local unstable_candidates=0
    local saturation_count=0

    local -a saturated_pids=()
    local -a saturated_commands=()
    local -a saturated_cpu_values=()


    while read -r \
        candidate_pid \
        candidate_command \
        candidate_cpu \
        candidate_state \
        candidate_nice
    do

        [[ "$candidate_pid" =~ ^[0-9]+$ ]] || continue


        #
        # LPD must never diagnose itself or its direct parent
        # as the CPU culprit.
        #

        if (( candidate_pid == $$ ||
              candidate_pid == PPID )); then

            continue
        fi


        #
        # Capture PID identity safely.
        #
        # lpd_capture_pid_identity validates the observed PID and
        # command and returns the /proc starttime used later to
        # protect remediation against PID reuse.
        #

        candidate_start=$(
            lpd_capture_pid_identity \
                "$candidate_pid" \
                "$candidate_command"
        ) || {

            unstable_candidates=$((unstable_candidates + 1))

            continue
        }


        #
        # Keep the highest stable CPU consumer as the primary
        # evidence/remediation target.
        #

        if [[ "$pid" == "N/A" ]]; then

            pid="$candidate_pid"
            command="$candidate_command"
            cpu_usage="$candidate_cpu"
            state="$candidate_state"
            nice_value="$candidate_nice"
            start_time="$candidate_start"

        fi


        #
        # Count every stable process independently reaching the
        # configured per-process saturation threshold.
        #

        if awk \
            -v cpu="$candidate_cpu" \
            -v threshold="$saturation_threshold" \
            'BEGIN {
                if ((cpu + 0) >= (threshold + 0))
                    exit 0

                exit 1
            }'
        then

            saturated_pids+=("$candidate_pid")
            saturated_commands+=("$candidate_command")
            saturated_cpu_values+=("$candidate_cpu")

            saturation_count=$((saturation_count + 1))

        fi

    done <<< "$candidates"


    #
    # Every candidate disappeared or became inaccessible.
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
    # SAVE WORKFLOW EVIDENCE
    # ------------------------------------------------------------
    #
    # These variables are intentionally consumed by other LPD
    # workflow modules after cpu_diagnose returns.
    #

    # shellcheck disable=SC2034
    LPD_CPU_PID="$pid"

    # shellcheck disable=SC2034
    LPD_CPU_COMMAND="$command"

    # shellcheck disable=SC2034
    LPD_CPU_USAGE="$cpu_usage"

    # shellcheck disable=SC2034
    LPD_CPU_PID_START="$start_time"

    # shellcheck disable=SC2034
    LPD_CPU_SATURATION_COUNT="$saturation_count"


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
    # MULTI-PROCESS SATURATION
    # ------------------------------------------------------------
    #

    if (( saturation_count >= 2 )); then

        echo
        echo "CPU-intensive processes:"
        echo

        printf "%-10s %-24s %-10s\n" \
            "PID" \
            "COMMAND" \
            "CPU"

        printf "%-10s %-24s %-10s\n" \
            "----------" \
            "------------------------" \
            "----------"


        local index=0

        for (( index = 0; index < saturation_count; index++ )); do

            printf "%-10s %-24s %s%%\n" \
                "${saturated_pids[$index]}" \
                "${saturated_commands[$index]}" \
                "${saturated_cpu_values[$index]}"

        done


        echo
        echo "Diagnosis:           Multi-process CPU saturation"
        printf "Saturated processes: %s\n" "$saturation_count"
        echo "Culprit confidence:  HIGH"

        warn \
            "Multiple processes are each consuming approximately one full CPU core"


        return 1
    fi


    #
    # ------------------------------------------------------------
    # SINGLE-PROCESS SATURATION
    # ------------------------------------------------------------
    #

    if (( saturation_count == 1 )); then

        echo
        echo "Diagnosis:           Single-process CPU saturation"
        echo "Saturated processes: 1"
        echo "Culprit confidence:  HIGH"

        warn \
            "One process is consuming approximately one full CPU core"


        return 1
    fi


    #
    # ------------------------------------------------------------
    # NO DOMINANT PROCESS
    # ------------------------------------------------------------
    #

    echo
    echo "Diagnosis:           No dominant CPU culprit identified"
    echo "Saturated processes: 0"
    echo "Culprit confidence:  LOW"

    info "No actionable per-process CPU saturation detected"


    return 0
}
