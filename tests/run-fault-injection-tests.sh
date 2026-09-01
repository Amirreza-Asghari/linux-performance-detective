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


TEST_TMP="$(
    mktemp -d /tmp/lpd-fault-tests.XXXXXX
)" || {

    echo "Unable to create temporary test directory"

    exit 1
}


PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0


cleanup_fault_tests() {

    rm -rf -- "$TEST_TMP"
}


trap cleanup_fault_tests EXIT


#
# ------------------------------------------------------------
# ISOLATED CLI COPY
# ------------------------------------------------------------
#

CLI_ROOT="$TEST_TMP/cli-project"

mkdir -p "$CLI_ROOT"


cp -a \
    "$PROJECT_ROOT/lpd.sh" \
    "$CLI_ROOT/"

cp -a \
    "$PROJECT_ROOT/lib" \
    "$CLI_ROOT/"

cp -a \
    "$PROJECT_ROOT/checks" \
    "$CLI_ROOT/"

cp -a \
    "$PROJECT_ROOT/diagnostics" \
    "$CLI_ROOT/"

cp -a \
    "$PROJECT_ROOT/fixes" \
    "$CLI_ROOT/"

cp -a \
    "$PROJECT_ROOT/verify" \
    "$CLI_ROOT/"

cp -a \
    "$PROJECT_ROOT/config" \
    "$CLI_ROOT/"


mkdir -p \
    "$CLI_ROOT/logs" \
    "$CLI_ROOT/reports" \
    "$CLI_ROOT/evidence"


#
# ------------------------------------------------------------
# HARNESS
# ------------------------------------------------------------
#

run_test() {

    local name="${1:-Unnamed test}"
    local function_name="${2:-}"


    echo
    printf "[TEST] %s\n" "$name"


    "$function_name"

    local rc=$?


    case "$rc" in

        0)

            printf "[PASS] %s\n" "$name"

            PASS_COUNT=$((PASS_COUNT + 1))
            ;;


        77)

            printf "[SKIP] %s\n" "$name"

            SKIP_COUNT=$((SKIP_COUNT + 1))
            ;;


        *)

            printf "[FAIL] %s\n" "$name"

            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;

    esac
}


#
# ============================================================
# TEST 01
# Malicious config must be rejected without execution
# ============================================================
#

test_config_injection() {

    local config="$TEST_TMP/malicious.conf"
    local marker="$TEST_TMP/config-command-executed"

    local output="$TEST_TMP/config-injection.out"


    cp \
        "$PROJECT_ROOT/config/lpd.conf" \
        "$config"


    printf 'EVIL_COMMAND=$(touch %s)\n' \
        "$marker" \
        >> "$config"


    LPD_CONFIG_FILE="$config" \
        "$CLI_ROOT/lpd.sh" scan \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 3 )); then

        echo "Expected exit 3, got $rc"

        cat "$output"

        return 1
    fi


    if [[ -e "$marker" ]]; then

        echo "SECURITY FAILURE: injected command executed"

        return 1
    fi


    if ! grep -qi \
        'configuration is invalid' \
        "$output"
    then

        echo "Invalid configuration was not reported"

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 02
# Required runtime telemetry failure must produce UNKNOWN
# ============================================================
#

