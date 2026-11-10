#!/bin/bash

mole_config_language_name() {
    case "$1" in
        ru) mole_t language_russian ;;
        *) mole_t language_english ;;
    esac
}

mole_config_command() {
    if [[ "${1:-}" != "language" ]]; then
        printf '%s\n' "$(mole_t config_usage)" >&2
        return 1
    fi

    shift
    if [[ "${1:-}" == "--help" || $# -eq 0 ]]; then
        printf '%s\n' "$(mole_t config_usage)" "$(mole_t help_options)" \
            "  en                $(mole_t help_config_language)" \
            "  ru                $(mole_t help_config_language)" \
            "  -h, --help        $(mole_t help_option_help)"
        return 0
    fi

    local target="${1:-}"
    if [[ $# -ne 1 || ("$target" != "en" && "$target" != "ru") ]]; then
        printf '%s\n' "$(mole_t config_invalid_language "$target")" "$(mole_t config_usage)" >&2
        return 1
    fi

    local config_home="${HOME:-}"
    if [[ -z "$config_home" ]]; then
        # shellcheck disable=SC2088 # Show the conventional home-relative path literally.
        printf '%s\n' "$(mole_t config_write_failed "~/.config/mole/language")" >&2
        return 1
    fi
    local config_dir="$config_home/.config/mole"
    local config_file="$config_dir/language"
    local temp_file=""
    if ! mkdir -p "$config_dir"; then
        printf '%s\n' "$(mole_t config_write_failed "$config_file")" >&2
        return 1
    fi
    temp_file="$(mktemp "$config_dir/.language.XXXXXX")" || {
        printf '%s\n' "$(mole_t config_write_failed "$config_file")" >&2
        return 1
    }
    if ! printf '%s\n' "$target" > "$temp_file" || ! mv -f "$temp_file" "$config_file"; then
        rm -f "$temp_file" # SAFE: own mktemp scratch file
        printf '%s\n' "$(mole_t config_write_failed "$config_file")" >&2
        return 1
    fi

    log_operation config REBUILT "$config_file" "language=$target"
    if [[ "${MOLE_I18N_ENV_OVERRIDE:-0}" != "1" ]]; then
        mole_i18n_activate_language "$target"
    fi
    printf '%s\n' "$(mole_t config_saved "$(mole_config_language_name "$target")")"
}
