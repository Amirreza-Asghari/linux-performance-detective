#!/usr/bin/env bash


disk_check() {

    section "Disk"


    #
    # ------------------------------------------------------------
    # CONFIGURATION
    # ------------------------------------------------------------
    #

    local fs_usage_warn="${FS_USAGE_WARN_PCT:-85}"
    local fs_usage_critical="${FS_USAGE_CRITICAL_PCT:-95}"

    local fs_inode_warn="${FS_INODE_WARN_PCT:-85}"
    local fs_inode_critical="${FS_INODE_CRITICAL_PCT:-95}"

    local util_warn="${DISK_UTIL_WARN_PCT:-80}"
    local util_critical="${DISK_UTIL_CRITICAL_PCT:-95}"

    local await_warn="${DISK_AWAIT_WARN_MS:-20}"
    local await_critical="${DISK_AWAIT_CRITICAL_MS:-100}"

    local queue_warn="${DISK_QUEUE_WARN:-1}"
    local queue_critical="${DISK_QUEUE_CRITICAL:-2}"


    local filesystem_warning=0
    local filesystem_critical=0

    local disk_warning=0
    local disk_critical=0


    #
    # ------------------------------------------------------------
    # FILESYSTEM CAPACITY
    # ------------------------------------------------------------
    #

    echo "Filesystem usage:"
    echo


    printf "%-15s %-10s %-10s %-10s\n" \
        "Mount" \
        "Type" \
        "Usage" \
        "Inodes"


    printf "%-15s %-10s %-10s %-10s\n" \
        "---------------" \
        "----------" \
        "----------" \
        "----------"


    local targets=(
        "/"
        "/tmp"
        "/var"
        "/home"
        "$ROOT_DIR"
    )


    local seen_mounts=""

    local target=""
    local mount=""
    local fstype=""

    local usage=0
    local inode_usage=0


    for target in "${targets[@]}"; do

        [[ -e "$target" ]] || continue


        mount=$(
            df -P "$target" 2>/dev/null |
            awk '
                NR == 2 {
                    print $6
                    exit
                }
            '
        )


        [[ -n "$mount" ]] || continue


        #
        # Avoid printing the same filesystem mount twice.
        #

        if grep -Fxq "$mount" <<< "$seen_mounts"; then
            continue
        fi


        seen_mounts+="${mount}"$'\n'


        fstype=$(
            findmnt -rn -T "$target" -o FSTYPE 2>/dev/null |
            head -n 1
        )


        fstype="${fstype:-unknown}"


        usage=$(
            df -P "$target" 2>/dev/null |
            awk '
                NR == 2 {
                    gsub("%","",$5)
                    print $5
                    exit
                }
            '
        )


        inode_usage=$(
            df -Pi "$target" 2>/dev/null |
            awk '
                NR == 2 {
                    gsub("%","",$5)
                    print $5
                    exit
                }
            '
        )


        usage="${usage:-0}"
        inode_usage="${inode_usage:-0}"


        printf "%-15s %-10s %-9s%% %-9s%%\n" \
            "$mount" \
            "$fstype" \
            "$usage" \
            "$inode_usage"


        #
        # Critical filesystem state
        #

        if awk \
            -v usage="$usage" \
            -v inode="$inode_usage" \
            -v usagecrit="$fs_usage_critical" \
            -v inodecrit="$fs_inode_critical" \
            'BEGIN {
                if (usage >= usagecrit) exit 0
                if (inode >= inodecrit) exit 0

                exit 1
            }'
        then

            filesystem_critical=1


        #
        # Warning filesystem state
        #

        elif awk \
            -v usage="$usage" \
            -v inode="$inode_usage" \
            -v usagewarn="$fs_usage_warn" \
            -v inodewarn="$fs_inode_warn" \
            'BEGIN {
                if (usage >= usagewarn) exit 0
                if (inode >= inodewarn) exit 0

                exit 1
            }'
        then

            filesystem_warning=1
        fi

    done


    echo


    if (( filesystem_critical == 1 )); then

        fail "Critical filesystem capacity or inode pressure detected"

    elif (( filesystem_warning == 1 )); then

        warn "Filesystem capacity or inode usage requires attention"

    else

        ok "Filesystem capacity and inode usage are healthy"

    fi


    #
    # ------------------------------------------------------------
    # I/O PSI
    # ------------------------------------------------------------
    #

    echo
    echo "I/O pressure:"


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


    printf "I/O PSI some avg10:  %s%%\n" "$psi_some"
    printf "I/O PSI full avg10:  %s%%\n" "$psi_full"


    #
    # ------------------------------------------------------------
    # BLOCK DEVICE PERFORMANCE
    # ------------------------------------------------------------
    #

    echo
    echo "Block device performance:"
    echo


    if ! command_exists iostat; then

        warn "iostat is unavailable; block-device performance could not be evaluated"

        return 3
    fi


    printf "%-10s %-8s %-8s %-10s %-10s %-10s %-8s\n" \
        "Device" \
        "r/s" \
        "w/s" \
        "r_await" \
        "w_await" \
        "aqu-sz" \
        "%util"


    printf "%-10s %-8s %-8s %-10s %-10s %-10s %-8s\n" \
        "----------" \
        "--------" \
        "--------" \
        "----------" \
        "----------" \
        "----------" \
        "--------"


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


    local device=""
    local reads="0"
    local writes="0"

    local rawait="0"
    local wawait="0"

    local queue="0"
    local util="0"

    local device_count=0


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


        device_count=$((device_count + 1))


        printf "%-10s %-8s %-8s %-10s %-10s %-10s %-8s\n" \
            "$device" \
            "$reads" \
            "$writes" \
            "$rawait" \
            "$wawait" \
            "$queue" \
            "$util"


        #
        # Critical
        #

        if awk \
            -v util="$util" \
            -v r="$rawait" \
            -v w="$wawait" \
            -v q="$queue" \
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

            disk_critical=1


        #
        # Warning
        #

        elif awk \
            -v util="$util" \
            -v r="$rawait" \
            -v w="$wawait" \
            -v q="$queue" \
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

            disk_warning=1
        fi

    done <<< "$io_data"


    if (( device_count == 0 )); then

        fail "No supported whole block device was found"

        return 3
    fi


    #
    # ------------------------------------------------------------
    # TOP I/O PROCESS
    # ------------------------------------------------------------
    #

    echo
    echo "Top I/O process:"


    local process=""

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

    fi


    if [[ -n "$process" ]]; then

        local pid=""
        local command=""

        local read_rate=""
        local write_rate=""

        local io_delay=""


        read -r \
            pid \
            command \
            read_rate \
            write_rate \
            io_delay \
            <<< "$process"


        printf "PID:                 %s\n" "$pid"
        printf "Command:             %s\n" "$command"

        printf "Read:                %s KB/s\n" "$read_rate"
        printf "Write:               %s KB/s\n" "$write_rate"

        printf "I/O delay:           %s\n" "$io_delay"

    else

        echo "No significant process I/O activity detected"

    fi


    #
    # ------------------------------------------------------------
    # FINAL CLASSIFICATION
    # ------------------------------------------------------------
    #

    echo


    if (( filesystem_critical == 1 ||
          disk_critical == 1 )); then

        fail "Critical disk or filesystem pressure detected"

        return 2
    fi


    if (( filesystem_warning == 1 ||
          disk_warning == 1 )); then

        warn "Disk or filesystem pressure detected"

        return 1
    fi


    ok "No significant disk I/O pressure detected"

    echo

    ok "Disk subsystem is healthy"


    return 0
}