test_required_ps_failure() {

    local fake_bin="$TEST_TMP/fake-ps-bin"
    local output="$TEST_TMP/ps-failure.out"


    mkdir -p "$fake_bin"


    cat > "$fake_bin/ps" <<'EOF'
#!/bin/sh
exit 1
EOF


    chmod +x "$fake_bin/ps"


    PATH="$fake_bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "$CLI_ROOT/lpd.sh" scan \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 3 )); then

        echo "Expected UNKNOWN exit 3, got $rc"

        cat "$output"

        return 1
    fi


    if ! grep -qi \
        'health status is UNKNOWN' \
        "$output"
    then

        echo "System was not reported UNKNOWN"

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 03
# Missing required preflight dependency → UNSUPPORTED
# ============================================================
#

test_required_preflight_dependency() {

    (
        ROOT_DIR="$TEST_TMP/preflight-required-root"

        mkdir -p \
            "$ROOT_DIR/logs" \
            "$ROOT_DIR/reports" \
            "$ROOT_DIR/evidence"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/config.sh"
        source "$PROJECT_ROOT/lib/capabilities.sh"
        source "$PROJECT_ROOT/lib/preflight.sh"


        lpd_log_init \
            "fault-required-preflight"


        LPD_CONFIG_FILE="$PROJECT_ROOT/config/lpd.conf"


        if ! lpd_config_load "$LPD_CONFIG_FILE"; then

            echo "Unable to load configuration"

            exit 1
        fi


        #
        # Preflight has its own command-availability boundary.
        # Inject the failure at that exact boundary instead of
        # overriding the lower-level common.sh helper.
        #

        if ! declare -F preflight_command_available \
            >/dev/null \
            2>&1
        then

            echo "preflight_command_available is unavailable"

            exit 1
        fi


        preflight_command_available() {

            local command_name="${1:-}"


            if [[ "$command_name" == "awk" ]]; then

                return 1
            fi


            command -v "$command_name" \
                >/dev/null \
                2>&1
        }


        preflight_run \
            > "$TEST_TMP/preflight-required.out" \
            2>&1

        local rc=$?


        if (( rc != 3 )); then

            echo "Expected UNSUPPORTED exit 3, got $rc"

            cat "$TEST_TMP/preflight-required.out"

            exit 1
        fi


        if ! grep -q \
            'UNSUPPORTED' \
            "$TEST_TMP/preflight-required.out"
        then

            echo "Required dependency loss was not classified UNSUPPORTED"

            cat "$TEST_TMP/preflight-required.out"

            exit 1
        fi


        if grep -q \
            '\[OK\] READY' \
            "$TEST_TMP/preflight-required.out"
        then

            echo "False READY state after required dependency failure"

            cat "$TEST_TMP/preflight-required.out"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 04
# Missing optional preflight tool → DEGRADED
# ============================================================
#

test_optional_preflight_dependency() {

    (
        ROOT_DIR="$TEST_TMP/preflight-optional-root"

        mkdir -p \
            "$ROOT_DIR/logs" \
            "$ROOT_DIR/reports" \
            "$ROOT_DIR/evidence"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/config.sh"
        source "$PROJECT_ROOT/lib/capabilities.sh"
        source "$PROJECT_ROOT/lib/preflight.sh"


        lpd_log_init \
            "fault-optional-preflight"


        LPD_CONFIG_FILE="$PROJECT_ROOT/config/lpd.conf"


        if ! lpd_config_load "$LPD_CONFIG_FILE"; then

            echo "Unable to load configuration"

            exit 1
        fi


        if ! declare -F preflight_command_available \
            >/dev/null \
            2>&1
        then

            echo "preflight_command_available is unavailable"

            exit 1
        fi


        #
        # iostat is optional. Simulate only iostat being absent.
        #

        preflight_command_available() {

            local command_name="${1:-}"


            if [[ "$command_name" == "iostat" ]]; then

                return 1
            fi


            command -v "$command_name" \
                >/dev/null \
                2>&1
        }


        preflight_run \
            > "$TEST_TMP/preflight-optional.out" \
            2>&1

        local rc=$?


        if (( rc != 1 )); then

            echo "Expected DEGRADED exit 1, got $rc"

            cat "$TEST_TMP/preflight-optional.out"

            exit 1
        fi


        if ! grep -q \
            'DEGRADED' \
            "$TEST_TMP/preflight-optional.out"
        then

            echo "Optional dependency loss was not classified DEGRADED"

            cat "$TEST_TMP/preflight-optional.out"

            exit 1
        fi


        if grep -q \
            '\[OK\] READY' \
            "$TEST_TMP/preflight-optional.out"
        then

            echo "False READY state after optional dependency failure"

            cat "$TEST_TMP/preflight-optional.out"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 05
# Missing optional vmstat must not fabricate UNKNOWN
# ============================================================
#

test_optional_vmstat_failure() {

    (
        ROOT_DIR="$TEST_TMP/vmstat-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"
        source "$PROJECT_ROOT/lib/capabilities.sh"
        source "$PROJECT_ROOT/checks/memory.sh"


        command_exists() {

            if [[ "${1:-}" == "vmstat" ]]; then

                return 1
            fi


            command -v "${1:-}" \
                >/dev/null \
                2>&1
        }


        memory_check \
            > "$TEST_TMP/vmstat.out" \
            2>&1

        local rc=$?


        if (( rc == 3 )); then

            echo "Optional vmstat loss caused UNKNOWN"

            cat "$TEST_TMP/vmstat.out"

            exit 1
        fi


        if ! grep -q \
            'Swap-in:.*N/A' \
            "$TEST_TMP/vmstat.out"
        then

            echo "Missing telemetry was not represented as N/A"

            cat "$TEST_TMP/vmstat.out"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 06
# Reporting failure must invalidate otherwise healthy run
# ============================================================
#

test_report_failure_escalation() {

    (
        ROOT_DIR="$TEST_TMP/report-failure-root"

        mkdir -p \
            "$ROOT_DIR/logs" \
            "$ROOT_DIR/reports" \
            "$ROOT_DIR/evidence"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/interactive.sh"


        lpd_log_init \
            "fault-report-failure"


        cpu_check() {
            return 0
        }


        cpu_diagnose() {
            return 0
        }


        cpu_remediate() {
            return 0
        }


        cpu_verify() {
            return 0
        }


        lpd_report_generate() {
            return 1
        }


        interactive_run cpu \
            > "$TEST_TMP/report-failure.out" \
            2>&1

        local rc=$?


        if (( rc != 3 )); then

            echo "Reporting failure did not escalate to UNKNOWN"

            echo "Expected: 3"
            echo "Actual:   $rc"

            cat "$TEST_TMP/report-failure.out"

            exit 1
        fi


        if [[ "${LPD_OVERALL_EXIT_CODE:-}" != "3" ]]; then

            echo "Overall exit code was not changed to 3"

            exit 1
        fi


        if [[ "${LPD_OVERALL_STATUS:-}" != "UNKNOWN" ]]; then

            echo "Overall status was not changed to UNKNOWN"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 07
# Missing interactive module function must fail closed
# ============================================================
#

test_missing_interactive_function() {

    (
        ROOT_DIR="$TEST_TMP/missing-function-root"

        mkdir -p "$ROOT_DIR/logs"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/interactive.sh"


        lpd_log_init \
            "fault-missing-function"


        cpu_check() {
            return 0
        }


        cpu_diagnose() {
            return 0
        }


        #
        # cpu_remediate intentionally not defined.
        #

        cpu_verify() {
            return 0
        }


        interactive_run_one cpu \
            > "$TEST_TMP/missing-function.out" \
            2>&1

        local rc=$?


        if (( rc != 3 )); then

            echo "Missing remediation function did not fail closed"

            echo "Expected: 3"
            echo "Actual:   $rc"

            cat "$TEST_TMP/missing-function.out"

            exit 1
        fi


        if ! grep -q \
            'INTERACTIVE_FUNCTION_MISSING' \
            "$LPD_AUDIT_LOG"
        then

            echo "Missing function was not audited"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 08
# Invalid module result must normalize to UNKNOWN
# ============================================================
#

test_invalid_check_return() {

    (
        ROOT_DIR="$TEST_TMP/invalid-check-root"

        mkdir -p "$ROOT_DIR/logs"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/interactive.sh"


        lpd_log_init \
            "fault-invalid-check"


        cpu_check() {
            return 99
        }


        cpu_diagnose() {
            return 0
        }


        cpu_remediate() {
            return 0
        }


        cpu_verify() {
            return 0
        }


        interactive_run_one cpu \
            > "$TEST_TMP/invalid-check.out" \
            2>&1

        local rc=$?


        if (( rc != 3 )); then

            echo "Invalid check return was not normalized to UNKNOWN"

            echo "Expected: 3"
            echo "Actual:   $rc"

            cat "$TEST_TMP/invalid-check.out"

            exit 1
        fi


        if ! grep -q \
            'INTERACTIVE_INVALID_RC' \
            "$LPD_AUDIT_LOG"
        then

            echo "Invalid return code was not audited"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 09
# Stale process identity must never be accepted for signaling
# ============================================================
#

test_stale_pid_signal_rejection() {

    (
        ROOT_DIR="$TEST_TMP/stale-pid-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"


        sleep 30 &

        # shellcheck disable=SC2031
        local pid=$!


        local start=""


        start=$(
            lpd_capture_pid_identity \
                "$pid" \
                "sleep"
        ) || {

            kill "$pid" \
                2>/dev/null \
                || true

            wait "$pid" \
                2>/dev/null \
                || true


            echo "Unable to capture PID identity"

            exit 1
        }


        kill "$pid"

        wait "$pid" \
            2>/dev/null \
            || true


        if lpd_signal_target_safe \
            "$pid" \
            "$start" \
            "sleep"
        then

            echo "SECURITY FAILURE: stale PID was accepted"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ------------------------------------------------------------
# RUN
# ------------------------------------------------------------
#

echo "============================================================"
echo "Linux Performance Detective"
echo "Final Fault Injection Suite"
echo "============================================================"

echo

printf "Project: %s\n" "$PROJECT_ROOT"
printf "Temp:    %s\n" "$TEST_TMP"


run_test \
    "Config command-injection rejection" \
    test_config_injection


run_test \
    "Required ps telemetry failure" \
    test_required_ps_failure


run_test \
    "Required preflight dependency failure" \
    test_required_preflight_dependency


run_test \
    "Optional preflight dependency degradation" \
    test_optional_preflight_dependency


run_test \
    "Optional vmstat telemetry loss" \
    test_optional_vmstat_failure


run_test \
    "Report failure escalation" \
    test_report_failure_escalation


run_test \
    "Missing interactive function fail-closed" \
    test_missing_interactive_function


run_test \
    "Invalid module return normalization" \
    test_invalid_check_return


run_test \
    "Stale PID signal rejection" \
    test_stale_pid_signal_rejection


#
# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------
#

echo
echo "============================================================"
echo "LPD FAULT INJECTION SUMMARY"
echo "============================================================"

printf "Passed:  %d\n" "$PASS_COUNT"
printf "Failed:  %d\n" "$FAIL_COUNT"
printf "Skipped: %d\n" "$SKIP_COUNT"


if (( FAIL_COUNT > 0 )); then

    echo
    echo "RESULT: FAIL"

    exit 1
fi


echo
echo "RESULT: PASS"

exit 0
