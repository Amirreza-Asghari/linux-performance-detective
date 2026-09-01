#!/usr/bin/env bash

set -u
set -o pipefail


ROOT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"


#
# ------------------------------------------------------------
# CORE
# ------------------------------------------------------------
#

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/safety.sh"
source "$ROOT_DIR/lib/logger.sh"
source "$ROOT_DIR/lib/runtime.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/capabilities.sh"
source "$ROOT_DIR/lib/evidence.sh"
source "$ROOT_DIR/lib/report.sh"
source "$ROOT_DIR/lib/preflight.sh"


#
# ------------------------------------------------------------
# CHECKS
# ------------------------------------------------------------
#

source "$ROOT_DIR/checks/cpu.sh"
source "$ROOT_DIR/checks/memory.sh"
source "$ROOT_DIR/checks/disk.sh"
source "$ROOT_DIR/checks/network.sh"
source "$ROOT_DIR/checks/file-descriptors.sh"


#
# ------------------------------------------------------------
# DIAGNOSTICS
# ------------------------------------------------------------
#

source "$ROOT_DIR/diagnostics/cpu.sh"
source "$ROOT_DIR/diagnostics/memory.sh"
source "$ROOT_DIR/diagnostics/disk.sh"
source "$ROOT_DIR/diagnostics/network.sh"
source "$ROOT_DIR/diagnostics/file-descriptors.sh"


#
# ------------------------------------------------------------
# REMEDIATION
# ------------------------------------------------------------
#

source "$ROOT_DIR/fixes/cpu.sh"
source "$ROOT_DIR/fixes/memory.sh"
source "$ROOT_DIR/fixes/disk.sh"
source "$ROOT_DIR/fixes/network.sh"
source "$ROOT_DIR/fixes/file-descriptors.sh"


#
# ------------------------------------------------------------
# VERIFICATION
# ------------------------------------------------------------
#

source "$ROOT_DIR/verify/cpu.sh"
source "$ROOT_DIR/verify/memory.sh"
source "$ROOT_DIR/verify/disk.sh"
source "$ROOT_DIR/verify/network.sh"
source "$ROOT_DIR/verify/file-descriptors.sh"


#
# ------------------------------------------------------------
# ENGINES
# ------------------------------------------------------------
#

source "$ROOT_DIR/lib/scan.sh"
source "$ROOT_DIR/lib/diagnose.sh"
source "$ROOT_DIR/lib/interactive.sh"


#
# ------------------------------------------------------------
# RUN INITIALIZATION
# ------------------------------------------------------------
#

lpd_log_init "$*"


trap 'lpd_exit_handler' EXIT
trap 'lpd_signal_handler INT' INT
trap 'lpd_signal_handler TERM' TERM


#
# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------
#

case "${1:-help}" in

    preflight|scan|diagnose|interactive)

        LPD_CONFIG_FILE="${LPD_CONFIG_FILE:-$ROOT_DIR/config/lpd.conf}"


        if ! lpd_config_load "$LPD_CONFIG_FILE"; then

            lpd_audit \
                "ERROR" \
                "config" \
                "CONFIG_INVALID" \
                "file=$LPD_CONFIG_FILE"


            fail "LPD configuration is invalid"

            exit 3
        fi
        ;;

esac


#
# ------------------------------------------------------------
# MODULE VALIDATION
# ------------------------------------------------------------
#

