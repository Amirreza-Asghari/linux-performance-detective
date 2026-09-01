#!/usr/bin/env bash

set -o pipefail


TEST_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"


PROJECT_ROOT="$(
    cd -- "$TEST_DIR/.." &&
    pwd
)"


source "$TEST_DIR/testlib.sh"


TEST_TMP="$(
    mktemp -d /tmp/lpd-incident-tests.XXXXXX
)" || {
    echo "Unable to create temporary test directory"
    exit 1
}


CLI_ROOT="$TEST_TMP/project"

WORKLOAD_PIDS=()

DISK_TEST_FILE=""


#
# ------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------
#

register_workload_pid() {

    local pid="${1:-}"

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    WORKLOAD_PIDS+=("$pid")
}


stop_workload_pid() {

    local pid="${1:-}"

    [[ "$pid" =~ ^[0-9]+$ ]] || return 0


    if kill -0 "$pid" 2>/dev/null; then

        kill "$pid" 2>/dev/null || true

        sleep 1
    fi


    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi


    wait "$pid" 2>/dev/null || true
}


cleanup_workloads() {

    local pid=""


    for pid in "${WORKLOAD_PIDS[@]}"; do
        stop_workload_pid "$pid"
    done


    if [[ -n "$DISK_TEST_FILE" ]]; then
        rm -f -- "$DISK_TEST_FILE"
    fi
}


cleanup_all() {

    cleanup_workloads

    rm -rf -- "$TEST_TMP"
}


signal_exit() {

    local rc="${1:-130}"

    cleanup_all

    trap - EXIT

    exit "$rc"
}


trap cleanup_all EXIT
trap 'signal_exit 130' INT
trap 'signal_exit 143' TERM


#
# ------------------------------------------------------------
# ISOLATED PROJECT COPY
# ------------------------------------------------------------
#

mkdir -p "$CLI_ROOT"


cp -a "$PROJECT_ROOT/lpd.sh" "$CLI_ROOT/"
cp -a "$PROJECT_ROOT/lib" "$CLI_ROOT/"
cp -a "$PROJECT_ROOT/checks" "$CLI_ROOT/"
cp -a "$PROJECT_ROOT/diagnostics" "$CLI_ROOT/"
cp -a "$PROJECT_ROOT/fixes" "$CLI_ROOT/"
cp -a "$PROJECT_ROOT/verify" "$CLI_ROOT/"
cp -a "$PROJECT_ROOT/config" "$CLI_ROOT/"


mkdir -p \
    "$CLI_ROOT/logs" \
    "$CLI_ROOT/reports" \
    "$CLI_ROOT/evidence"


#
# ------------------------------------------------------------
# CONFIG HELPERS
# ------------------------------------------------------------
#

make_test_config() {

    local name="${1:-test}"

    local file="$TEST_TMP/${name}.conf"


    cp \
        "$PROJECT_ROOT/config/lpd.conf" \
        "$file" ||
        return 1


    printf "%s" "$file"
}


set_config_value() {

    local file="${1:-}"
    local key="${2:-}"
    local value="${3:-}"


    if ! grep -q "^${key}=" "$file"; then

        echo "Config key not found: $key"

        return 1
    fi


    sed -i \
        "s/^${key}=.*/${key}=${value}/" \
        "$file"
}


run_scan() {

    local config="${1:-}"
    local output="${2:-}"


    LPD_CONFIG_FILE="$config" \
        "$CLI_ROOT/lpd.sh" scan \
        > "$output" \
        2>&1


    return $?
}


#
# ============================================================
# TEST 01
# CPU SATURATION
# ============================================================
#

test_cpu_incident() {

    if ! command -v yes >/dev/null 2>&1; then
        echo "yes command unavailable"
        return 77
    fi


    local config=""

    config=$(
        make_test_config cpu
    ) || return 1


    #
    # A single yes process should clearly exceed this.
    #

    set_config_value \
        "$config" \
        CPU_PROCESS_SATURATION_PCT \
        40 ||
        return 1


    local output="$TEST_TMP/cpu.out"


    yes > /dev/null &

    local pid=$!

    register_workload_pid "$pid"


    sleep 2


    if ! kill -0 "$pid" 2>/dev/null; then

        echo "CPU workload exited unexpectedly"

        return 1
    fi


    run_scan \
        "$config" \
        "$output"

    local rc=$?


    stop_workload_pid "$pid"


    if (( rc == 0 )); then

        echo "CPU incident was reported HEALTHY"

        cat "$output"

        return 1
    fi


    if (( rc == 3 )); then

        echo "CPU incident produced UNKNOWN"

        cat "$output"

        return 1
    fi


    if ! grep -Eq \
        'Command:[[:space:]]+yes' \
        "$output"
    then

        echo "yes process was not identified"

        cat "$output"

        return 1
    fi


    echo "CPU detector exit: $rc"

    return 0
}


