#!/bin/bash

# Shared Bash localization loader. The same TSV catalogs are read by Go.
if [[ -n "${MOLE_I18N_HELPER_LOADED:-}" ]]; then
    return 0
fi
MOLE_I18N_HELPER_LOADED=1
MOLE_I18N_KEYS=()
MOLE_I18N_TEMPLATE_KEYS=()

_MOLE_I18N_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../i18n" && pwd)"
MOLE_I18N_DIR="$_MOLE_I18N_DIR"
export MOLE_I18N_DIR

_mole_i18n_normalize_language() {
    case "$1" in
        [Rr][Uu] | [Rr][Uu]_* | [Rr][Uu]-*) printf 'ru\n' ;;
        [Ee][Nn] | [Ee][Nn]_* | [Ee][Nn]-*) printf 'en\n' ;;
        *) printf 'en\n' ;;
    esac
}

_mole_i18n_resolve_language() {
    local override_is_set="$1"
    local override="$2"
    local saved="$3"
    local system_locale="$4"
    if [[ "$override_is_set" == "1" ]]; then
        _mole_i18n_normalize_language "$override"
    elif [[ -n "$saved" ]]; then
        _mole_i18n_normalize_language "$saved"
    else
        _mole_i18n_normalize_language "$system_locale"
    fi
}

_mole_i18n_system_locale() {
    local locale=""
    if [[ -x /usr/bin/defaults ]]; then
        locale=$(/usr/bin/defaults read -g AppleLocale 2> /dev/null || true)
    fi
    if [[ -z "$locale" ]]; then
        locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    fi
    printf '%s' "$locale"
}

_mole_i18n_load_catalog() {
    local language="$1"
    local file="${MOLE_I18N_DIR}/${language}.tsv"
    local key value variable
    [[ -r "$file" ]] || return 1

    while IFS=$'\t' read -r key value || [[ -n "${key:-}" ]]; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        [[ "$key" =~ ^[a-z][a-z0-9_]*$ && -n "$value" ]] || return 1
        variable="MOLE_I18N_${language}_${key}"
        printf -v "$variable" '%s' "$value"
        if [[ "$language" == "en" ]]; then
            MOLE_I18N_KEYS+=("$key")
            if [[ "$value" == *%s* || "$value" == *%d* ]]; then
                MOLE_I18N_TEMPLATE_KEYS+=("$key")
            fi
        fi
    done < "$file"
}

mole_i18n_activate_language() {
    MOLE_LANG="$(_mole_i18n_normalize_language "$1")"
    export MOLE_LANG
    MOLE_I18N_KEYS=()
    MOLE_I18N_TEMPLATE_KEYS=()
    _mole_i18n_load_catalog en || return 1
    _mole_i18n_load_catalog ru || return 1
}

mole_i18n_init() {
    [[ -n "${MOLE_I18N_INITIALIZED:-}" ]] && return 0

    local override_is_set=0 override="" saved="" system_locale=""
    [[ "${MOLE_LANG+x}" == x ]] && override_is_set=1 && override="$MOLE_LANG"
    [[ "$override_is_set" == "1" ]] && MOLE_I18N_ENV_OVERRIDE=1 || MOLE_I18N_ENV_OVERRIDE=0
    if [[ "$override_is_set" != "1" && -r "${HOME:-}/.config/mole/language" ]]; then
        IFS= read -r saved < "${HOME}/.config/mole/language" || true
    fi
    if [[ "$override_is_set" != "1" && -z "$saved" ]]; then
        system_locale="$(_mole_i18n_system_locale)"
    fi

    MOLE_I18N_INITIALIZED=1
    # Catalog values are shell variables and are intentionally process-local.
    # Do not export the initialized marker: command dispatch starts child
    # shells that must load the same catalogs for themselves.
    export MOLE_I18N_ENV_OVERRIDE
    mole_i18n_activate_language "$(_mole_i18n_resolve_language "$override_is_set" "$override" "$saved" "$system_locale")"
}

