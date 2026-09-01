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
    mktemp -d /tmp/lpd-ui-tests.XXXXXX
)" || exit 1


cleanup_ui_tests() {

    rm -rf -- "$TEST_TMP"
}


trap cleanup_ui_tests EXIT


#
# ============================================================
# TEST 01
# UI-related Bash syntax
# ============================================================
#

test_ui_syntax() {

    local file=""

    for file in \
        "$PROJECT_ROOT/lpd.sh" \
        "$PROJECT_ROOT/lib/common.sh" \
        "$PROJECT_ROOT/lib/ui.sh" \
        "$PROJECT_ROOT/lib/scan.sh" \
        "$PROJECT_ROOT/lib/interactive.sh"
    do

        if ! bash -n "$file"; then

            echo "Syntax failure: $file"

            return 1
        fi

    done


    return 0
}


#
# ============================================================
# TEST 02
# Redirected scan must contain no ANSI or TTY decoration
# ============================================================
#

test_scan_non_tty() {

    local output="$TEST_TMP/scan.out"


    "$PROJECT_ROOT/lpd.sh" scan \
        > "$output" \
        2>&1

    local rc=$?


    case "$rc" in
        0|1|2|3)
            ;;
        *)
            echo "Unexpected scan exit code: $rc"
            return 1
            ;;
    esac


    if grep -q $'\033' "$output"; then

        echo "ANSI escape sequence leaked into redirected scan"

        return 1
    fi


    if grep -Eq \
        'Progress|Workflow|╭|╮|╰|╯|█|░' \
        "$output"
    then

        echo "TTY UI leaked into redirected scan"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 03
# Interactive mode must fail fast without a TTY
# ============================================================
#

test_interactive_tty_guard() {

    local output="$TEST_TMP/interactive-nontty.out"


    "$PROJECT_ROOT/lpd.sh" interactive cpu \
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

        echo "TTY guard message missing"

        cat "$output"

        return 1
    fi


    if grep -q $'\033' "$output"; then

        echo "ANSI leaked into non-TTY interactive output"

        return 1
    fi


    if grep -Ein \
        'Select action|Apply this remediation|\[y/N\]' \
        "$output" \
        >/dev/null
    then

        echo "Interactive prompt appeared without a TTY"

        cat "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 04
# UI must actually activate on a pseudo-terminal
# ============================================================
#

test_ui_real_tty() {

    if ! command -v script >/dev/null 2>&1; then

        echo "script command unavailable"

        return 77
    fi


    local helper="$TEST_TMP/ui-helper.sh"
    local output="$TEST_TMP/ui-tty.out"


    cat > "$helper" <<EOF
#!/usr/bin/env bash

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/ui.sh"

lpd_ui_banner
lpd_ui_progress 1 5 "Scan"
lpd_ui_status "CPU" 0
EOF


    chmod +x "$helper"


    script \
        -q \
        -e \
        -c "$helper" \
        /dev/null \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 0 )); then

        echo "Pseudo-terminal UI test failed with exit $rc"

        cat -v "$output"

        return 1
    fi


    if ! grep -q \
        '20%' \
        "$output"
    then

        echo "Real progress was not rendered on a TTY"

        cat -v "$output"

        return 1
    fi


    if ! grep -q \
        'HEALTHY' \
        "$output"
    then

        echo "TTY status rendering is missing"

        cat -v "$output"

        return 1
    fi


    return 0
}


#
# ============================================================
# TEST 05
# NO_COLOR must disable ANSI even on a real TTY
# ============================================================
#

test_no_color_tty() {

    if ! command -v script >/dev/null 2>&1; then

        echo "script command unavailable"

        return 77
    fi


    local helper="$TEST_TMP/no-color-helper.sh"
    local output="$TEST_TMP/no-color.out"


    cat > "$helper" <<EOF
#!/usr/bin/env bash

export NO_COLOR=1

source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/ui.sh"

lpd_ui_banner
lpd_ui_progress 2 5 "Scan"
lpd_ui_status "CPU" 0
EOF


    chmod +x "$helper"


    script \
        -q \
        -e \
        -c "$helper" \
        /dev/null \
        > "$output" \
        2>&1

    local rc=$?


    if (( rc != 0 )); then

        echo "NO_COLOR pseudo-terminal test failed with exit $rc"

        cat -v "$output"

        return 1
    fi


    if grep -q $'\033' "$output"; then

        echo "ANSI was emitted despite NO_COLOR=1"

        cat -v "$output"

        return 1
    fi


    if ! grep -q \
        '40%' \
        "$output"
    then

        echo "NO_COLOR incorrectly disabled progress information"

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
echo "UI Regression Test Suite"
echo "============================================================"

echo

printf "Project: %s\n" "$PROJECT_ROOT"
printf "Temp:    %s\n" "$TEST_TMP"


lpd_run_test \
    "UI Bash syntax" \
    test_ui_syntax


lpd_run_test \
    "Non-TTY scan has no decorative UI" \
    test_scan_non_tty


lpd_run_test \
    "Interactive non-TTY guard" \
    test_interactive_tty_guard


lpd_run_test \
    "TTY UI rendering" \
    test_ui_real_tty


lpd_run_test \
    "NO_COLOR TTY behavior" \
    test_no_color_tty


lpd_test_summary

exit $?
