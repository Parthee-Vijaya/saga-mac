#!/usr/bin/env bash
# Saga setup-script — installer Python-deps + sætter Xcode-toolchain.
# Henter IKKE Hviske-modellen; kør `uv run saga-download` separat (4-8 GB).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SIDECAR_DIR="${PROJECT_ROOT}/saga-sidecar"
APP_DIR="${PROJECT_ROOT}/saga-app"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "  → %s\n" "$*"; }
warn() { printf "  ⚠ %s\n" "$*" 1>&2; }
ok() { printf "  ✓ %s\n" "$*"; }

bold "Saga setup"
echo

# 1. Tjek tools
bold "[1/5] Tjekker tools"

if ! command -v uv >/dev/null 2>&1; then
  warn "uv mangler. Installer via: curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi
ok "uv $(uv --version)"

if ! command -v xcodegen >/dev/null 2>&1; then
  warn "xcodegen mangler. Installer via: brew install xcodegen"
  exit 1
fi
ok "xcodegen $(xcodegen --version 2>&1 | head -1)"

if [[ ! -d "/Applications/Xcode.app" ]]; then
  warn "Xcode.app ikke fundet i /Applications. Installer fra App Store før du kører appen."
else
  ok "Xcode.app fundet"
fi

CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null || echo '')"
if [[ "${CURRENT_DEV_DIR}" != *"Xcode.app"* ]]; then
  warn "xcode-select peger på '${CURRENT_DEV_DIR}'."
  warn "Kør senere: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

# 2. Sync Python sidecar
echo
bold "[2/5] Installerer Python-sidecar dependencies (uv sync)"
cd "${SIDECAR_DIR}"
uv sync
ok "Sidecar venv klar i ${SIDECAR_DIR}/.venv"

# 3. Generér Xcode-projekt
echo
bold "[3/5] Genererer Xcode-projekt"
cd "${APP_DIR}"
xcodegen generate
ok "SagaApp.xcodeproj genereret"

# 4. Hint om Hviske-download
echo
bold "[4/5] Hviske-model"
HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--syvai--hviske-v5.3"
if [[ -d "${HF_CACHE}" ]]; then
  ok "Hviske-modellen er allerede cached i ${HF_CACHE}"
else
  info "Hviske-modellen er IKKE downloaded endnu (4-8 GB)."
  info "Kør: cd saga-sidecar && uv run saga-download"
fi

# 5. Hint om LM Studio
echo
bold "[5/5] LM Studio"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:1234/v1/models 2>/dev/null | grep -q "200"; then
  ok "LM Studio kører på localhost:1234"
else
  info "LM Studio svarer ikke på localhost:1234."
  info "Start LM Studio og load gemma-4-26b (eller en anden model — sæt i Settings)."
fi

echo
bold "✓ Saga setup færdig"
echo
cat <<'EOF'

Næste skridt:
  1. cd saga-sidecar && uv run saga-download         # Hent Hviske-modellen (4-8 GB)
  2. cd saga-app && open SagaApp.xcodeproj           # Åbn i Xcode
  3. Cmd+R i Xcode for at bygge og køre
  4. Granté Mikrofon + Accessibility første gang Saga starter
  5. Hold Fn og tal — teksten indsættes ved cursor

EOF
