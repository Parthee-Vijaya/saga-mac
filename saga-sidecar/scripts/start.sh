#!/usr/bin/env bash
set -euo pipefail

# Start Saga sidecar. Bruges af Saga.app via Process(), eller manuelt.
#
# Args:
#   $1 — port (optional, default 7861)
#   $2 — device (optional, default auto)

cd "$(dirname "$0")/.."

PORT="${1:-${SAGA_PORT:-7861}}"
DEVICE="${2:-${SAGA_DEVICE:-auto}}"

exec uv run saga-sidecar --port "$PORT" --device "$DEVICE"
