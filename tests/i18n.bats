#!/usr/bin/env bats

load helpers/common

setup() {
    mole_test_setup_project_root
    export NO_COLOR=1
}

@test "config help succeeds and an invalid preference path cannot report success" {
    local test_home="$BATS_TEST_TMPDIR/home"
    local preference="$test_home/.config/mole/language"
    mkdir -p "$preference"

    run env HOME="$test_home" MOLE_LANG=ru "$PROJECT_ROOT/mole" config --help
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"mo config language"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru "$PROJECT_ROOT/mole" config language ru
    [ "$status" -ne 0 ] || return 1
    [[ "$output" != *"Язык интерфейса сохранён"* ]] || return 1
    [ -z "$(ls -A "$preference")" ]
}

@test "Bash keeps English when the Russian catalog is absent or malformed" {
    local catalogs="$BATS_TEST_TMPDIR/catalogs"
    mkdir -p "$catalogs"
    printf 'test_greeting\tHello\n' > "$catalogs/en.tsv"
    local catalog_state language
    for catalog_state in missing malformed; do
        if [[ "$catalog_state" == "malformed" ]]; then
            printf 'test_greeting\tПривет\ninvalid\n' > "$catalogs/ru.tsv"
        fi
        for language in en ru; do
            run /bin/bash -euc 'source "$1"; MOLE_I18N_DIR="$2"; mole_i18n_activate_language "$3"; mole_t test_greeting' \
                _ "$PROJECT_ROOT/lib/core/i18n.sh" "$catalogs" "$language"
            [ "$status" -eq 0 ] || return 1
            [ "$output" = Hello ] || return 1
        done
    done
}

@test "language resolution prefers the environment, then saved preference, then macOS locale" {
    run /bin/bash -c 'source "$1"; printf "%s\n" \
        "$(_mole_i18n_resolve_language 1 ru en en_US)" \
        "$(_mole_i18n_resolve_language 0 "" ru en_US)" \
        "$(_mole_i18n_resolve_language 0 "" "" ru_RU.UTF-8)" \
        "$(_mole_i18n_resolve_language 0 "" "" fr_FR)" \
        "$(_mole_i18n_resolve_language 1 de ru ru_RU)"' _ "$PROJECT_ROOT/lib/core/i18n.sh"
    [ "$status" -eq 0 ]
    [ "$output" = $'ru\nru\nru\nen\nen' ]
}

@test "mo config language saves a setting and the next command uses it" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home"

    run env -u MOLE_LANG HOME="$test_home" MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" config language ru
    [ "$status" -eq 0 ]
    [[ "$output" == *"Язык интерфейса сохранён: русский"* ]] || return 1
    [ "$(cat "$test_home/.config/mole/language")" = "ru" ]
    [[ "$(cat "$test_home/Library/Logs/mole/operations.log")" == *"[config] REBUILT $test_home/.config/mole/language (language=ru)"* ]] || return 1

    run env -u MOLE_LANG HOME="$test_home" MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"КОМАНДЫ"* ]] || return 1
    [[ "$output" == *"mo config language"* ]] || return 1
}

@test "MOLE_LANG overrides the saved choice and unsupported languages use English" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home/.config/mole"
    printf 'en\n' > "$test_home/.config/mole/language"

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"КОМАНДЫ"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=fr_FR MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMANDS"* ]]
}

@test "language setting rejects unsupported values without replacing the saved choice" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home/.config/mole"
    printf 'en\n' > "$test_home/.config/mole/language"

    run env HOME="$test_home" MOLE_LANG=en MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" config language fr
    [ "$status" -eq 1 ]
    [[ "$output" == *'Choose "en" or "ru"'* ]] || return 1
    [ "$(cat "$test_home/.config/mole/language")" = "en" ]
}

@test "additional command help and history text honor the Russian locale" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home"

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" purge --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Использование: mo purge"* ]] || return 1
    [[ "$output" == *"Каталоги по умолчанию"* ]] || return 1
    [[ "$output" == *"--dry-run"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" slim --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Удалить код Intel"* ]] || return 1
    [[ "$output" == *"~/.config/mole/whitelist"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" update --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Обновить Mole до последней версии"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" remove --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Удалить Mole с этого Mac"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" completion --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Настроить автодополнение команд mole и mo"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" completion fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"Предварительный просмотр без изменений"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" completion zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"--dry-run[Предварительный просмотр без изменений]"* ]] || return 1
    [[ "$output" == *"--whitelist[Настроить защищённые пути]"* ]] || return 1

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" history
    [ "$status" -eq 0 ]
    [[ "$output" == *"История Mole"* ]] || return 1
    [[ "$output" == *"История операций пока пуста"* ]]
}

