#!/bin/bash
# Mole - Status command.
# Runs the Go system status panel.
# Shows live system metrics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/status-go"
source "$SCRIPT_DIR/../lib/core/i18n.sh"
mole_i18n_init
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

printf '%s\n' "$(mole_t go_status_missing)" >&2
exit 1
