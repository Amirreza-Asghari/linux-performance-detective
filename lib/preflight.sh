#!/usr/bin/env bash


#
# ------------------------------------------------------------
# PREFLIGHT HELPERS
# ------------------------------------------------------------
#

preflight_command_available() {

    local command_name="${1:-}"


    [[ -n "$command_name" ]] || return 1


    if declare -F lpd_command_available >/dev/null 2>&1; then

        lpd_command_available "$command_name"

        return $?
    fi


    command_exists "$command_name"
}


preflight_audit() {

    local level="${1:-INFO}"
    local event="${2:-PREFLIGHT}"
    local details="${3:-}"


    if declare -F lpd_audit >/dev/null 2>&1; then

        lpd_audit \
            "$level" \
            "preflight" \
            "$event" \
            "$details"

    fi
}


#
# ------------------------------------------------------------
# WRITABLE DIRECTORY TEST
# ------------------------------------------------------------
#

preflight_check_writable_directory() {

    local directory="${1:-}"
    local label="${2:-runtime directory}"


    [[ -n "$directory" ]] || return 1


    if ! mkdir -p "$directory" 2>/dev/null; then

        fail "$label cannot be created: $directory"

        return 1
    fi


    if [[ ! -d "$directory" ]]; then

        fail "$label is not a directory: $directory"

        return 1
    fi


    local probe=""

    probe="$directory/.lpd-write-test.$$.$RANDOM"


    if ! : > "$probe" 2>/dev/null; then

        fail "$label is not writable: $directory"

        return 1
    fi


    rm -f "$probe" 2>/dev/null || true


    ok "$label writable"

    return 0
}


#
# ------------------------------------------------------------
# CONFIGURATION STATE
# ------------------------------------------------------------
#

preflight_check_configuration() {

    local config_file=""

    config_file="${LPD_CONFIG_FILE:-$ROOT_DIR/config/lpd.conf}"


    printf "Config file:      %s\n" "$config_file"


    if [[ ! -f "$config_file" ]]; then

        fail "Configuration file does not exist"

        return 1
    fi


    if [[ ! -r "$config_file" ]]; then

        fail "Configuration file is not readable"

        return 1
    fi


    ok "Configuration file readable"


    #
    # The authoritative parser and semantic relationship checks
    # belong to lib/config.sh.
    #
    # Preflight intentionally does not duplicate that parser.
    #
    # At this point we verify that representative thresholds from
    # every configuration group have actually been loaded.
    #

    local expected_variables=(
        CPU_BUSY_WARN_PCT
        CPU_BUSY_CRITICAL_PCT

        MEM_AVAILABLE_WARN_PCT
        MEM_AVAILABLE_CRITICAL_PCT

        FS_USAGE_WARN_PCT
        FS_USAGE_CRITICAL_PCT

        DISK_UTIL_WARN_PCT
        DISK_UTIL_CRITICAL_PCT

        NETWORK_TIME_WAIT_WARN
        NETWORK_TIME_WAIT_CRITICAL

        FD_PROCESS_WARN_PCT
        FD_PROCESS_CRITICAL_PCT
    )


    local variable=""
    local value=""


    for variable in "${expected_variables[@]}"; do

        value="${!variable-}"


        if [[ -z "$value" ]]; then

            fail "Configuration threshold not loaded: $variable"

            return 1
        fi


        if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

            fail "Configuration threshold is invalid: $variable=$value"

            return 1
        fi

    done


    ok "Configuration thresholds loaded"

    return 0
}


#
# ------------------------------------------------------------
# PREFLIGHT
# ------------------------------------------------------------
#