#
# ============================================================
# TEST 02
# MEMORY PRESSURE
# ============================================================
#

current_memory_available_pct() {

    awk '
        /^MemTotal:/ {
            total=$2
        }

        /^MemAvailable:/ {
            available=$2
        }

        END {
            if (total <= 0)
                exit 1

            printf "%.0f\n", (available * 100) / total
        }
    ' /proc/meminfo
}


test_memory_incident() {

    if ! command -v stress-ng >/dev/null 2>&1; then

        echo "stress-ng unavailable"

        return 77
    fi


    local baseline=""

    baseline=$(
        current_memory_available_pct
    ) || return 1


    echo "Baseline MemAvailable: ${baseline}%"


    #
    # Do not deliberately pressure an already-low-memory host.
    #

    if (( baseline < 45 )); then

        echo "Baseline memory is already too low for a safe incident test"

        return 77
    fi


    local warn=$((baseline - 5))
    local swap_critical=$((warn - 10))
    local critical=$((warn - 20))


    if (( critical < 5 )); then
        critical=5
    fi


    if (( swap_critical <= critical )); then
        swap_critical=$((critical + 5))
    fi


    local config=""

    config=$(
        make_test_config memory
    ) || return 1


    set_config_value \
        "$config" \
        MEM_AVAILABLE_WARN_PCT \
        "$warn" ||
        return 1


    set_config_value \
        "$config" \
        MEM_AVAILABLE_SWAP_CRITICAL_PCT \
        "$swap_critical" ||
        return 1


    set_config_value \
        "$config" \
        MEM_AVAILABLE_CRITICAL_PCT \
        "$critical" ||
        return 1


    local output="$TEST_TMP/memory.out"


    stress-ng \
        --vm 1 \
        --vm-bytes 25% \
        --vm-keep \
        --timeout 20s \
        --quiet \
        >/dev/null \
        2>&1 &


    local pid=$!

    register_workload_pid "$pid"


    sleep 3


    if ! kill -0 "$pid" 2>/dev/null; then

        echo "Memory workload exited unexpectedly"

        return 1
    fi


    run_scan \
        "$config" \
        "$output"

    local rc=$?


    stop_workload_pid "$pid"


    local observed=""

    observed=$(
        awk '
            /Memory available:/ {
                value=$3

                gsub("%","",value)

                print value

                exit
            }
        ' "$output"
    )


    if [[ ! "$observed" =~ ^[0-9]+$ ]]; then

        echo "Unable to read Memory available from scan"

        cat "$output"

        return 1
    fi


    echo "Observed MemAvailable: ${observed}%"
    echo "Warning threshold:     ${warn}%"


    if (( observed >= warn )); then

        echo "Memory workload did not cross the test threshold"

        cat "$output"

        return 1
    fi


    if (( rc == 0 )); then

        echo "Memory incident crossed threshold but scan returned HEALTHY"

        cat "$output"

        return 1
    fi


    if (( rc == 3 )); then

        echo "Memory incident returned UNKNOWN"

        cat "$output"

        return 1
    fi


    echo "Memory detector exit: $rc"

    return 0
}


#
# ============================================================
# TEST 03
# DISK I/O PRESSURE
# ============================================================
#

