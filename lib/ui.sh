#!/usr/bin/env bash


#
# ------------------------------------------------------------
# UI CAPABILITY
# ------------------------------------------------------------
#

lpd_ui_enabled() {

    [[ -t 1 ]] || return 1
    [[ "${TERM:-}" != "dumb" ]] || return 1
    [[ "${LPD_UI_DISABLE:-0}" != "1" ]] || return 1

    return 0
}


lpd_ui_color_enabled() {

    lpd_ui_enabled || return 1
    [[ "${NO_COLOR:-0}" != "1" ]] || return 1

    return 0
}


lpd_ui_unicode_enabled() {

    lpd_ui_enabled || return 1

    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf-8*|*UTF8*|*utf8*)
            return 0
            ;;
    esac

    return 1
}


#
# ------------------------------------------------------------
# UI SYMBOLS
# ------------------------------------------------------------
#

lpd_ui_symbol_ok() {

    if lpd_ui_unicode_enabled; then
        printf "✓"
    else
        printf "+"
    fi
}


lpd_ui_symbol_warning() {

    if lpd_ui_unicode_enabled; then
        printf "!"
    else
        printf "!"
    fi
}


lpd_ui_symbol_failed() {

    if lpd_ui_unicode_enabled; then
        printf "✗"
    else
        printf "X"
    fi
}


lpd_ui_symbol_unknown() {

    if lpd_ui_unicode_enabled; then
        printf "?"
    else
        printf "?"
    fi
}


#
# ------------------------------------------------------------
# BASIC DRAWING
# ------------------------------------------------------------
#

lpd_ui_repeat() {

    local character="${1:-=}"
    local count="${2:-0}"

    local output=""


    [[ "$count" =~ ^[0-9]+$ ]] || return 1


    while (( count > 0 )); do

        output+="$character"
        count=$((count - 1))
    done


    printf "%s" "$output"
}


lpd_ui_rule() {

    local width="${1:-60}"


    lpd_ui_enabled || return 0


    if lpd_ui_unicode_enabled; then

        lpd_ui_repeat "─" "$width"

    else

        lpd_ui_repeat "-" "$width"

    fi


    printf "\n"
}


#
# ------------------------------------------------------------
# BANNER
# ------------------------------------------------------------
#

lpd_ui_banner() {

    lpd_ui_enabled || {
        print_banner
        return 0
    }


    local width=58

    local top_left="+"
    local top_right="+"

    local bottom_left="+"
    local bottom_right="+"

    local horizontal="-"
    local vertical="|"


    if lpd_ui_unicode_enabled; then

        top_left="╭"
        top_right="╮"

        bottom_left="╰"
        bottom_right="╯"

        horizontal="─"
        vertical="│"

    fi


    local inner_width=$((width - 2))

    local title="$LPD_NAME"
    local version="v$LPD_VERSION"


    printf "%s" "$top_left"
    lpd_ui_repeat "$horizontal" "$inner_width"
    printf "%s\n" "$top_right"


    printf "%s %-*s %s\n" \
        "$vertical" \
        $((inner_width - 2)) \
        "$title" \
        "$vertical"


    printf "%s %-*s %s\n" \
        "$vertical" \
        $((inner_width - 2)) \
        "$version" \
        "$vertical"


    printf "%s" "$bottom_left"
    lpd_ui_repeat "$horizontal" "$inner_width"
    printf "%s\n" "$bottom_right"
}


#
# ------------------------------------------------------------
# STATUS
# ------------------------------------------------------------
#

lpd_ui_result_label() {

    local rc="${1:-3}"


    case "$rc" in
        0) printf "HEALTHY" ;;
        1) printf "ATTENTION" ;;
        2) printf "FAILED" ;;
        3) printf "UNKNOWN" ;;
        *) printf "UNKNOWN" ;;
    esac
}


lpd_ui_status() {

    local label="${1:-Unknown}"
    local rc="${2:-3}"

    local status=""
    local symbol=""

    local prefix=""
    local suffix=""


    status="$(
        lpd_ui_result_label "$rc"
    )"


    case "$rc" in

        0)
            symbol="$(
                lpd_ui_symbol_ok
            )"

            if lpd_ui_color_enabled; then
                prefix="${GREEN:-}"
                suffix="${RESET:-}"
            fi
            ;;


        1)
            symbol="$(
                lpd_ui_symbol_warning
            )"

            if lpd_ui_color_enabled; then
                prefix="${YELLOW:-}"
                suffix="${RESET:-}"
            fi
            ;;


        2)
            symbol="$(
                lpd_ui_symbol_failed
            )"

            if lpd_ui_color_enabled; then
                prefix="${RED:-}"
                suffix="${RESET:-}"
            fi
            ;;


        *)
            symbol="$(
                lpd_ui_symbol_unknown
            )"

            if lpd_ui_color_enabled; then
                prefix="${RED:-}"
                suffix="${RESET:-}"
            fi
            ;;

    esac


    printf "%-20s %b%s %-12s%b\n" \
        "$label" \
        "$prefix" \
        "$symbol" \
        "$status" \
        "$suffix"
}


#
# ------------------------------------------------------------
# WORKFLOW STAGE
# ------------------------------------------------------------
#

lpd_ui_stage() {

    local stage="${1:-}"
    local subsystem="${2:-}"


    lpd_ui_enabled || return 0


    echo

    if [[ -n "$subsystem" ]]; then

        printf "%b%s%b  %s\n" \
            "${BOLD:-}" \
            "$stage" \
            "${RESET:-}" \
            "$subsystem"

    else

        printf "%b%s%b\n" \
            "${BOLD:-}" \
            "$stage" \
            "${RESET:-}"

    fi
}


#
# ------------------------------------------------------------
# REAL PROGRESS
# ------------------------------------------------------------
#

lpd_ui_progress() {

    local current="${1:-0}"
    local total="${2:-0}"
    local label="${3:-Progress}"

    local width=24


    lpd_ui_enabled || return 0


    [[ "$current" =~ ^[0-9]+$ ]] || return 1
    [[ "$total" =~ ^[0-9]+$ ]] || return 1

    (( total > 0 )) || return 1
    (( current <= total )) || current="$total"


    local percent=$((current * 100 / total))
    local filled=$((current * width / total))

    local empty=$((width - filled))


    local fill_character="#"
    local empty_character="-"


    if lpd_ui_unicode_enabled; then
        fill_character="█"
        empty_character="░"
    fi


    local filled_text=""
    local empty_text=""


    filled_text="$(
        lpd_ui_repeat \
            "$fill_character" \
            "$filled"
    )"


    empty_text="$(
        lpd_ui_repeat \
            "$empty_character" \
            "$empty"
    )"


    printf "%-10s [%s%s] %3d%%  (%d/%d)\n" \
        "$label" \
        "$filled_text" \
        "$empty_text" \
        "$percent" \
        "$current" \
        "$total"
}


#
# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------
#

lpd_ui_summary_header() {

    lpd_ui_enabled || return 0


    echo

    lpd_ui_rule 46

    printf "%b%-20s %-14s%b\n" \
        "${BOLD:-}" \
        "Subsystem" \
        "Result" \
        "${RESET:-}"

    lpd_ui_rule 46
}


lpd_ui_overall() {

    local rc="${1:-3}"


    lpd_ui_enabled || return 0


    echo

    case "$rc" in

        0)
            ok "Overall status: HEALTHY"
            ;;

        1)
            warn "Overall status: ATTENTION"
            ;;

        2)
            fail "Overall status: FAILED"
            ;;

        *)
            fail "Overall status: UNKNOWN"
            ;;

    esac
}
