#!/bin/bash
# Mole - Analyze command.
# Runs the Go disk analyzer UI.
# Uses bundled analyze-go binary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/analyze-go"
source "$SCRIPT_DIR/../lib/core/i18n.sh"
mole_i18n_init
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

printf '%s\n' "$(mole_t go_analyze_missing)" >&2
exit 1
