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
    mktemp -d /tmp/lpd-final-regression.XXXXXX
)" || {

    echo "Unable to create temporary test directory"

    exit 1
}


PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0


cleanup_final_tests() {

    rm -rf -- "$TEST_TMP"
}


trap cleanup_final_tests EXIT


#
# ------------------------------------------------------------
# TEST HARNESS
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


allowed_rc() {

    local actual="${1:-}"
    shift || true

    local expected=""


    for expected in "$@"; do

        if [[ "$actual" == "$expected" ]]; then
            return 0
        fi

    done


    return 1
}


contains_ansi() {

    local file="${1:-}"

    grep -q $'\033' "$file"
}


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
        find \
            "$PROJECT_ROOT/lpd.sh" \
            "$PROJECT_ROOT/lib" \
            "$PROJECT_ROOT/checks" \
            "$PROJECT_ROOT/diagnostics" \
            "$PROJECT_ROOT/fixes" \
            "$PROJECT_ROOT/verify" \
            "$PROJECT_ROOT/tests" \
            -type f \
            -name '*.sh' \
            -print0
    )


    return 0
}


#
# ============================================================
# TEST 02
# Production ShellCheck
# ============================================================
#

test_shellcheck() {

    if ! command -v shellcheck >/dev/null 2>&1; then

        echo "shellcheck unavailable"

        return 77
    fi


    find \
        "$PROJECT_ROOT/lpd.sh" \
        "$PROJECT_ROOT/lib" \
        "$PROJECT_ROOT/checks" \
        "$PROJECT_ROOT/diagnostics" \
        "$PROJECT_ROOT/fixes" \
        "$PROJECT_ROOT/verify" \
        -type f \
        -name '*.sh' \
        -print0 |
    xargs -0 shellcheck \
        -x \
        -e SC1090,SC1091,SC2034,SC2317,SC2016


    return $?
}


#
# ============================================================
# TEST 03
# Version contract
# ============================================================
#

test_version_contract() {

    local expected=""
    local actual=""

    local rc=0


    expected=$(
        bash -c '
            source "'"$PROJECT_ROOT"'/lib/common.sh"
            printf "%s" "$LPD_VERSION"
        '
    ) || return 1


    actual=$(
        "$PROJECT_ROOT/lpd.sh" version \
            2>&1
    )

    rc=$?


    if (( rc != 0 )); then

        echo "Version command returned $rc"

        return 1
    fi


    if [[ "$actual" != "$expected" ]]; then

        echo "Expected version: $expected"
        echo "Actual version:   $actual"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 04
# Help + frozen CLI contract
# ============================================================
#

test_help_contract() {

    local output="$TEST_TMP/help.out"


    "$PROJECT_ROOT/lpd.sh" help \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 0 )); then

        echo "Help returned $rc"

        cat "$output"

        return 1
    fi


    local required=""

    for required in \
        "preflight" \
        "scan" \
        "diagnose [cpu|memory|disk|network|fd|all]" \
        "interactive [cpu|memory|disk|network|fd|all]" \
        "version" \
        "help"
    do

        if ! grep -Fq \
            "$required" \
            "$output"
        then

            echo "Missing CLI contract entry: $required"

            cat "$output"

            return 1
        fi

    done


    return 0
}


#
# ============================================================
# TEST 05
# Unknown command contract
# ============================================================
#

test_unknown_command() {

    local output="$TEST_TMP/unknown-command.out"


    "$PROJECT_ROOT/lpd.sh" \
        "__lpd_invalid_command__" \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 2 )); then

        echo "Expected exit 2, got $rc"

        cat "$output"

        return 1
    fi


    if ! grep -q \
        'Unknown command' \
        "$output"
    then

        echo "Unknown-command error message missing"

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 06
# Preflight contract
# ============================================================
#

