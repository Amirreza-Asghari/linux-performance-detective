#!/usr/bin/env bash


#
# ------------------------------------------------------------
# PID EXISTS
# ------------------------------------------------------------
#

lpd_pid_exists() {

    local pid="${1:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    (( pid > 1 )) || return 1


    [[ -d "/proc/$pid" ]]
}


#
# ------------------------------------------------------------
# READ PID STAT
# ------------------------------------------------------------
#

lpd_pid_stat_line() {

    local pid="${1:-}"


    lpd_pid_exists "$pid" || return 1


    local stat_file="/proc/$pid/stat"


    [[ -r "$stat_file" ]] || return 1


    local stat_line=""


    IFS= read -r stat_line < "$stat_file" || return 1


    [[ -n "$stat_line" ]] || return 1


    #
    # Must contain the closing ")" that terminates comm.
    #

    [[ "$stat_line" == *") "* ]] || return 1


    printf "%s\n" "$stat_line"
}


#
# ------------------------------------------------------------
# PID START TIME
# ------------------------------------------------------------
#
# /proc/PID/stat field 22 = process starttime.
#
# We deliberately do NOT use:
#
#     awk '{print $22}'
#
# because field 2 (comm) can contain spaces.
#

lpd_pid_starttime() {

    local pid="${1:-}"


    local stat_line=""


    stat_line=$(
        lpd_pid_stat_line "$pid"
    ) || return 1


    #
    # Strip:
    #
    #   PID (process name)
    #
    # Everything after ") " begins with field 3 (state).
    #

    local remainder="${stat_line##*) }"


    [[ -n "$remainder" ]] || return 1


    local fields=()


    read -r -a fields <<< "$remainder"


    #
    # Array index:
    #
    # fields[0]  = original field 3
    # fields[19] = original field 22
    #

    [[ ${#fields[@]} -gt 19 ]] || return 1


    local start_time="${fields[19]}"


    [[ "$start_time" =~ ^[0-9]+$ ]] || return 1


    printf "%s\n" "$start_time"
}


#
# ------------------------------------------------------------
# PID STATE
# ------------------------------------------------------------
#

lpd_pid_state() {

    local pid="${1:-}"


    local stat_line=""


    stat_line=$(
        lpd_pid_stat_line "$pid"
    ) || return 1


    local remainder="${stat_line##*) }"


    [[ -n "$remainder" ]] || return 1


    local fields=()


    read -r -a fields <<< "$remainder"


    [[ ${#fields[@]} -gt 0 ]] || return 1


    local state="${fields[0]}"


    [[ -n "$state" ]] || return 1


    printf "%s\n" "$state"
}


#
# ------------------------------------------------------------
# PID COMMAND
# ------------------------------------------------------------
#

lpd_pid_command() {

    local pid="${1:-}"


    lpd_pid_exists "$pid" || return 1


    local comm_file="/proc/$pid/comm"


    [[ -r "$comm_file" ]] || return 1


    local command=""


    IFS= read -r command < "$comm_file" || return 1


    [[ -n "$command" ]] || return 1


    printf "%s\n" "$command"
}


#
# ------------------------------------------------------------
# CAPTURE STABLE PID IDENTITY
# ------------------------------------------------------------
#
# Important race protection:
#
#   starttime #1
#   command
#   starttime #2
#
# If PID disappeared/reused while we were inspecting it,
# the two start times will not remain identical.
#

lpd_capture_pid_identity() {

    local pid="${1:-}"
    local expected_command="${2:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    (( pid > 1 )) || return 1


    local first_start=""

    local current_command=""

    local second_start=""

    local current_state=""


    first_start=$(
        lpd_pid_starttime "$pid"
    ) || return 1


    current_command=$(
        lpd_pid_command "$pid"
    ) || return 1


    current_state=$(
        lpd_pid_state "$pid"
    ) || return 1


    #
    # Zombie processes are not actionable targets.
    #

    if [[ "$current_state" == "Z" ]]; then
        return 1
    fi


    second_start=$(
        lpd_pid_starttime "$pid"
    ) || return 1


    #
    # Identity changed while being captured.
    #

    [[ "$first_start" == "$second_start" ]] || return 1


    if [[ -n "$expected_command" ]] &&
       [[ "$current_command" != "$expected_command" ]]; then

        return 1
    fi


    printf "%s\n" "$first_start"
}


#
# ------------------------------------------------------------
# VALIDATE EXISTING PID IDENTITY
# ------------------------------------------------------------
#

lpd_pid_identity_valid() {

    local pid="${1:-}"
    local expected_start="${2:-}"
    local expected_command="${3:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    (( pid > 1 )) || return 1


    [[ "$expected_start" =~ ^[0-9]+$ ]] || return 1


    local first_start=""

    local current_command=""

    local current_state=""

    local second_start=""


    first_start=$(
        lpd_pid_starttime "$pid"
    ) || return 1


    [[ "$first_start" == "$expected_start" ]] || return 1


    current_command=$(
        lpd_pid_command "$pid"
    ) || return 1


    if [[ -n "$expected_command" ]] &&
       [[ "$current_command" != "$expected_command" ]]; then

        return 1
    fi


    current_state=$(
        lpd_pid_state "$pid"
    ) || return 1


    if [[ "$current_state" == "Z" ]]; then
        return 1
    fi


    second_start=$(
        lpd_pid_starttime "$pid"
    ) || return 1


    [[ "$second_start" == "$expected_start" ]] || return 1


    return 0
}


#
# ------------------------------------------------------------
# PROTECTED PROCESS POLICY
# ------------------------------------------------------------
#

lpd_process_is_protected() {

    local command="${1:-}"


    case "$command" in

        systemd|\
        init|\
        kthreadd|\
        kworker*|\
        ksoftirqd*|\
        kswapd*|\
        rcu*|\
        migration*|\
        watchdog*|\
        systemd-journald|\
        systemd-logind|\
        systemd-udevd|\
        systemd-networkd|\
        systemd-resolved|\
        NetworkManager|\
        dbus-daemon|\
        sshd)

            return 0
            ;;


        *)

            return 1
            ;;

    esac
}


#
# ------------------------------------------------------------
# FINAL PRE-ACTION SAFETY CHECK
# ------------------------------------------------------------
#
# Despite the historical function name, this helper is also
# valid immediately before non-signal process mutations such
# as ionice.
#

lpd_signal_target_safe() {

    local pid="${1:-}"
    local expected_start="${2:-}"
    local expected_command="${3:-}"


    [[ "$pid" =~ ^[0-9]+$ ]] || return 1


    if (( pid == $$ )); then
        return 1
    fi


    if (( pid == PPID )); then
        return 1
    fi


    if lpd_process_is_protected "$expected_command"; then
        return 1
    fi


    if ! lpd_pid_identity_valid \
        "$pid" \
        "$expected_start" \
        "$expected_command"
    then

        return 1
    fi


    return 0
}