test_disk_incident() {

    if ! command -v fio >/dev/null 2>&1; then

        echo "fio unavailable"

        return 77
    fi


    if ! command -v iostat >/dev/null 2>&1; then

        echo "iostat unavailable"

        return 77
    fi


    local config=""

    config=$(
        make_test_config disk
    ) || return 1


    set_config_value \
        "$config" \
        DISK_UTIL_WARN_PCT \
        5 ||
        return 1


    set_config_value \
        "$config" \
        DISK_UTIL_CRITICAL_PCT \
        95 ||
        return 1


    local output="$TEST_TMP/disk.out"


    DISK_TEST_FILE="$PROJECT_ROOT/tests/.lpd-fio-test.$$"


    fio \
        --name=lpd-incident \
        --filename="$DISK_TEST_FILE" \
        --size=256M \
        --rw=randwrite \
        --bs=4k \
        --direct=1 \
        --ioengine=libaio \
        --iodepth=32 \
        --time_based=1 \
        --runtime=18 \
        --group_reporting=1 \
        >/dev/null \
        2>&1 &


    local pid=$!

    register_workload_pid "$pid"


    sleep 3


    if ! kill -0 "$pid" 2>/dev/null; then

        echo "fio exited before measurement"

        return 1
    fi


    run_scan \
        "$config" \
        "$output"

    local rc=$?


    stop_workload_pid "$pid"

    rm -f -- "$DISK_TEST_FILE"

    DISK_TEST_FILE=""


    if (( rc == 0 )); then

        echo "Disk incident was reported HEALTHY"

        cat "$output"

        return 1
    fi


    if (( rc == 3 )); then

        echo "Disk incident returned UNKNOWN"

        cat "$output"

        return 1
    fi


    if ! grep -Eq \
        'Command:[[:space:]]+fio' \
        "$output"
    then

        echo "fio was not attributed as active I/O workload"

        cat "$output"

        return 1
    fi


    echo "Disk detector exit: $rc"

    return 0
}


#
# ============================================================
# TEST 04
# NETWORK CONNECTION CHURN
# ============================================================
#

test_network_incident() {

    if ! command -v python3 >/dev/null 2>&1; then

        echo "python3 unavailable"

        return 77
    fi


    if ! command -v curl >/dev/null 2>&1; then

        echo "curl unavailable"

        return 77
    fi


    if ! command -v ss >/dev/null 2>&1; then

        echo "ss unavailable"

        return 77
    fi


    local config=""

    config=$(
        make_test_config network
    ) || return 1


    set_config_value \
        "$config" \
        NETWORK_TIME_WAIT_WARN \
        1 ||
        return 1


    set_config_value \
        "$config" \
        NETWORK_TIME_WAIT_CRITICAL \
        1000 ||
        return 1


    local port_file="$TEST_TMP/network-port"


    python3 - "$port_file" <<'PY' \
        >/dev/null \
        2>&1 &

import socket
import sys

port_file = sys.argv[1]

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

server.setsockopt(
    socket.SOL_SOCKET,
    socket.SO_REUSEADDR,
    1,
)

server.bind(("127.0.0.1", 0))

server.listen(128)

port = server.getsockname()[1]

with open(port_file, "w", encoding="utf-8") as f:
    f.write(str(port))

while True:
    connection, _ = server.accept()

    try:
        connection.recv(4096)

        connection.sendall(
            b"HTTP/1.1 200 OK\r\n"
            b"Content-Length: 2\r\n"
            b"Connection: close\r\n"
            b"\r\n"
            b"OK"
        )

    except OSError:
        pass

    finally:
        connection.close()
PY


    local server_pid=$!

    register_workload_pid "$server_pid"


    local attempt=0


    while [[ ! -s "$port_file" ]]; do

        attempt=$((attempt + 1))


        if (( attempt >= 50 )); then

            echo "Network test server did not start"

            return 1
        fi


        sleep 0.1
    done


    local port=""

    port=$(
        cat "$port_file"
    )


    [[ "$port" =~ ^[0-9]+$ ]] || {

        echo "Invalid test server port: $port"

        return 1
    }


    echo "Local test port: $port"


    local i=0


    for ((i=1; i<=80; i++)); do

        curl \
            -s \
            --max-time 1 \
            "http://127.0.0.1:$port/" \
            >/dev/null \
            2>&1 ||
            true

    done


    local before_time_wait=0

    before_time_wait=$(
        ss -Htan state time-wait \
            2>/dev/null |
        awk 'END {print NR + 0}'
    )


    echo "TIME-WAIT before scan: $before_time_wait"


    if (( before_time_wait < 1 )); then

        echo "Connection churn did not create TIME-WAIT sockets"

        return 1
    fi


    local output="$TEST_TMP/network.out"


    run_scan \
        "$config" \
        "$output"

    local rc=$?


    stop_workload_pid "$server_pid"


    local observed=""

    observed=$(
        awk '
            /TIME-WAIT:/ {
                print $2
                exit
            }
        ' "$output"
    )


    if [[ ! "$observed" =~ ^[0-9]+$ ]]; then

        echo "Unable to read TIME-WAIT telemetry"

        cat "$output"

        return 1
    fi


    echo "TIME-WAIT observed by LPD: $observed"


    if (( observed < 1 )); then

        echo "LPD did not observe generated connection churn"

        cat "$output"

        return 1
    fi


    if (( rc == 0 )); then

        echo "Network incident was reported HEALTHY"

        cat "$output"

        return 1
    fi


    if (( rc == 3 )); then

        echo "Network incident returned UNKNOWN"

        cat "$output"

        return 1
    fi


    echo "Network detector exit: $rc"

    return 0
}