@test "whitelist refusal messages are localized and keep the repair command" {
    local test_home="$BATS_TEST_TMPDIR/whitelist-home"
    mkdir -p "$test_home"
    # shellcheck disable=SC2016 # The child shell initializes the selected locale.
    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        /bin/bash -c 'source "$1/lib/core/common.sh"; mole_report_unreadable_whitelist "$2" "whitelist" "directory"' \
        _ "$PROJECT_ROOT" "$test_home/.config/mole"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Не удаётся открыть каталог whitelist"* ]] || return 1
    [[ "$output" == *"Очистка остановлена"* ]] || return 1
    [[ "$output" == *"chmod u+rx"* ]]
}

@test "display translations keep the logged message in English" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home"

    # shellcheck disable=SC2016 # The child Bash program expands its positional paths.
    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        /bin/bash -c 'source "$1/lib/core/common.sh"; log_success "System caches"; log_error "Uninstall aborted: protected path"; cat "$HOME/Library/Logs/mole/mole.log"' \
        _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Системные кеши"* ]] || return 1
    [[ "$output" == *"SUCCESS: System caches"* ]] || return 1
    [[ "$output" == *"Удаление приложений отменено: protected path"* ]] || return 1
    [[ "$output" == *"ERROR: Uninstall aborted: protected path"* ]]
}

@test "summary rows translate behind their icon and one-word phrases are text, not keys" {
    local test_home="$BATS_TEST_TMPDIR/home" language
    mkdir -p "$test_home"

    for language in ru en; do
        # shellcheck disable=SC2016 # The child Bash program expands its own variables.
        run env HOME="$test_home" MOLE_LANG="$language" MOLE_TEST_NO_AUTH=1 NO_COLOR=1 \
            /bin/bash -c 'set -euo pipefail; source "$1/lib/core/common.sh"
print_summary_block "Slim incomplete" \
    "${ICON_REVIEW} Still running during uninstall, files removed but process kept alive: Example" \
    "${ICON_WARNING} 3 more failed" \
    "${ICON_LIST} $(mole_t ui_uninstall_failed_summary Example "$(mole_display_text "is still running")")" \
    "${ICON_LIST} no catalog entry for this row"
mole_review_row "Docker Desktop data" "" "1GB" "macOS removes them when space runs low"
printf "%s|%s|%s\n" "$(mole_display_text whitelisted)" "$(mole_display_text "permission denied")" "$(mole_t no_such_key)"' \
            _ "$PROJECT_ROOT"
        [ "$status" -eq 0 ] || return 1
        [[ "$output" == *"• no catalog entry for this row"* ]] || return 1
        if [[ "$language" == "ru" ]]; then
            [[ "$output" == *"Удаление кода Intel завершено не полностью"* ]] || return 1
            [[ "$output" == *"⊙ Продолжают работать после удаления (процесс остался активным): Example"* ]] || return 1
            [[ "$output" == *"◎ Ещё ошибок: 3"* ]] || return 1
            [[ "$output" == *"• Сбой: Example — приложение запущено"* ]] || return 1
            [[ "$output" == *"⊙ Данные Docker Desktop · 1GB · macOS удаляет их при нехватке места"* ]] || return 1
            [[ "$output" == *"в списке исключений|нет прав доступа|no_such_key"* ]] || return 1
        else
            [[ "$output" == *"Slim incomplete"* ]] || return 1
            [[ "$output" == *"⊙ Still running during uninstall, files removed but process kept alive: Example"* ]] || return 1
            [[ "$output" == *"◎ 3 more failed"* ]] || return 1
            [[ "$output" == *"• Failed: Example is still running"* ]] || return 1
            [[ "$output" == *"⊙ Docker Desktop data · 1GB · macOS removes them when space runs low"* ]] || return 1
            [[ "$output" == *"whitelisted|permission denied|no_such_key"* ]] || return 1
        fi
    done
}

@test "spinner and optimization messages use display-only translations" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home"

    # shellcheck disable=SC2016 # The child Bash program expands its positional paths.
    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        /bin/bash -c 'source "$1/lib/core/common.sh"; source "$1/lib/optimize/tasks.sh"; format_spinner_message "Scanning installed apps..."; printf "\n"; format_spinner_message "[2/4] Uninstalling Example.app..."; printf "\n"; opt_msg "DNS cache refreshed"' \
        _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Сканирование установленных приложений..."* ]] || return 1
    [[ "$output" == *"[2/4] Удаление приложения Example.app..."* ]] || return 1
    [[ "$output" == *"Кеш DNS обновлён"* ]]
}