test_preflight_contract() {

    local output="$TEST_TMP/preflight.out"


    "$PROJECT_ROOT/lpd.sh" preflight \
        > "$output" \
        2>&1

    local rc=$?


    if ! allowed_rc "$rc" 0 1 3; then

        echo "Unexpected preflight exit code: $rc"

        cat "$output"

        return 1
    fi


    if contains_ansi "$output"; then

        echo "ANSI leaked into redirected preflight"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 07
# Scan contract
# ============================================================
#

test_scan_contract() {

    local output="$TEST_TMP/scan.out"


    "$PROJECT_ROOT/lpd.sh" scan \
        > "$output" \
        2>&1

    local rc=$?


    if ! allowed_rc "$rc" 0 1 2 3; then

        echo "Unexpected scan exit code: $rc"

        cat "$output"

        return 1
    fi


    if contains_ansi "$output"; then

        echo "ANSI leaked into redirected scan"

        return 1
    fi


    if grep -Eq \
        'Workflow|Progress|╭|╮|╰|╯|█|░' \
        "$output"
    then

        echo "TTY decoration leaked into redirected scan"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 08
# Diagnose single-target contracts
# ============================================================
#

test_diagnose_targets() {

    local target=""
    local output=""

    local rc=0


    for target in \
        cpu \
        memory \
        disk \
        network \
        fd
    do

        output="$TEST_TMP/diagnose-$target.out"


        "$PROJECT_ROOT/lpd.sh" \
            diagnose \
            "$target" \
            > "$output" \
            2>&1

        rc=$?


        if ! allowed_rc "$rc" 0 1 2 3; then

            echo "Unexpected diagnose $target exit code: $rc"

            cat "$output"

            return 1
        fi


        if contains_ansi "$output"; then

            echo "ANSI leaked into diagnose $target"

            return 1
        fi


        if grep -Ein \
            'Apply this remediation|Select action|\[y/N\]' \
            "$output" \
            >/dev/null
        then

            echo "Interactive prompt leaked into diagnose $target"

            cat "$output"

            return 1
        fi

    done


    return 0
}


#
# ============================================================
# TEST 09
# Diagnose all contract
# ============================================================
#

test_diagnose_all() {

    local output="$TEST_TMP/diagnose-all.out"


    "$PROJECT_ROOT/lpd.sh" \
        diagnose \
        all \
        > "$output" \
        2>&1

    local rc=$?


    if ! allowed_rc "$rc" 0 1 2 3; then

        echo "Unexpected diagnose all exit code: $rc"

        cat "$output"

        return 1
    fi


    if contains_ansi "$output"; then

        echo "ANSI leaked into diagnose all"

        return 1
    fi


    if grep -Ein \
        'Apply this remediation|Select action|\[y/N\]' \
        "$output" \
        >/dev/null
    then

        echo "Interactive prompt leaked into diagnose all"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 10
# Interactive non-TTY protection
# ============================================================
#

test_interactive_guard() {

    local output="$TEST_TMP/interactive-guard.out"


    "$PROJECT_ROOT/lpd.sh" \
        interactive \
        cpu \
        </dev/null \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 3 )); then

        echo "Expected interactive non-TTY exit 3, got $rc"

        cat "$output"

        return 1
    fi


    if ! grep -q \
        'Interactive mode requires a terminal' \
        "$output"
    then

        echo "Interactive TTY guard message missing"

        cat "$output"

        return 1
    fi


    if contains_ansi "$output"; then

        echo "ANSI leaked into non-TTY interactive output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 11
# Scan helper namespace regression
# ============================================================
#

test_scan_namespace() {

    (
        source "$PROJECT_ROOT/lib/common.sh"
        source "$PROJECT_ROOT/lib/ui.sh"
        source "$PROJECT_ROOT/lib/scan.sh"


        if declare -F process_result >/dev/null 2>&1; then

            echo "process_result already exists before scan"

            exit 1
        fi


        if ! declare -F lpd_scan_run_check >/dev/null 2>&1; then

            echo "Namespaced scan helper is missing"

            exit 1
        fi


        cpu_check() {
            return 0
        }

        memory_check() {
            return 0
        }

        disk_check() {
            return 0
        }

        network_check() {
            return 0
        }

        file_descriptor_check() {
            return 0
        }


        scan_run \
            >/dev/null \
            2>&1


        if declare -F process_result >/dev/null 2>&1; then

            echo "process_result leaked into global namespace"

            exit 1
        fi


        exit 0
    )

    return $?
}


#
# ============================================================
# TEST 12
# Safe regression suite
# ============================================================
#

test_safe_suite() {

    local output="$TEST_TMP/safe-suite.out"


    "$PROJECT_ROOT/tests/run-safe-tests.sh" \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 0 )); then

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 13
# UI regression suite
# ============================================================
#

test_ui_suite() {

    local output="$TEST_TMP/ui-suite.out"


    "$PROJECT_ROOT/tests/run-ui-tests.sh" \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 0 )); then

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 14
# Incident regression suite
# ============================================================
#

test_incident_suite() {

    local output="$TEST_TMP/incident-suite.out"


    "$PROJECT_ROOT/tests/run-incident-tests.sh" \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 0 )); then

        cat "$output"

        return 1
    fi


    return 0
}


#
# ------------------------------------------------------------
# RUN
# ------------------------------------------------------------
#

echo "============================================================"
echo "Linux Performance Detective"
echo "Final Regression / Release Gate"
echo "============================================================"

echo

printf "Project: %s\n" "$PROJECT_ROOT"
printf "Temp:    %s\n" "$TEST_TMP"


run_test \
    "Bash syntax" \
    test_bash_syntax


run_test \
    "Production ShellCheck" \
    test_shellcheck


run_test \
    "Version contract" \
    test_version_contract


run_test \
    "Help and frozen CLI contract" \
    test_help_contract


run_test \
    "Unknown command exit contract" \
    test_unknown_command


run_test \
    "Preflight automation contract" \
    test_preflight_contract


run_test \
    "Scan automation contract" \
    test_scan_contract


run_test \
    "Single-target diagnosis contracts" \
    test_diagnose_targets


run_test \
    "All-subsystem diagnosis contract" \
    test_diagnose_all


run_test \
    "Interactive non-TTY safety guard" \
    test_interactive_guard


run_test \
    "Scan namespace regression" \
    test_scan_namespace


run_test \
    "Safe regression suite" \
    test_safe_suite


run_test \
    "UI regression suite" \
    test_ui_suite


run_test \
    "Incident regression suite" \
    test_incident_suite


#
# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------
#

echo
echo "============================================================"
echo "LPD FINAL REGRESSION SUMMARY"
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
