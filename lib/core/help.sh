#!/bin/bash

show_clean_help() {
    printf '%s\n\n' "$(mole_t help_usage 'clean [OPTIONS]')"
    printf '%s\n\n' "$(mole_t help_clean_description)"
    printf '%s\n' "$(mole_t help_options)"
    printf '%s\n' \
        "  --dry-run, -n     $(mole_t help_option_dry_run)" \
        "  --external PATH   $(mole_t help_option_external)" \
        "  --whitelist       $(mole_t help_option_whitelist_paths)" \
        "  --debug           $(mole_t help_option_debug)" \
        "  -h, --help        $(mole_t help_option_help)"
}

show_installer_help() {
    printf '%s\n\n' "$(mole_t help_usage 'installer [OPTIONS]')"
    printf '%s\n\n' "$(mole_t help_installer_description)"
    printf '%s\n' "$(mole_t help_options)"
    printf '%s\n' \
        "  --dry-run         $(mole_t help_option_dry_run_installer)" \
        "  --debug           $(mole_t help_option_debug)" \
        "  -h, --help        $(mole_t help_option_help)"
}

show_optimize_help() {
    printf '%s\n\n' "$(mole_t help_usage 'optimize [OPTIONS]')"
    printf '%s\n\n' "$(mole_t help_optimize_description)"
    printf '%s\n' "$(mole_t help_options)"
    printf '%s\n' \
        "  --dry-run, -n     $(mole_t help_option_dry_run_optimize)" \
        "  --whitelist       $(mole_t help_option_whitelist_items)" \
        "  --debug           $(mole_t help_option_debug)" \
        "  -h, --help        $(mole_t help_option_help)"
}

show_touchid_help() {
    printf '%s\n\n' "$(mole_t help_usage 'touchid [COMMAND]')"
    printf '%s\n\n' "$(mole_t help_touchid_description)"
    printf '%s\n' "$(mole_t help_commands)"
    printf '%s\n' \
        "  enable            $(mole_t help_touchid_enable)" \
        "  disable           $(mole_t help_touchid_disable)" \
        "  status            $(mole_t help_touchid_status)"
    printf '\n%s\n' "$(mole_t help_options)"
    printf '%s\n' \
        "  --dry-run         $(mole_t help_option_dry_run_touchid)" \
        "  -h, --help        $(mole_t help_option_help)"
    printf '\n%s\n' "$(mole_t help_touchid_interactive)"
}

show_uninstall_help() {
    printf '%s\n\n' "$(mole_t help_usage 'uninstall [OPTIONS] [APP_NAME ...]')"
    printf '%s\n' \
        "$(mole_t help_uninstall_description)" \
        "$(mole_t help_uninstall_names)" \
        "$(mole_t help_uninstall_leftovers)"
    printf '\n%s\n' "$(mole_t help_examples)"
    printf '%s\n' \
        "  mo uninstall                   $(mole_t help_uninstall_example_selector)" \
        "  mo uninstall slack             $(mole_t help_uninstall_slack)" \
        "  mo uninstall slack zoom        $(mole_t help_uninstall_slack_zoom)" \
        "  mo uninstall --dry-run slack   $(mole_t help_uninstall_preview_slack)" \
        "  mo uninstall --with-data slack $(mole_t help_uninstall_with_data_slack)" \
        "  mo uninstall --list            $(mole_t help_uninstall_list_names)"
    printf '\n%s\n' "$(mole_t help_options)"
    printf '%s\n' \
        "  --list            $(mole_t help_option_list)" \
        "  --dry-run         $(mole_t help_option_dry_run_uninstall)" \
        "  --permanent       $(mole_t help_option_permanent)" \
        "  --with-data       $(mole_t help_option_with_data)" \
        "  --whitelist       $(mole_t help_option_uninstall_whitelist)" \
        "  --debug           $(mole_t help_option_debug)" \
        "  -h, --help        $(mole_t help_option_help)"
    printf '\n%s\n%s\n' "$(mole_t help_uninstall_recover)" "$(mole_t help_uninstall_recover_continued)"
}