@test "operational status labels and update guidance have Russian translations" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home"

    # shellcheck disable=SC2016 # The child Bash program initializes the selected locale.
    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 MO_DEBUG=1 \
        /bin/bash -c 'source "$1/lib/core/common.sh"; printf "%s\n" "$(mole_t update_whats_new 1.2.3)" "$(mole_t update_success_detail nightly abc123)" "$(mole_t update_manual_reinstall main /opt/mole ~/.config/mole)"; mole_join_names Alpha Beta Gamma Delta Echo; debug_risk_level HIGH "sample pressure"' \
        _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Что нового в версии 1.2.3"* ]] || return 1
    [[ "$output" == *"Обновлено: nightly, abc123"* ]] || return 1
    [[ "$output" == *"Переустановите вручную: curl -fsSL"* ]] || return 1
    [[ "$output" == *"и ещё: 2"* ]] || return 1
    [[ "$output" == *"Уровень риска: HIGH"* ]]
}

@test "history JSON is identical in Russian and English" {
    local test_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$test_home"

    run env HOME="$test_home" MOLE_LANG=en MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" history --json
    [ "$status" -eq 0 ]
    local english_json="$output"

    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" history --json
    [ "$status" -eq 0 ]
    [ "$output" = "$english_json" ]
}

@test "invalid command options have Russian diagnostics" {
    local command
    for command in clean purge slim optimize; do
        run env HOME="$BATS_TEST_TMPDIR" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
            "$PROJECT_ROOT/mole" "$command" --invalid-option
        [ "$status" -eq 1 ] || return 1
        [[ "$output" == *"Неизвестный параметр"* ]] || return 1
        [[ "$output" == *"mo $command --help"* ]] || return 1
    done
}

@test "slim summary translates failure reasons while keeping grouping" {
    # shellcheck disable=SC2016 # The child Bash program expands its own variables.
    run env HOME="$BATS_TEST_TMPDIR" MOLE_LANG=ru MOLE_TEST_MODE=1 MOLE_TEST_NO_AUTH=1 \
        /bin/bash -c 'source "$1/bin/slim.sh"; SLIM_FAILED_NAMES=(Alpha Beta); SLIM_FAILED_REASONS=("still running" "still running"); total_failed=2; show_slim_summary' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"приложение запущено: Alpha, Beta"* ]] || return 1
}

@test "Trash dry-run reports Russian text and retains its item" {
    local test_home="$BATS_TEST_TMPDIR/trash-home"
    mkdir -p "$test_home/.Trash"
    : > "$test_home/.Trash/example"
    # shellcheck disable=SC2016 # The child Bash program expands its own paths.
    run env HOME="$test_home" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        /bin/bash -c 'source "$1/lib/core/common.sh"; source "$1/lib/clean/user.sh"; DRY_RUN=true; clean_trash' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Корзина · будет очищена, объектов: 1"* ]] || return 1
    [ -f "$test_home/.Trash/example" ]
}


@test "update notice is localized for display while the cached text stays English" {
    # shellcheck disable=SC2016 # The child Bash program expands its own variables.
    run env HOME="$BATS_TEST_TMPDIR" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        /bin/bash -c 'source "$1/lib/core/common.sh"
eval "$(sed -n "/^_main_menu_update_notice()/,/^}$/p" "$1/mole")"
_main_menu_update_notice "Update 9.8.7 available, run mo update"
_main_menu_update_notice "New nightly commit abc1234 available, run mo update --nightly"
MOLE_LANG=en _main_menu_update_notice "Update 9.8.7 available, run mo update"' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Доступно обновление 9.8.7, выполните mo update"* ]] || return 1
    [[ "$output" == *"Доступен новый ночной коммит abc1234, выполните mo update --nightly"* ]] || return 1
    [[ "$output" == *"Update 9.8.7 available, run mo update"* ]] || return 1
}

@test "external volume refusals are localized and still exit nonzero" {
    run env HOME="$BATS_TEST_TMPDIR" MOLE_LANG=ru MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" clean --external relative/path
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"Путь к внешнему тому должен быть абсолютным: relative/path"* ]] || return 1

    run env HOME="$BATS_TEST_TMPDIR" MOLE_LANG=en MOLE_TEST_NO_AUTH=1 \
        "$PROJECT_ROOT/mole" clean --external relative/path
    [ "$status" -ne 0 ] || return 1
    [[ "$output" == *"External volume path must be absolute: relative/path"* ]] || return 1
}