#
# ============================================================
# TEST 05
# FILE DESCRIPTOR EXHAUSTION
# ============================================================
#

test_fd_incident() {

    if ! command -v python3 >/dev/null 2>&1; then

        echo "python3 unavailable"

        return 77
    fi


    local config=""

    config=$(
        make_test_config fd
    ) || return 1


    set_config_value \
        "$config" \
        FD_PROCESS_WARN_PCT \
        70 ||
        return 1


    set_config_value \
        "$config" \
        FD_PROCESS_CRITICAL_PCT \
        95 ||
        return 1


    local ready_file="$TEST_TMP/fd-ready"


    bash -c '
        ulimit -n 64

        exec python3 - "$1" <<'"'"'PY'"'"'
import sys
import time

ready = sys.argv[1]

fds = []

for _ in range(52):
    fds.append(open("/dev/null", "rb"))

with open(ready, "w", encoding="utf-8") as f:
    f.write(str(len(fds)))

time.sleep(30)
PY
    ' _ "$ready_file" \
        >/dev/null \
        2>&1 &


    local pid=$!

    register_workload_pid "$pid"


    local attempt=0


    while [[ ! -s "$ready_file" ]]; do

        attempt=$((attempt + 1))


        if (( attempt >= 50 )); then

            echo "FD workload failed to initialize"

            return 1
        fi


        if ! kill -0 "$pid" 2>/dev/null; then

            echo "FD workload exited unexpectedly"

            return 1
        fi


        sleep 0.1
    done


    local actual_fd_count=0

    actual_fd_count=$(
        find \
            "/proc/$pid/fd" \
            -mindepth 1 \
            -maxdepth 1 \
            2>/dev/null |
        wc -l
    )


    echo "FD workload PID:  $pid"
    echo "Open descriptors: $actual_fd_count"


    if (( actual_fd_count < 45 )); then

        echo "FD workload did not open enough descriptors"

        return 1
    fi


    local output="$TEST_TMP/fd.out"


    run_scan \
        "$config" \
        "$output"

    local rc=$?


    stop_workload_pid "$pid"


    local utilization=""

    utilization=$(
        awk '
            /Utilization:/ {
                value=$2

                gsub("%","",value)

                print value

                exit
            }
        ' "$output"
    )


    if [[ ! "$utilization" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

        echo "Unable to read FD utilization"

        cat "$output"

        return 1
    fi


    echo "LPD FD utilization: ${utilization}%"


    if ! awk \
        -v value="$utilization" \
        'BEGIN {
            if (value >= 70) exit 0
            exit 1
        }'
    then

        echo "LPD did not identify the high-utilization FD process"

        cat "$output"

        return 1
    fi


    if (( rc == 0 )); then

        echo "FD incident was reported HEALTHY"

        cat "$output"

        return 1
    fi


    if (( rc == 3 )); then

        echo "FD incident returned UNKNOWN"

        cat "$output"

        return 1
    fi


    echo "FD detector exit: $rc"

    return 0
}


#
# ------------------------------------------------------------
# RUN SUITE
# ------------------------------------------------------------
#

echo "============================================================"
echo "Linux Performance Detective"
echo "Automated Incident Test Suite"
echo "============================================================"

echo

echo "WARNING:"
echo "This test intentionally creates short-lived CPU, memory,"
echo "disk, network and file-descriptor pressure."
echo

printf "Project: %s\n" "$PROJECT_ROOT"
printf "Temp:    %s\n" "$TEST_TMP"


lpd_run_test \
    "CPU saturation detection" \
    test_cpu_incident


lpd_run_test \
    "Memory pressure detection" \
    test_memory_incident


lpd_run_test \
    "Disk I/O pressure detection" \
    test_disk_incident


lpd_run_test \
    "Network connection churn detection" \
    test_network_incident


lpd_run_test \
    "File descriptor pressure detection" \
    test_fd_incident


lpd_test_summary

exit $?
