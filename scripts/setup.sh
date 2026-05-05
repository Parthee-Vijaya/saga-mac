#!/usr/bin/env bash
# Saga setup-script — installer Xcode-toolchain + generér Xcode-projekt.
# Canary-modellerne kommer enten bundlet (full DMG) eller downloades ved
# første start (slim DMG) — ingen manuel model-håndtering nødvendig her.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${PROJECT_ROOT}/saga-app"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "  → %s\n" "$*"; }
warn() { printf "  ⚠ %s\n" "$*" 1>&2; }
ok() { printf "  ✓ %s\n" "$*"; }

bold "Saga setup"
echo

# 1. Tjek tools
bold "[1/3] Tjekker tools"

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

# 2. Generér Xcode-projekt
echo
bold "[2/3] Genererer Xcode-projekt"
cd "${APP_DIR}"
xcodegen generate
ok "SagaApp.xcodeproj genereret"

# 3. LM Studio (optional)
echo
bold "[3/3] LM Studio (optional — kun for Modes + Companion)"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:1234/v1/models 2>/dev/null | grep -q "200"; then
  ok "LM Studio kører på localhost:1234"
else
  info "LM Studio svarer ikke på localhost:1234."
  info "Saga virker fint uden — kun Modes (oversæt/format/...) og Companion kræver det."
  info "Hvis du vil bruge dem: start LM Studio og load fx gemma-4-26b."
fi

echo
bold "✓ Saga setup færdig"
echo
cat <<'EOF'

Næste skridt:
  1. cd saga-app && open SagaApp.xcodeproj           # Åbn i Xcode
  2. Cmd+R i Xcode for at bygge og køre
  3. Granté Mikrofon + Accessibility første gang Saga starter
  4. Hold ⌥ Højre Option og tal — teksten indsættes ved cursor

EOF
