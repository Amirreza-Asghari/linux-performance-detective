#!/usr/bin/env bash


#
# ------------------------------------------------------------
# DEFAULTS
# ------------------------------------------------------------
#

lpd_config_defaults() {

    #
    # CPU
    #

    CPU_BUSY_WARN_PCT=85
    CPU_BUSY_CRITICAL_PCT=95

    CPU_LOAD_PER_CPU_WARN=1.00
    CPU_LOAD_PER_CPU_CRITICAL=2.00

    CPU_PROCESS_SATURATION_PCT=90

    CPU_PSI_WARN_PCT=10
    CPU_PSI_CRITICAL_PCT=25

    CPU_VERIFY_HEALTHY_BUSY_PCT=85


    #
    # MEMORY
    #

    MEM_AVAILABLE_WARN_PCT=25
    MEM_AVAILABLE_SWAP_CRITICAL_PCT=15
    MEM_AVAILABLE_CRITICAL_PCT=8

    MEM_SWAP_ACTIVITY_WARN_KB=1024
    MEM_SWAP_ACTIVITY_CRITICAL_KB=4096

    MEM_PSI_SOME_WARN_PCT=10
    MEM_PSI_SOME_CRITICAL_PCT=25
    MEM_PSI_FULL_CRITICAL_PCT=10

    MEM_PROCESS_MEDIUM_CONFIDENCE_PCT=20
    MEM_PROCESS_HIGH_CONFIDENCE_PCT=40
    MEM_PROCESS_REMEDIATE_MIN_PCT=20

    MEM_VERIFY_MIN_AVAILABLE_PCT=25
    MEM_VERIFY_MAX_PSI_PCT=10
    MEM_VERIFY_MAX_SWAP_KB=1024

    MEM_MITIGATION_IMPROVEMENT_PCT=5


    #
    # FILESYSTEM
    #

    FS_USAGE_WARN_PCT=85
    FS_USAGE_CRITICAL_PCT=95

    FS_INODE_WARN_PCT=85
    FS_INODE_CRITICAL_PCT=95


    #
    # DISK
    #

    DISK_UTIL_WARN_PCT=80
    DISK_UTIL_CRITICAL_PCT=95

    DISK_AWAIT_WARN_MS=20
    DISK_AWAIT_CRITICAL_MS=100

    DISK_QUEUE_WARN=1
    DISK_QUEUE_CRITICAL=2

    DISK_CULPRIT_MEDIUM_KBPS=512
    DISK_CULPRIT_HIGH_KBPS=1024


    #
    # NETWORK
    #

    NETWORK_TIME_WAIT_WARN=1000
    NETWORK_TIME_WAIT_CRITICAL=5000

    NETWORK_RETRANS_WARN=10
    NETWORK_RETRANS_CRITICAL=100

    NETWORK_SYN_WARN=100
    NETWORK_SYN_CRITICAL=500

    NETWORK_CONNECT_WARN_5S=20
    NETWORK_CONNECT_CRITICAL_5S=500

    NETWORK_TOP_CONNECT_MEDIUM_5S=5
    NETWORK_TOP_CONNECT_HIGH_5S=20

    NETWORK_VERIFY_CONNECT_MAX_3S=5


    #
    # FILE DESCRIPTORS
    #

    FD_PROCESS_WARN_PCT=80
    FD_PROCESS_CRITICAL_PCT=95

    FD_SYSTEM_WARN_PCT=80
    FD_SYSTEM_CRITICAL_PCT=95
}


#
# ------------------------------------------------------------
# TRIM
# ------------------------------------------------------------
#

