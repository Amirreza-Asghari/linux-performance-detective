#!/usr/bin/env bash


disk_diagnose() {

    section "Disk Deep Diagnosis"


    #
    # ------------------------------------------------------------
    # CONFIG
    # ------------------------------------------------------------
    #

    local util_warn="${DISK_UTIL_WARN_PCT:-80}"
    local util_critical="${DISK_UTIL_CRITICAL_PCT:-95}"

    local await_warn="${DISK_AWAIT_WARN_MS:-20}"
    local await_critical="${DISK_AWAIT_CRITICAL_MS:-100}"

    local queue_warn="${DISK_QUEUE_WARN:-1}"
    local queue_critical="${DISK_QUEUE_CRITICAL:-2}"

    local culprit_medium="${DISK_CULPRIT_MEDIUM_KBPS:-512}"
    local culprit_high="${DISK_CULPRIT_HIGH_KBPS:-1024}"


    if ! command_exists iostat; then

        fail "iostat is required for disk diagnosis"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # I/O PSI
    # ------------------------------------------------------------
    #

    local psi_some="0.00"
    local psi_full="0.00"


    if [[ -r /proc/pressure/io ]]; then

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
            ' /proc/pressure/io
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
            ' /proc/pressure/io
        )

    fi


    psi_some="${psi_some:-0.00}"
    psi_full="${psi_full:-0.00}"


    #
    # ------------------------------------------------------------
    # IOSTAT
    # ------------------------------------------------------------
    #

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

                rs=0
                ws=0

                rawait=0
                wawait=0

                queue=0
                util=0

                if (column["r/s"])
                    rs=$(column["r/s"])

                if (column["w/s"])
                    ws=$(column["w/s"])

                if (column["r_await"])
                    rawait=$(column["r_await"])

                if (column["w_await"])
                    wawait=$(column["w_await"])

                if (column["aqu-sz"])
                    queue=$(column["aqu-sz"])

                if (column["%util"])
                    util=$(column["%util"])

                print device,rs,ws,rawait,wawait,queue,util
            }
        '
    )


    local selected_device=""

    local selected_reads="0"
    local selected_writes="0"

    local selected_rawait="0"
    local selected_wawait="0"

    local selected_queue="0"
    local selected_util="0"

    local best_score="-1"


    local device=""
    local reads="0"
    local writes="0"

    local rawait="0"
    local wawait="0"

    local queue="0"
    local util="0"


    while read -r \
        device \
        reads \
        writes \
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


        local score="0"


        score=$(
            awk \
                -v util="$util" \
                -v r="$rawait" \
                -v w="$wawait" \
                -v q="$queue" \
                'BEGIN {
                    maxawait=r

                    if (w > maxawait)
                        maxawait=w

                    printf "%.2f", util + (maxawait * 2) + (q * 10)
                }'
        )


        if awk \
            -v current="$score" \
            -v best="$best_score" \
            'BEGIN {
                if (current > best)
                    exit 0

                exit 1
            }'
        then

            best_score="$score"

            selected_device="$device"

            selected_reads="$reads"
            selected_writes="$writes"

            selected_rawait="$rawait"
            selected_wawait="$wawait"

            selected_queue="$queue"
            selected_util="$util"
        fi

    done <<< "$io_data"


    if [[ -z "$selected_device" ]]; then

        fail "Unable to identify a block device for diagnosis"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # TOP I/O PROCESS
    # ------------------------------------------------------------
    #

    local process=""

    local pid="N/A"
    local command="N/A"

    local read_rate="0.00"
    local write_rate="0.00"

    local io_delay="0"


    if command_exists pidstat; then

        process=$(
            LC_ALL=C pidstat -d 1 2 2>/dev/null |
            awk '
                $1 == "Average:" &&
                $3 ~ /^[0-9]+$/ {

                    total=$4+$5

                    if (total > max) {
                        max=total

                        pid=$3

                        readrate=$4
                        writerate=$5

                        delay=$7

                        command=$NF
                    }
                }

                END {
                    if (max > 0)
                        print pid,command,readrate,writerate,delay
                }
            '
        )


        if [[ -n "$process" ]]; then

            read -r \
                pid \
                command \
                read_rate \
                write_rate \
                io_delay \
                <<< "$process"

        fi

    fi


    #
    # ------------------------------------------------------------
    # PID IDENTITY
    # ------------------------------------------------------------
    #

    local start_time="N/A"


    if [[ "$pid" =~ ^[0-9]+$ ]]; then

        start_time=$(
            lpd_capture_pid_identity \
                "$pid" \
                "$command"
        ) || start_time="N/A"

    fi


    #
    # ------------------------------------------------------------
    # DISPLAY
    # ------------------------------------------------------------
    #

    echo "Finding: DISK_IO_PRESSURE"

    echo

    printf "Device:              %s\n" "$selected_device"

    printf "Reads/sec:           %s\n" "$selected_reads"
    printf "Writes/sec:          %s\n" "$selected_writes"

    printf "Read await:          %s ms\n" "$selected_rawait"
    printf "Write await:         %s ms\n" "$selected_wawait"

    printf "Queue depth:         %s\n" "$selected_queue"
    printf "Utilization:         %s%%\n" "$selected_util"

    printf "I/O PSI some:        %s%%\n" "$psi_some"
    printf "I/O PSI full:        %s%%\n" "$psi_full"


    echo
    echo "Top I/O process:"

    printf "PID:                 %s\n" "$pid"
    printf "Command:             %s\n" "$command"

    printf "Read rate:           %s KB/s\n" "$read_rate"
    printf "Write rate:          %s KB/s\n" "$write_rate"

    printf "I/O delay:           %s\n" "$io_delay"


    #
    # ------------------------------------------------------------
    # SAVE EVIDENCE
    # ------------------------------------------------------------
    #

    LPD_DISK_DEVICE="$selected_device"

    LPD_DISK_BEFORE_RAWAIT="$selected_rawait"
    LPD_DISK_BEFORE_WAWAIT="$selected_wawait"

    LPD_DISK_BEFORE_QUEUE="$selected_queue"
    LPD_DISK_BEFORE_UTIL="$selected_util"

    LPD_DISK_PID="$pid"
    LPD_DISK_COMMAND="$command"

    LPD_DISK_READ_RATE="$read_rate"
    LPD_DISK_WRITE_RATE="$write_rate"

    LPD_DISK_PID_START="$start_time"


    #
    # ------------------------------------------------------------
    # CULPRIT CONFIDENCE
    # ------------------------------------------------------------
    #

    local confidence="LOW"


    if [[ "$pid" =~ ^[0-9]+$ ]] &&
       [[ "$start_time" != "N/A" ]]; then


        if awk \
            -v util="$selected_util" \
            -v readrate="$read_rate" \
            -v writerate="$write_rate" \
            -v utilwarn="$util_warn" \
            -v high="$culprit_high" \
            'BEGIN {
                if (util >= utilwarn &&
                    (readrate + writerate) >= high)
                    exit 0

                exit 1
            }'
        then

            confidence="HIGH"


        elif awk \
            -v readrate="$read_rate" \
            -v writerate="$write_rate" \
            -v medium="$culprit_medium" \
            'BEGIN {
                if ((readrate + writerate) >= medium)
                    exit 0

                exit 1
            }'
        then

            confidence="MEDIUM"

        fi

    fi


    LPD_DISK_CONFIDENCE="$confidence"


    #
    # ------------------------------------------------------------
    # SEVERITY
    # ------------------------------------------------------------
    #

    local severity="OK"

    local diagnosis="No actionable disk I/O pressure detected"


    if awk \
        -v util="$selected_util" \
        -v r="$selected_rawait" \
        -v w="$selected_wawait" \
        -v q="$selected_queue" \
        -v utilcrit="$util_critical" \
        -v awaitcrit="$await_critical" \
        -v queuecrit="$queue_critical" \
        'BEGIN {
            if (util >= utilcrit && q >= queuecrit) exit 0
            if (r >= awaitcrit) exit 0
            if (w >= awaitcrit) exit 0

            exit 1
        }'
    then

        severity="CRITICAL"

        diagnosis="Severe disk I/O pressure detected"


    elif awk \
        -v util="$selected_util" \
        -v r="$selected_rawait" \
        -v w="$selected_wawait" \
        -v q="$selected_queue" \
        -v utilwarn="$util_warn" \
        -v awaitwarn="$await_warn" \
        -v queuewarn="$queue_warn" \
        'BEGIN {
            if (util >= utilwarn) exit 0
            if (r >= awaitwarn) exit 0
            if (w >= awaitwarn) exit 0
            if (q >= queuewarn) exit 0

            exit 1
        }'
    then

        severity="WARNING"

        diagnosis="Elevated disk I/O activity or latency detected"

    fi


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
