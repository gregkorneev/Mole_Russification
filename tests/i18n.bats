#!/usr/bin/env bats

load helpers/common

setup() {
    mole_test_setup_project_root
    export NO_COLOR=1
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