lpd_config_trim() {

    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"

    value="${value%"${value##*[![:space:]]}"}"

    printf "%s" "$value"
}


#
# ------------------------------------------------------------
# ALLOWED KEYS
# ------------------------------------------------------------
#

lpd_config_key_allowed() {

    local key="${1:-}"


    case "$key" in

        CPU_BUSY_WARN_PCT|\
        CPU_BUSY_CRITICAL_PCT|\
        CPU_LOAD_PER_CPU_WARN|\
        CPU_LOAD_PER_CPU_CRITICAL|\
        CPU_PROCESS_SATURATION_PCT|\
        CPU_PSI_WARN_PCT|\
        CPU_PSI_CRITICAL_PCT|\
        CPU_VERIFY_HEALTHY_BUSY_PCT|\
        MEM_AVAILABLE_WARN_PCT|\
        MEM_AVAILABLE_SWAP_CRITICAL_PCT|\
        MEM_AVAILABLE_CRITICAL_PCT|\
        MEM_SWAP_ACTIVITY_WARN_KB|\
        MEM_SWAP_ACTIVITY_CRITICAL_KB|\
        MEM_PSI_SOME_WARN_PCT|\
        MEM_PSI_SOME_CRITICAL_PCT|\
        MEM_PSI_FULL_CRITICAL_PCT|\
        MEM_PROCESS_MEDIUM_CONFIDENCE_PCT|\
        MEM_PROCESS_HIGH_CONFIDENCE_PCT|\
        MEM_PROCESS_REMEDIATE_MIN_PCT|\
        MEM_VERIFY_MIN_AVAILABLE_PCT|\
        MEM_VERIFY_MAX_PSI_PCT|\
        MEM_VERIFY_MAX_SWAP_KB|\
        MEM_MITIGATION_IMPROVEMENT_PCT|\
        FS_USAGE_WARN_PCT|\
        FS_USAGE_CRITICAL_PCT|\
        FS_INODE_WARN_PCT|\
        FS_INODE_CRITICAL_PCT|\
        DISK_UTIL_WARN_PCT|\
        DISK_UTIL_CRITICAL_PCT|\
        DISK_AWAIT_WARN_MS|\
        DISK_AWAIT_CRITICAL_MS|\
        DISK_QUEUE_WARN|\
        DISK_QUEUE_CRITICAL|\
        DISK_CULPRIT_MEDIUM_KBPS|\
        DISK_CULPRIT_HIGH_KBPS|\
        NETWORK_TIME_WAIT_WARN|\
        NETWORK_TIME_WAIT_CRITICAL|\
        NETWORK_RETRANS_WARN|\
        NETWORK_RETRANS_CRITICAL|\
        NETWORK_SYN_WARN|\
        NETWORK_SYN_CRITICAL|\
        NETWORK_CONNECT_WARN_5S|\
        NETWORK_CONNECT_CRITICAL_5S|\
        NETWORK_TOP_CONNECT_MEDIUM_5S|\
        NETWORK_TOP_CONNECT_HIGH_5S|\
        NETWORK_VERIFY_CONNECT_MAX_3S|\
        FD_PROCESS_WARN_PCT|\
        FD_PROCESS_CRITICAL_PCT|\
        FD_SYSTEM_WARN_PCT|\
        FD_SYSTEM_CRITICAL_PCT)

            return 0
            ;;

        *)

            return 1
            ;;

    esac
}


#
# ------------------------------------------------------------
# NUMERIC VALUE
# ------------------------------------------------------------
#

lpd_config_value_valid() {

    local value="${1:-}"

    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]
}


#
# ------------------------------------------------------------
# PERCENTAGE KEYS
# ------------------------------------------------------------
#

lpd_config_percentage_key() {

    local key="${1:-}"


    case "$key" in

        *_PCT)

            return 0
            ;;

        *)

            return 1
            ;;

    esac
}


#
# ------------------------------------------------------------
# PERCENTAGE RANGE
# ------------------------------------------------------------
#

lpd_config_percentage_valid() {

    local value="${1:-}"


    awk \
        -v value="$value" \
        'BEGIN {
            if (value >= 0 && value <= 100)
                exit 0

            exit 1
        }'
}


#
# ------------------------------------------------------------
# RELATION HELPER
# ------------------------------------------------------------
#

lpd_config_less_than() {

    local lower="$1"
    local upper="$2"


    awk \
        -v lower="$lower" \
        -v upper="$upper" \
        'BEGIN {
            if (lower < upper)
                exit 0

            exit 1
        }'
}


#
# ------------------------------------------------------------
# LOGICAL VALIDATION
# ------------------------------------------------------------
#

