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
    mktemp -d /tmp/lpd-safe-tests.XXXXXX
)" || {

    echo "Unable to create test directory"

    exit 1
}


cleanup_tests() {

    rm -rf -- "$TEST_TMP"
}


trap cleanup_tests EXIT


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
# ============================================================
# TEST 01
# Bash syntax
# ============================================================
#

test_bash_syntax() {

    local file=""


    while IFS= read -r -d '' file; do

        if ! bash -n "$file"; then

            echo "Syntax failure: $file"

            return 1
        fi

    done < <(
        find "$PROJECT_ROOT" \
            -type f \
            -name '*.sh' \
            -print0
    )


    return 0
}


#
# ============================================================
# TEST 02
# Config command injection must never execute
# ============================================================
#

test_config_injection() {

    local config="$TEST_TMP/injection.conf"

    local marker="$TEST_TMP/config-hacked"

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


    if ! grep -q \
        'configuration is invalid' \
        "$output"
    then

        echo "Expected invalid configuration message"

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 03
# Invalid threshold relationship
# ============================================================
#

test_config_relationship() {

    local config="$TEST_TMP/relationship.conf"

    local output="$TEST_TMP/config-relationship.out"


    cp \
        "$PROJECT_ROOT/config/lpd.conf" \
        "$config"


    sed -i \
        's/^FD_PROCESS_WARN_PCT=.*/FD_PROCESS_WARN_PCT=99/' \
        "$config"


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


    return 0
}


#
# ============================================================
# TEST 04
# Protected process policy
# ============================================================
#

test_protected_process() {

    (
        ROOT_DIR="$TEST_TMP/protected-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"


        if ! lpd_process_is_protected systemd; then

            echo "systemd was not classified as protected"

            exit 1
        fi


        if lpd_signal_target_safe 1 1 systemd; then

            echo "PID 1 was incorrectly accepted as safe"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 05
# Stale PID rejection
# ============================================================
#

test_stale_pid() {

    (
        ROOT_DIR="$TEST_TMP/stale-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"


        sleep 20 &

        local pid=$!


        local start=""


        start=$(
            lpd_capture_pid_identity \
                "$pid" \
                "sleep"
        ) || {

            kill "$pid" 2>/dev/null || true

            wait "$pid" 2>/dev/null || true

            echo "Unable to capture test PID identity"

            exit 1
        }


        if ! lpd_pid_identity_valid \
            "$pid" \
            "$start" \
            "sleep"
        then

            kill "$pid" 2>/dev/null || true

            wait "$pid" 2>/dev/null || true

            echo "Live PID failed identity validation"

            exit 1
        fi


        kill "$pid"

        wait "$pid" 2>/dev/null || true


        if lpd_pid_identity_valid \
            "$pid" \
            "$start" \
            "sleep"
        then

            echo "Dead PID was incorrectly accepted"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 06
# Invalid diagnosis return code
# ============================================================
#

test_invalid_diagnosis_rc() {

    (
        ROOT_DIR="$TEST_TMP/diag-rc-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/diagnose.sh"


        lpd_log_init \
            "safe-test-invalid-diagnosis"


        broken_diagnosis() {

            return 42
        }


        lpd_diagnose_run_one \
            "cpu" \
            "broken_diagnosis" \
            >/dev/null \
            2>&1


        local rc=$?


        if (( rc != 3 )); then

            echo "Expected normalized return 3, got $rc"

            exit 1
        fi


        if ! grep -q \
            'DIAGNOSIS_INVALID_RC' \
            "$LPD_AUDIT_LOG"
        then

            echo "Invalid diagnosis return was not audited"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 07
# Invalid remediation return code
# ============================================================
#

test_invalid_remediation_rc() {

    (
        ROOT_DIR="$TEST_TMP/remediation-rc-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/interactive.sh"


        lpd_log_init \
            "safe-test-invalid-remediation"


        local verify_marker="$ROOT_DIR/verify-ran"


        cpu_check() {
            return 1
        }


        cpu_diagnose() {
            return 1
        }


        cpu_remediate() {
            return 42
        }


        cpu_verify() {

            touch "$verify_marker"

            return 0
        }


        interactive_run_one cpu \
            >/dev/null \
            2>&1


        local rc=$?


        if (( rc != 3 )); then

            echo "Expected UNKNOWN=3, got $rc"

            exit 1
        fi


        if [[ -e "$verify_marker" ]]; then

            echo "Verifier ran after invalid remediation result"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 08
# Invalid verification return code
# ============================================================
#

test_invalid_verification_rc() {

    (
        ROOT_DIR="$TEST_TMP/verify-rc-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/interactive.sh"


        lpd_log_init \
            "safe-test-invalid-verification"


        cpu_check() {
            return 1
        }


        cpu_diagnose() {
            return 1
        }


        cpu_remediate() {
            return 0
        }


        cpu_verify() {
            return 42
        }


        interactive_run_one cpu \
            >/dev/null \
            2>&1


        local rc=$?


        if (( rc != 3 )); then

            echo "Expected UNKNOWN=3, got $rc"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 09
# Remediation code 10 = ATTENTION and no verifier
# ============================================================
#

test_no_action_rc() {

    (
        ROOT_DIR="$TEST_TMP/no-action-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/interactive.sh"


        lpd_log_init \
            "safe-test-no-action"


        local verify_marker="$ROOT_DIR/verify-ran"


        cpu_check() {
            return 1
        }


        cpu_diagnose() {

            LPD_CPU_PID="12345"
            LPD_CPU_COMMAND="mock-process"
            LPD_CPU_USAGE="99"

            return 1
        }


        cpu_remediate() {

            LPD_CPU_ACTION="SKIP"

            return 10
        }


        cpu_verify() {

            touch "$verify_marker"

            return 0
        }


        interactive_run_one cpu \
            >/dev/null \
            2>&1


        local rc=$?


        if (( rc != 1 )); then

            echo "Expected ATTENTION=1, got $rc"

            exit 1
        fi


        if [[ -e "$verify_marker" ]]; then

            echo "Verifier ran after no-action result"

            exit 1
        fi


        if ! grep -q \
            '|SKIP|' \
            "$LPD_REMEDIATION_LOG"
        then

            echo "SKIP decision was not written to remediation ledger"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 10
# ionice rollback
# ============================================================
#

test_ionice_rollback() {

    if ! command -v ionice >/dev/null 2>&1; then

        echo "ionice is unavailable"

        return 77
    fi


    (
        ROOT_DIR="$TEST_TMP/ionice-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/fixes/disk.sh"


        lpd_log_init \
            "safe-test-ionice-rollback"


        sleep 20 &

        local pid=$!


        local start=""


        start=$(
            lpd_capture_pid_identity \
                "$pid" \
                "sleep"
        ) || {

            kill "$pid" 2>/dev/null || true

            wait "$pid" 2>/dev/null || true

            exit 1
        }


        if ! disk_capture_ionice_state "$pid"; then

            kill "$pid" 2>/dev/null || true

            wait "$pid" 2>/dev/null || true

            echo "Unable to capture original ionice state"

            exit 1
        fi


        local original_raw="$LPD_IONICE_CAPTURE_RAW"


        LPD_DISK_PID="$pid"
        LPD_DISK_COMMAND="sleep"
        LPD_DISK_PID_START="$start"

        LPD_DISK_IONICE_BEFORE_CLASS="$LPD_IONICE_CAPTURE_CLASS"
        LPD_DISK_IONICE_BEFORE_DATA="$LPD_IONICE_CAPTURE_DATA"
        LPD_DISK_IONICE_BEFORE_RAW="$LPD_IONICE_CAPTURE_RAW"


        if ! ionice \
            -c 2 \
            -n 7 \
            -p "$pid" \
            >/dev/null \
            2>&1
        then

            kill "$pid" 2>/dev/null || true

            wait "$pid" 2>/dev/null || true

            echo "Unable to apply temporary ionice state"

            exit 1
        fi


        disk_restore_ionice \
            >/dev/null \
            2>&1


        local rollback_rc=$?


        if (( rollback_rc != 0 )); then

            kill "$pid" 2>/dev/null || true

            wait "$pid" 2>/dev/null || true

            echo "Rollback returned $rollback_rc"

            exit 1
        fi


        if ! disk_capture_ionice_state "$pid"; then

            kill "$pid" 2>/dev/null || true

            wait "$pid" 2>/dev/null || true

            echo "Unable to read restored ionice state"

            exit 1
        fi


        local restored_raw="$LPD_IONICE_CAPTURE_RAW"


        kill "$pid"

        wait "$pid" 2>/dev/null || true


        if [[ "$restored_raw" != "$original_raw" ]]; then

            echo "Original: $original_raw"

            echo "Restored: $restored_raw"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 11
# Required ps failure → overall UNKNOWN
# ============================================================
#

test_required_ps_failure() {

    local fake_bin="$TEST_TMP/fake-ps-bin"

    local output="$TEST_TMP/required-ps.out"


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

        echo "Expected UNKNOWN=3, got $rc"

        cat "$output"

        return 1
    fi


    if ! grep -q \
        'health status is UNKNOWN' \
        "$output"
    then

        echo "Overall UNKNOWN message not found"

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 12
# Optional vmstat failure must not force UNKNOWN
# ============================================================
#

test_optional_vmstat_fallback() {

    local fake_bin="$TEST_TMP/fake-vmstat-bin"

    local output="$TEST_TMP/vmstat-fallback.out"


    mkdir -p "$fake_bin"


    cat > "$fake_bin/vmstat" <<'EOF'
#!/bin/sh
exit 1
EOF


    chmod +x "$fake_bin/vmstat"


    (
        PATH="$fake_bin:/usr/sbin:/usr/bin:/sbin:/bin"


        ROOT_DIR="$TEST_TMP/vmstat-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/capabilities.sh"
        source "$PROJECT_ROOT/checks/memory.sh"


        lpd_log_init \
            "safe-test-vmstat-fallback"


        memory_check \
            > "$output" \
            2>&1


        local rc=$?


        if (( rc == 3 )); then

            echo "Optional vmstat failure caused UNKNOWN"

            cat "$output"

            exit 1
        fi


        if ! grep -q \
            'Swap-in:.*N/A' \
            "$output"
        then

            echo "N/A swap fallback not shown"

            cat "$output"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 13
# Evidence CPU arithmetic regression
# ============================================================
#

test_evidence_cpu_arithmetic() {

    (
        ROOT_DIR="$TEST_TMP/evidence-root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"
        source "$PROJECT_ROOT/lib/evidence.sh"


        local sample=""


        sample=$(
            lpd_evidence_cpu_stat_sample \
                2>/dev/null
        ) || {

            echo "Unable to read CPU evidence sample"

            exit 1
        }


        if [[ ! "$sample" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then

            echo "Unexpected CPU evidence sample: $sample"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 14
# Markdown + JSON report schema and coverage semantics
# ============================================================
#

test_report_structure() {

    if ! command -v python3 >/dev/null 2>&1; then

        echo "python3 unavailable for JSON validation"

        return 77
    fi


    (
        local report_root="$TEST_TMP/report-root"


        ROOT_DIR="$report_root"

        mkdir -p "$ROOT_DIR"


        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/safety.sh"
        source "$PROJECT_ROOT/lib/logger.sh"
        source "$PROJECT_ROOT/lib/capabilities.sh"
        source "$PROJECT_ROOT/lib/config.sh"
        source "$PROJECT_ROOT/lib/evidence.sh"
        source "$PROJECT_ROOT/lib/report.sh"


        lpd_log_init \
            "safe-test-report"


        #
        # Simulate:
        #
        #   ./lpd.sh interactive cpu
        #

        LPD_RUN_COMMAND="interactive cpu"


        LPD_CONFIG_FILE="$PROJECT_ROOT/config/lpd.conf"


        if ! lpd_config_load "$LPD_CONFIG_FILE"; then

            echo "Unable to load production config"

            exit 1
        fi


        LPD_RESULT_CPU=0

        LPD_RESULT_MEMORY=""
        LPD_RESULT_DISK=""

        LPD_RESULT_NETWORK=""
        LPD_RESULT_FD=""


        LPD_OVERALL_EXIT_CODE=0
        LPD_OVERALL_STATUS="HEALTHY"


        if ! lpd_report_generate \
            >/dev/null \
            2>&1
        then

            echo "Report generator returned failure"

            exit 1
        fi


        [[ -f "$LPD_REPORT_MD" ]] || {

            echo "Markdown report missing"

            exit 1
        }


        [[ -f "$LPD_REPORT_JSON" ]] || {

            echo "JSON report missing"

            exit 1
        }


        if ! python3 -m json.tool \
            "$LPD_REPORT_JSON" \
            >/dev/null
        then

            echo "Generated JSON is invalid"

            exit 1
        fi


        if ! grep -q \
            'LPD Version' \
            "$LPD_REPORT_MD"
        then

            echo "Version missing from Markdown report"

            exit 1
        fi


        if ! grep -q \
            'Final Exit Code.*0' \
            "$LPD_REPORT_MD"
        then

            echo "Final exit code missing from Markdown"

            exit 1
        fi


        if ! grep -Fq \
            '| CPU | YES | HEALTHY | 0 |' \
            "$LPD_REPORT_MD"
        then

            echo "CPU result wiring is incorrect"

            cat "$LPD_REPORT_MD"

            exit 1
        fi


        if ! grep -Fq \
            'Coverage scope: **cpu**. Full-system coverage: **NO**.' \
            "$LPD_REPORT_MD"
        then

            echo "Markdown coverage semantics are incorrect"

            cat "$LPD_REPORT_MD"

            exit 1
        fi


        if grep -q \
            'Top stable process: ps ' \
            "$LPD_REPORT_MD"
        then

            echo "Temporary ps process leaked into CPU evidence"

            exit 1
        fi


        #
        # Pass the expected version from common.sh to Python.
        #
        # Version is not hard-coded here, so future version bumps
        # do not require rewriting this test.
        #

        python3 \
            - \
            "$LPD_REPORT_JSON" \
            "$LPD_VERSION" \
            <<'PY'
import json
import sys


path = sys.argv[1]
expected_version = sys.argv[2]


with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)


#
# Schema
#

assert data["schema_version"] == 1


#
# Run metadata
#

assert data["run"]["version"] == expected_version

assert data["run"]["command"] == "interactive cpu"
assert data["run"]["mode"] == "interactive"
assert data["run"]["target"] == "cpu"

assert data["run"]["exit_code"] == 0


#
# Overall result
#

assert data["overall_status"] == "HEALTHY"


#
# Explicit coverage
#

assert data["coverage"]["scope"] == "cpu"
assert data["coverage"]["full_system"] is False


#
# CPU executed
#

cpu = data["subsystems"]["cpu"]

assert cpu["executed"] is True
assert cpu["status"] == "HEALTHY"
assert cpu["exit_code"] == 0


#
# Other subsystem workflows were not executed.
#

for name in (
    "memory",
    "disk",
    "network",
    "file_descriptors",
):
    subsystem = data["subsystems"][name]

    assert subsystem["executed"] is False
    assert subsystem["status"] == "NOT_RUN"
    assert subsystem["exit_code"] is None


#
# Config values must remain native JSON numbers.
#

assert (
    data["configuration"]["effective_thresholds"]
        ["CPU_BUSY_WARN_PCT"]
    == 85
)


#
# Missing machine-readable values must use JSON null,
# never the human-readable string "N/A".
#

def reject_na(value, path="root"):

    if isinstance(value, dict):

        for key, child in value.items():

            reject_na(
                child,
                f"{path}.{key}",
            )

        return


    if isinstance(value, list):

        for index, child in enumerate(value):

            reject_na(
                child,
                f"{path}[{index}]",
            )

        return


    assert value != "N/A", (
        f'JSON contains human-readable "N/A" at {path}'
    )


reject_na(data)
PY

        local python_rc=$?


        if (( python_rc != 0 )); then

            echo "JSON semantic validation failed"

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
echo "Safe Regression Test Suite"
echo "============================================================"

echo

printf "Project: %s\n" "$PROJECT_ROOT"
printf "Temp:    %s\n" "$TEST_TMP"


lpd_run_test \
    "Bash syntax" \
    test_bash_syntax


lpd_run_test \
    "Config command-injection protection" \
    test_config_injection


lpd_run_test \
    "Config relationship validation" \
    test_config_relationship


lpd_run_test \
    "Protected process policy" \
    test_protected_process


lpd_run_test \
    "Stale PID rejection" \
    test_stale_pid


lpd_run_test \
    "Invalid diagnosis return normalization" \
    test_invalid_diagnosis_rc


lpd_run_test \
    "Invalid remediation return normalization" \
    test_invalid_remediation_rc


lpd_run_test \
    "Invalid verification return normalization" \
    test_invalid_verification_rc


lpd_run_test \
    "No-action remediation semantics" \
    test_no_action_rc


lpd_run_test \
    "ionice rollback restoration" \
    test_ionice_rollback


lpd_run_test \
    "Required ps failure produces UNKNOWN" \
    test_required_ps_failure


lpd_run_test \
    "Optional vmstat fallback" \
    test_optional_vmstat_fallback


lpd_run_test \
    "CPU evidence arithmetic regression" \
    test_evidence_cpu_arithmetic


lpd_run_test \
    "Markdown and JSON report schema" \
    test_report_structure


lpd_test_summary

exit $?