validate_modules() {

    local missing=0


    local required_functions=(

        lpd_ui_enabled
        lpd_ui_banner
        lpd_ui_progress
        lpd_ui_summary_header
        lpd_ui_status
        lpd_ui_overall

        lpd_pid_starttime
        lpd_capture_pid_identity
        lpd_pid_identity_valid
        lpd_signal_target_safe

        lpd_runtime_register_pid
        lpd_runtime_unregister_pid
        lpd_runtime_register_file
        lpd_runtime_unregister_file
        lpd_runtime_cleanup
        lpd_exit_handler

        lpd_config_defaults
        lpd_config_load
        lpd_config_validate_relationships

        lpd_command_available
        lpd_require_command
        lpd_optional_command

        lpd_log_init
        lpd_audit
        lpd_record_remediation

        lpd_collect_all_evidence
        lpd_report_generate

        cpu_check
        memory_check
        disk_check
        network_check
        file_descriptor_check

        cpu_diagnose
        memory_diagnose
        disk_diagnose
        network_diagnose
        fd_diagnose

        lpd_diagnose_result_label
        lpd_diagnose_run_one
        diagnose_all_run

        cpu_remediate
        memory_remediate
        disk_remediate
        network_remediate
        fd_remediate

        cpu_verify
        memory_verify
        disk_verify
        network_verify
        fd_verify

        scan_run
        interactive_run
    )


    local function_name=""


    for function_name in "${required_functions[@]}"; do

        if ! declare -F "$function_name" >/dev/null 2>&1; then

            fail "Required module function missing: $function_name"

            missing=$((missing + 1))
        fi

    done


    if (( missing > 0 )); then

        fail "LPD initialization failed"

        return 1
    fi


    return 0
}


#
# ------------------------------------------------------------
# INTERACTIVE TERMINAL SAFETY
# ------------------------------------------------------------
#

require_interactive_terminal() {

    if [[ ! -t 0 || ! -t 1 ]]; then

        fail "Interactive mode requires a terminal"

        info "Use 'scan' or 'diagnose' for non-interactive automation"


        lpd_audit \
            "ERROR" \
            "interactive" \
            "TTY_REQUIRED" \
            "stdin_tty=$([[ -t 0 ]] && printf 'yes' || printf 'no') stdout_tty=$([[ -t 1 ]] && printf 'yes' || printf 'no')"


        return 1
    fi


    return 0
}


#
# ------------------------------------------------------------
# HELP
# ------------------------------------------------------------
#

show_help() {

    cat <<EOF

$LPD_NAME

Usage:

  ./lpd.sh COMMAND [TARGET]


Commands:

  preflight

  scan

  diagnose [cpu|memory|disk|network|fd|all]

  interactive [cpu|memory|disk|network|fd|all]

  version

  help

EOF
}


#
# ------------------------------------------------------------
# ROUTER
# ------------------------------------------------------------
#

case "${1:-help}" in

    preflight)

        validate_modules || exit 3

        preflight_run

        exit $?
        ;;


    scan)

        validate_modules || exit 3

        scan_run

        exit $?
        ;;


    diagnose)

        validate_modules || exit 3


        case "${2:-}" in

            cpu)

                print_banner

                lpd_diagnose_run_one \
                    "cpu" \
                    "cpu_diagnose"

                exit $?
                ;;


            memory)

                print_banner

                lpd_diagnose_run_one \
                    "memory" \
                    "memory_diagnose"

                exit $?
                ;;


            disk)

                print_banner

                lpd_diagnose_run_one \
                    "disk" \
                    "disk_diagnose"

                exit $?
                ;;


            network)

                print_banner

                lpd_diagnose_run_one \
                    "network" \
                    "network_diagnose"

                exit $?
                ;;


            fd)

                print_banner

                lpd_diagnose_run_one \
                    "fd" \
                    "fd_diagnose"

                exit $?
                ;;


            all)

                print_banner

                diagnose_all_run

                exit $?
                ;;


            *)

                fail "Usage: ./lpd.sh diagnose [cpu|memory|disk|network|fd|all]"

                exit 3
                ;;

        esac
        ;;


    interactive)

        validate_modules || exit 3

        require_interactive_terminal || exit 3

        interactive_run "${2:-}"

        exit $?
        ;;


    version)

        echo "$LPD_VERSION"

        exit 0
        ;;


    help|-h|--help)

        show_help

        exit 0
        ;;


    *)

        fail "Unknown command: $1"

        show_help

        exit 2
        ;;

esac
