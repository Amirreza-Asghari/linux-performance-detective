#!/usr/bin/env bash


LPD_TEST_PASS=0
LPD_TEST_FAIL=0
LPD_TEST_SKIP=0

LPD_TEST_TOTAL=0


lpd_test_pass() {

    local name="${1:-Unnamed test}"

    LPD_TEST_PASS=$((LPD_TEST_PASS + 1))

    printf "[PASS] %s\n" "$name"
}


lpd_test_fail() {

    local name="${1:-Unnamed test}"

    LPD_TEST_FAIL=$((LPD_TEST_FAIL + 1))

    printf "[FAIL] %s\n" "$name"
}


lpd_test_skip() {

    local name="${1:-Unnamed test}"

    LPD_TEST_SKIP=$((LPD_TEST_SKIP + 1))

    printf "[SKIP] %s\n" "$name"
}


lpd_run_test() {

    local name="${1:-Unnamed test}"
    local function_name="${2:-}"


    LPD_TEST_TOTAL=$((LPD_TEST_TOTAL + 1))


    printf "\n[%02d] %s\n" \
        "$LPD_TEST_TOTAL" \
        "$name"


    if ! declare -F "$function_name" >/dev/null 2>&1; then

        echo "Test function missing: $function_name"

        lpd_test_fail "$name"

        return 0
    fi


    "$function_name"

    local rc=$?


    case "$rc" in

        0)

            lpd_test_pass "$name"
            ;;


        77)

            lpd_test_skip "$name"
            ;;


        *)

            lpd_test_fail "$name"
            ;;

    esac


    return 0
}


lpd_test_summary() {

    echo
    echo "============================================================"
    echo "LPD SAFE TEST SUMMARY"
    echo "============================================================"

    printf "Total:   %s\n" "$LPD_TEST_TOTAL"
    printf "Passed:  %s\n" "$LPD_TEST_PASS"
    printf "Failed:  %s\n" "$LPD_TEST_FAIL"
    printf "Skipped: %s\n" "$LPD_TEST_SKIP"

    echo


    if (( LPD_TEST_FAIL > 0 )); then

        echo "RESULT: FAIL"

        return 1
    fi


    echo "RESULT: PASS"

    return 0
}