preflight_run() {

    local unsupported_count=0
    local degraded_count=0

    local os_name="Linux"
    local os_id="unknown"

    local kernel="N/A"
    local architecture="N/A"
    local hostname_value="N/A"

    local tool=""

    local config_file=""


    #
    # Exposed state for future UI/reporting.
    #

    LPD_PREFLIGHT_STATUS="UNKNOWN"
    LPD_PREFLIGHT_UNSUPPORTED_COUNT=0
    LPD_PREFLIGHT_DEGRADED_COUNT=0


    print_banner


    #
    # ------------------------------------------------------------
    # SYSTEM
    # ------------------------------------------------------------
    #

    section "System"


    if [[ -r /etc/os-release ]]; then

        local PRETTY_NAME=""
        local ID=""


        . /etc/os-release


        os_name="${PRETTY_NAME:-Linux}"
        os_id="${ID:-unknown}"

    fi


    if preflight_command_available uname; then

        kernel="$(uname -r 2>/dev/null || printf 'N/A')"
        architecture="$(uname -m 2>/dev/null || printf 'N/A')"

    fi


    if preflight_command_available hostname; then

        hostname_value="$(hostname 2>/dev/null || printf 'N/A')"

    fi


    printf "OS:              %s\n" "$os_name"
    printf "Distribution ID: %s\n" "$os_id"
    printf "Kernel:          %s\n" "$kernel"
    printf "Architecture:    %s\n" "$architecture"
    printf "Hostname:        %s\n" "$hostname_value"
    printf "Bash:            %s\n" "${BASH_VERSION:-N/A}"


    #
    # LPD uses Bash arrays and modern Bash behavior.
    #

    if (( BASH_VERSINFO[0] < 4 )); then

        fail "Bash 4 or newer is required"

        unsupported_count=$((unsupported_count + 1))

    else

        ok "Supported Bash version"

    fi


    #
    # ------------------------------------------------------------
    # PRIVILEGES
    # ------------------------------------------------------------
    #

    section "Privileges"


    if (( EUID == 0 )); then

        ok "Running as root"

    else

        warn "Running without root privileges"

        info "Core checks may work, but advanced diagnostics and process inspection can be limited"

        degraded_count=$((degraded_count + 1))

    fi


    #
    # ------------------------------------------------------------
    # LINUX INTERFACES
    # ------------------------------------------------------------
    #

    section "Linux Interfaces"


    if [[ -d /proc &&
          -r /proc/stat &&
          -r /proc/meminfo ]]; then

        ok "/proc available"

    else

        fail "Required /proc interfaces are unavailable"

        unsupported_count=$((unsupported_count + 1))

    fi


    if [[ -d /sys ]]; then

        ok "/sys available"

    else

        warn "/sys unavailable"

        info "Some disk, device and kernel diagnostics will be limited"

        degraded_count=$((degraded_count + 1))

    fi


    if [[ -d /run/systemd/system ]]; then

        ok "systemd detected"

    else

        info "systemd not detected"

        info "LPD will rely on feature detection instead of requiring systemd"

    fi


    #
    # ------------------------------------------------------------
    # CORE TOOLS
    # ------------------------------------------------------------
    #

    section "Core Tools"


    local core_tools=(
        awk
        grep
        sed
        ps
        df
        findmnt
    )


    for tool in "${core_tools[@]}"; do

        if preflight_command_available "$tool"; then

            ok "$tool"

        else

            fail "Required core tool missing: $tool"

            unsupported_count=$((unsupported_count + 1))

        fi

    done


    #
    # ------------------------------------------------------------
    # SUBSYSTEM / TELEMETRY TOOLS
    # ------------------------------------------------------------
    #

    section "Subsystem Tools"


    #
    # ss is essential for trusted Network analysis, but its
    # absence does not make CPU/Memory/Disk/FD unusable.
    #

    if preflight_command_available ss; then

        ok "ss"

    else

        warn "ss unavailable"

        info "Network socket analysis will be unavailable"

        degraded_count=$((degraded_count + 1))

    fi


    #
    # vmstat is useful telemetry but Memory already has fallback
    # behavior when it is unavailable.
    #

    if preflight_command_available vmstat; then

        ok "vmstat"

    else

        warn "vmstat unavailable"

        info "Active swap-rate telemetry will be unavailable"

        degraded_count=$((degraded_count + 1))

    fi


    #
    # ------------------------------------------------------------
    # ADVANCED DIAGNOSTIC TOOLS
    # ------------------------------------------------------------
    #

    section "Advanced Diagnostic Tools"


    local advanced_tools=(
        iostat
        strace
        perf
        bpftrace
        bpftool
        tcpconnect-bpfcc
        biolatency-bpfcc
    )


    for tool in "${advanced_tools[@]}"; do

        if preflight_command_available "$tool"; then

            ok "$tool"

        else

            warn "$tool unavailable"

            info "Related deep diagnostics will use fallback or report N/A"

            degraded_count=$((degraded_count + 1))

        fi

    done


    #
    # ------------------------------------------------------------
    # KERNEL DIAGNOSTIC FEATURES
    # ------------------------------------------------------------
    #

    section "Kernel Diagnostic Features"


    if [[ -r /proc/pressure/cpu &&
          -r /proc/pressure/memory &&
          -r /proc/pressure/io ]]; then

        ok "PSI available"

    else

        warn "PSI unavailable"

        info "Pressure-based evidence will be limited"

        degraded_count=$((degraded_count + 1))

    fi


    if [[ -r /sys/kernel/btf/vmlinux ]]; then

        ok "Kernel BTF available"

    else

        warn "Kernel BTF unavailable"

        info "Some eBPF diagnostics may be unavailable"

        degraded_count=$((degraded_count + 1))

    fi


    #
    # ------------------------------------------------------------
    # EBPF READINESS
    # ------------------------------------------------------------
    #

    section "eBPF Readiness"


    if preflight_command_available bpftool &&
       [[ -r /sys/kernel/btf/vmlinux ]]
    then

        if (( EUID == 0 )); then

            if bpftool feature probe kernel >/dev/null 2>&1; then

                ok "Kernel eBPF feature probe succeeded"

            else

                warn "Kernel eBPF feature probe failed"

                info "BCC/bpftrace diagnostics may not operate correctly"

                degraded_count=$((degraded_count + 1))

            fi

        else

            warn "eBPF readiness cannot be fully verified without root"

        fi

    else

        warn "eBPF readiness cannot be fully verified"

    fi


    #
    # ------------------------------------------------------------
    # CONFIGURATION
    # ------------------------------------------------------------
    #

    section "Configuration"


    config_file="${LPD_CONFIG_FILE:-$ROOT_DIR/config/lpd.conf}"


    if preflight_check_configuration; then

        preflight_audit \
            "INFO" \
            "CONFIG_READY" \
            "file=$config_file"

    else

        unsupported_count=$((unsupported_count + 1))


        preflight_audit \
            "ERROR" \
            "CONFIG_NOT_READY" \
            "file=$config_file"

    fi


    #
    # ------------------------------------------------------------
    # RUNTIME PATHS
    # ------------------------------------------------------------
    #

    section "Runtime Paths"


    if ! preflight_check_writable_directory \
        "$ROOT_DIR/logs" \
        "Log directory"
    then

        unsupported_count=$((unsupported_count + 1))

    fi


    if ! preflight_check_writable_directory \
        "$ROOT_DIR/reports" \
        "Report directory"
    then

        unsupported_count=$((unsupported_count + 1))

    fi


    if ! preflight_check_writable_directory \
        "$ROOT_DIR/evidence" \
        "Evidence directory"
    then

        unsupported_count=$((unsupported_count + 1))

    fi


    #
    # ------------------------------------------------------------
    # FINAL READINESS RESULT
    # ------------------------------------------------------------
    #

    section "Preflight Result"


    LPD_PREFLIGHT_UNSUPPORTED_COUNT="$unsupported_count"
    LPD_PREFLIGHT_DEGRADED_COUNT="$degraded_count"


    if (( unsupported_count > 0 )); then

        LPD_PREFLIGHT_STATUS="UNSUPPORTED"


        fail "UNSUPPORTED"

        printf "Blocking issues:     %s\n" "$unsupported_count"
        printf "Degraded features:   %s\n" "$degraded_count"


        info "LPD cannot be trusted for normal operation until blocking issues are resolved."


        preflight_audit \
            "ERROR" \
            "UNSUPPORTED" \
            "blocking=$unsupported_count degraded=$degraded_count"


        return 3
    fi


    if (( degraded_count > 0 )); then

        LPD_PREFLIGHT_STATUS="DEGRADED"


        warn "DEGRADED"

        printf "Blocking issues:     0\n"
        printf "Degraded features:   %s\n" "$degraded_count"


        info "Core LPD functionality is available, but some diagnostics are limited."


        preflight_audit \
            "WARNING" \
            "DEGRADED" \
            "blocking=0 degraded=$degraded_count"


        return 1
    fi


    LPD_PREFLIGHT_STATUS="READY"


    ok "READY"

    printf "Blocking issues:     0\n"
    printf "Degraded features:   0\n"


    ok "System is fully ready for the detected LPD feature set"


    preflight_audit \
        "INFO" \
        "READY" \
        "blocking=0 degraded=0"


    return 0
}
