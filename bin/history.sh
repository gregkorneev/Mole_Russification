#!/bin/bash
# Mole - History command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/core/history.sh"

HISTORY_JSON=false
HISTORY_LIMIT="$MOLE_HISTORY_DEFAULT_LIMIT"

show_history_help() {
    printf '%s\n\n' "$(mole_t help_history_usage)"
    printf '%s\n\n' "$(mole_t help_history_description)"
    printf '%s\n' "$(mole_t help_options)"
    printf '%s\n' \
        "  --json           $(mole_t help_history_json)" \
        "  --limit N        $(mole_t help_history_limit)" \
        "  -h, --help       $(mole_t help_option_help)"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "--json")
                HISTORY_JSON=true
                ;;
            "--limit")
                shift
                if [[ $# -eq 0 ]]; then
                    printf '%s\n' "$(mole_t history_missing_limit)" >&2
                    exit 1
                fi
                if ! HISTORY_LIMIT=$(history_parse_limit "$1"); then
                    printf '%s\n' "$(mole_t history_invalid_limit "$1")" >&2
                    exit 1
                fi
                ;;
            "--help" | "-h")
                show_history_help
                exit 0
                ;;
            -*)
                printf '%s\n' "$(mole_t history_unknown_option "$1")" >&2
                printf '%s\n' "$(mole_t history_help_hint)" >&2
                exit 1
                ;;
            *)
                printf '%s\n' "$(mole_t history_unexpected_argument "$1")" >&2
                printf '%s\n' "$(mole_t history_help_hint)" >&2
                exit 1
                ;;
        esac
        shift
    done

    history_load_operations "$(history_operations_log_file)"
    history_load_deletions "$(history_deletions_log_file)"

    if [[ "$HISTORY_JSON" == "true" ]]; then
        history_render_json "$HISTORY_LIMIT"
    else
        history_render_text "$HISTORY_LIMIT"
    fi
}

main "$@"