_mole_i18n_build_template_regex() {
    local LC_ALL=C
    local template="$1" index=0 char remainder directive literal_count=0
    MOLE_I18N_TEMPLATE_REGEX=""
    MOLE_I18N_TEMPLATE_ARG_COUNT=0

    while [[ "$index" -lt "${#template}" ]]; do
        char="${template:index:1}"
        if [[ "$char" == "%" ]]; then
            remainder="${template:index}"
            if [[ "$remainder" =~ ^%[sd] ]]; then
                directive="${BASH_REMATCH[0]}"
                MOLE_I18N_TEMPLATE_REGEX+="(.*)"
                MOLE_I18N_TEMPLATE_ARG_COUNT=$((MOLE_I18N_TEMPLATE_ARG_COUNT + 1))
                index=$((index + ${#directive}))
                continue
            fi
        fi

        if [[ "$char" == "\\" ]]; then
            MOLE_I18N_TEMPLATE_REGEX+="\\\\"
        else
            case "$char" in
                '.' | '[' | ']' | '(' | ')' | '{' | '}' | '*' | '+' | '?' | '$' | '^' | '|')
                    MOLE_I18N_TEMPLATE_REGEX+="\\$char"
                    ;;
                *) MOLE_I18N_TEMPLATE_REGEX+="$char" ;;
            esac
        fi
        literal_count=$((literal_count + 1))
        index=$((index + 1))
    done

    # Anchoring the full pattern plus eight literal characters keeps short
    # formatted values from matching unrelated terminal messages. This also
    # allows indexed progress text such as "[2/4] Uninstalling ...".
    [[ "$MOLE_I18N_TEMPLATE_ARG_COUNT" -gt 0 && "$literal_count" -ge 8 ]]
}

mole_t() {
    local key="${1:-}" variable value=""
    shift || true

    if [[ "$key" =~ ^[a-z][a-z0-9_]*$ ]]; then
        variable="MOLE_I18N_${MOLE_LANG:-en}_${key}"
        value="${!variable:-}"
        if [[ -z "$value" ]]; then
            variable="MOLE_I18N_en_${key}"
            value="${!variable:-$key}"
        fi
    else
        # Display helpers translate exact English phrases without changing
        # the English strings recorded in logs or machine-readable data.
        if [[ "${MOLE_LANG:-en}" != "ru" ]]; then
            printf '%s' "$key"
            return 0
        fi
        local phrase_key english_value candidate_value matched_phrase
        matched_phrase=0
        for phrase_key in "${MOLE_I18N_KEYS[@]}"; do
            variable="MOLE_I18N_en_${phrase_key}"
            english_value="${!variable:-}"
            [[ "$english_value" == "$key" ]] || continue
            variable="MOLE_I18N_${MOLE_LANG:-en}_${phrase_key}"
            candidate_value="${!variable:-$english_value}"
            if [[ "$matched_phrase" == "0" ]]; then
                value="$candidate_value"
                matched_phrase=1
            elif [[ "$candidate_value" != "$value" ]]; then
                # Identical English labels can need different translations in
                # different contexts. Leave an ambiguous raw phrase intact.
                matched_phrase=2
                break
            fi
        done
        if [[ "$matched_phrase" == "0" && "${MOLE_LANG:-en}" == "ru" ]]; then
            local template_key localized_template
            for template_key in "${MOLE_I18N_TEMPLATE_KEYS[@]}"; do
                variable="MOLE_I18N_en_${template_key}"
                english_value="${!variable:-}"
                _mole_i18n_build_template_regex "$english_value" || continue
                if [[ "$key" =~ ^${MOLE_I18N_TEMPLATE_REGEX}$ ]]; then
                    variable="MOLE_I18N_ru_${template_key}"
                    localized_template="${!variable:-$english_value}"
                    # shellcheck disable=SC2059 # Catalog format strings own their matching placeholders.
                    printf "$localized_template" "${BASH_REMATCH[@]:1}"
                    return 0
                fi
            done
        fi
        [[ "$matched_phrase" == "1" ]] || value="$key"
    fi

    if [[ $# -gt 0 ]]; then
        # shellcheck disable=SC2059 # Catalog format strings own their matching placeholders.
        printf "$value" "$@"
    else
        printf '%s' "$value"
    fi
}

# Display a count without using translated text as program state.
mole_t_items() {
    if [[ "$1" == "1" ]]; then
        mole_t clean_items_one "$1"
    else
        mole_t clean_items_many "$1"
    fi
}