lpd_config_validate_relationships() {

    local errors=0


    if ! lpd_config_less_than \
        "$CPU_BUSY_WARN_PCT" \
        "$CPU_BUSY_CRITICAL_PCT"
    then

        fail "Config error: CPU busy warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$CPU_LOAD_PER_CPU_WARN" \
        "$CPU_LOAD_PER_CPU_CRITICAL"
    then

        fail "Config error: CPU load warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$CPU_PSI_WARN_PCT" \
        "$CPU_PSI_CRITICAL_PCT"
    then

        fail "Config error: CPU PSI warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$MEM_AVAILABLE_CRITICAL_PCT" \
        "$MEM_AVAILABLE_SWAP_CRITICAL_PCT"
    then

        fail "Config error: critical memory availability must be lower than swap-critical availability"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$MEM_AVAILABLE_SWAP_CRITICAL_PCT" \
        "$MEM_AVAILABLE_WARN_PCT"
    then

        fail "Config error: swap-critical memory availability must be lower than warning availability"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$MEM_SWAP_ACTIVITY_WARN_KB" \
        "$MEM_SWAP_ACTIVITY_CRITICAL_KB"
    then

        fail "Config error: memory swap warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$MEM_PSI_SOME_WARN_PCT" \
        "$MEM_PSI_SOME_CRITICAL_PCT"
    then

        fail "Config error: memory PSI warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$MEM_PROCESS_MEDIUM_CONFIDENCE_PCT" \
        "$MEM_PROCESS_HIGH_CONFIDENCE_PCT"
    then

        fail "Config error: memory medium confidence must be lower than high confidence"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$FS_USAGE_WARN_PCT" \
        "$FS_USAGE_CRITICAL_PCT"
    then

        fail "Config error: filesystem warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$FS_INODE_WARN_PCT" \
        "$FS_INODE_CRITICAL_PCT"
    then

        fail "Config error: inode warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$DISK_UTIL_WARN_PCT" \
        "$DISK_UTIL_CRITICAL_PCT"
    then

        fail "Config error: disk utilization warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$DISK_AWAIT_WARN_MS" \
        "$DISK_AWAIT_CRITICAL_MS"
    then

        fail "Config error: disk await warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$DISK_QUEUE_WARN" \
        "$DISK_QUEUE_CRITICAL"
    then

        fail "Config error: disk queue warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$DISK_CULPRIT_MEDIUM_KBPS" \
        "$DISK_CULPRIT_HIGH_KBPS"
    then

        fail "Config error: disk medium confidence must be lower than high confidence"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$NETWORK_TIME_WAIT_WARN" \
        "$NETWORK_TIME_WAIT_CRITICAL"
    then

        fail "Config error: TIME-WAIT warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$NETWORK_RETRANS_WARN" \
        "$NETWORK_RETRANS_CRITICAL"
    then

        fail "Config error: retransmit warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$NETWORK_SYN_WARN" \
        "$NETWORK_SYN_CRITICAL"
    then

        fail "Config error: SYN warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$NETWORK_CONNECT_WARN_5S" \
        "$NETWORK_CONNECT_CRITICAL_5S"
    then

        fail "Config error: connection warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$NETWORK_TOP_CONNECT_MEDIUM_5S" \
        "$NETWORK_TOP_CONNECT_HIGH_5S"
    then

        fail "Config error: network medium confidence must be lower than high confidence"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$FD_PROCESS_WARN_PCT" \
        "$FD_PROCESS_CRITICAL_PCT"
    then

        fail "Config error: process FD warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if ! lpd_config_less_than \
        "$FD_SYSTEM_WARN_PCT" \
        "$FD_SYSTEM_CRITICAL_PCT"
    then

        fail "Config error: system FD warning must be lower than critical"

        errors=$((errors + 1))
    fi


    if (( errors > 0 )); then
        return 1
    fi


    return 0
}


#
# ------------------------------------------------------------
# LOAD CONFIGURATION
# ------------------------------------------------------------
#

lpd_config_load() {

    local config_file="${1:-$ROOT_DIR/config/lpd.conf}"


    lpd_config_defaults


    LPD_CONFIG_FILE="$config_file"
    LPD_CONFIG_SOURCE="defaults"


    if [[ ! -e "$config_file" ]]; then

        warn "Configuration file not found: $config_file"

        info "Using built-in threshold defaults"


        lpd_audit \
            "WARNING" \
            "config" \
            "CONFIG_MISSING" \
            "file=$config_file using=built-in-defaults"


        return 0
    fi


    if [[ ! -f "$config_file" ]]; then

        fail "Configuration path is not a regular file: $config_file"

        return 1
    fi


    if [[ ! -r "$config_file" ]]; then

        fail "Configuration file is not readable: $config_file"

        return 1
    fi


    local line=""
    local line_number=0

    local key=""
    local value=""


    while IFS= read -r line || [[ -n "$line" ]]; do

        line_number=$((line_number + 1))


        line="${line%$'\r'}"

        line="$(
            lpd_config_trim "$line"
        )"


        [[ -n "$line" ]] || continue

        [[ "${line:0:1}" != "#" ]] || continue


        if [[ "$line" != *"="* ]]; then

            fail "Config parse error at line $line_number: expected KEY=VALUE"

            return 1
        fi


        key="${line%%=*}"
        value="${line#*=}"


        key="$(
            lpd_config_trim "$key"
        )"


        value="$(
            lpd_config_trim "$value"
        )"


        if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then

            fail "Config parse error at line $line_number: invalid key '$key'"

            return 1
        fi


        if ! lpd_config_key_allowed "$key"; then

            fail "Unknown configuration key at line $line_number: $key"

            return 1
        fi


        if ! lpd_config_value_valid "$value"; then

            fail "Invalid numeric value for $key at line $line_number: '$value'"

            return 1
        fi


        if lpd_config_percentage_key "$key"; then

            if ! lpd_config_percentage_valid "$value"; then

                fail "Percentage out of range for $key at line $line_number: '$value'"

                return 1
            fi

        fi


        printf -v "$key" '%s' "$value"

    done < "$config_file"


    if ! lpd_config_validate_relationships; then

        fail "Configuration validation failed"

        return 1
    fi


    LPD_CONFIG_SOURCE="file"


    lpd_audit \
        "INFO" \
        "config" \
        "CONFIG_LOADED" \
        "file=$config_file"


    return 0
}
