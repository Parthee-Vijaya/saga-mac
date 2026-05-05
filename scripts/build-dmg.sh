#!/usr/bin/env bash
# Bygger Saga.app i Release-config, bundler Canary mlpackage-filer ind,
# re-signer, og pakker det hele som .dmg klar til distribution.
#
# Output: dist/Saga-X.Y.Z.dmg
#
# Krav:
#   - Xcode (xcodebuild)
#   - xcodegen (brew install xcodegen)
#   - canary-coreml/models/mlpackage/ skal eksistere ved siden af saga/
#   - hdiutil (macOS standard)
#   - codesign (macOS standard) — bruger Apple Development cert hvis tilgængelig

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${PROJECT_ROOT}/saga-app"
DIST_DIR="${PROJECT_ROOT}/dist"
BUILD_DIR="${DIST_DIR}/build"
DMG_TMP="${DIST_DIR}/dmg-staging"

# Find canary-coreml. Default: søsterprojekt på samme niveau.
CANARY_DIR="${SAGA_CANARY_DIR:-${PROJECT_ROOT}/../canary-coreml}"
MLPACKAGE_DIR="${CANARY_DIR}/models/mlpackage"

# Hent version fra project.yml (MARKETING_VERSION)
VERSION=$(grep -oE 'MARKETING_VERSION:\s*"[^"]+"' "${APP_DIR}/project.yml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
VERSION="${VERSION:-0.1.0}"

DMG_NAME="Saga-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
VOLUME_NAME="Saga ${VERSION}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "  → %s\n" "$*"; }
warn() { printf "  ⚠ %s\n" "$*" 1>&2; }
ok() { printf "  ✓ %s\n" "$*"; }
fail() { printf "  ✗ %s\n" "$*" 1>&2; exit 1; }

bold "Saga DMG-build"
echo "  Version: ${VERSION}"
echo "  Output:  ${DMG_PATH}"
echo

# Pre-flight
bold "[1/8] Pre-flight"
[[ -d "/Applications/Xcode.app" ]] || fail "Xcode.app mangler i /Applications. Installer fra App Store."
command -v xcodegen >/dev/null || fail "xcodegen mangler. Kør: brew install xcodegen"
[[ -d "${MLPACKAGE_DIR}" ]] || fail "mlpackage mangler: ${MLPACKAGE_DIR}. Kør canary-coreml/python pipelinen."
ok "Xcode, xcodegen, mlpackage OK"

# Generate xcodeproj
bold "[2/8] Generér Xcode-projekt"
cd "${APP_DIR}"
xcodegen generate >/dev/null
ok "SagaApp.xcodeproj"

# Build Release
bold "[3/8] xcodebuild Release"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "${APP_DIR}/SagaApp.xcodeproj" \
  -scheme Saga \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "${BUILD_DIR}" \
  -quiet \
  build
APP_BUILT="${BUILD_DIR}/Build/Products/Release/Saga.app"
[[ -d "${APP_BUILT}" ]] || fail "Saga.app blev ikke bygget"
ok "Bygget: ${APP_BUILT}"

# Bundle mlpackages
bold "[4/8] Bundle Canary mlpackages → Saga.app/Contents/Resources/mlpackage/"
BUNDLE_DEST="${APP_BUILT}/Contents/Resources/mlpackage"
mkdir -p "${BUNDLE_DEST}"
for pkg in CanaryEncoder.mlpackage CanaryDecoderLM.mlpackage CanaryPreprocessor.mlpackage; do
  src="${MLPACKAGE_DIR}/${pkg}"
  if [[ -d "${src}" ]]; then
    cp -R "${src}" "${BUNDLE_DEST}/"
    info "${pkg} ($(du -sh "${src}" | cut -f1))"
  else
    warn "${pkg} mangler i ${MLPACKAGE_DIR}"
  fi
done
APP_SIZE=$(du -sh "${APP_BUILT}" | cut -f1)
ok "Total Saga.app: ${APP_SIZE}"

# Re-sign app (vi har modificeret indhold)
bold "[5/8] Re-sign Saga.app"
SIGN_IDENTITY="${SAGA_SIGN_IDENTITY:-9E6001BC0D64B78FD7E2A7B2BA6279A222A4EB5F}"
if security find-identity -v -p codesigning 2>&1 | grep -q "${SIGN_IDENTITY}"; then
  codesign --force --deep --sign "${SIGN_IDENTITY}" \
    --options runtime \
    --entitlements "${APP_DIR}/Resources/Saga.entitlements" \
    "${APP_BUILT}" 2>&1 | tail -3
  ok "Signed med Apple Development identity"
else
  warn "Identity '${SIGN_IDENTITY}' ikke fundet — ad-hoc signing"
  codesign --force --deep --sign - "${APP_BUILT}" 2>&1 | tail -3
fi

# Verify signing
codesign -dv --verbose=2 "${APP_BUILT}" 2>&1 | grep -E "Authority|Signature|Identifier" | head -5

# Optional: notarize the app before staging the DMG.
# Set SAGA_NOTARIZE=1 along with the three credentials below to opt in.
# Skipped silently otherwise so local development builds keep working.
if [[ "${SAGA_NOTARIZE:-0}" == "1" ]]; then
  bold "[5b/8] Notarisering af Saga.app"
  : "${SAGA_NOTARY_APPLE_ID:?SAGA_NOTARY_APPLE_ID skal sættes når SAGA_NOTARIZE=1}"
  : "${SAGA_NOTARY_TEAM_ID:?SAGA_NOTARY_TEAM_ID skal sættes når SAGA_NOTARIZE=1}"
  : "${SAGA_NOTARY_PASSWORD:?SAGA_NOTARY_PASSWORD skal sættes når SAGA_NOTARIZE=1}"

  NOTARY_ZIP="${BUILD_DIR}/Saga-notarize.zip"
  rm -f "${NOTARY_ZIP}"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_BUILT}" "${NOTARY_ZIP}"
  info "Zip klar til upload ($(du -sh "${NOTARY_ZIP}" | cut -f1))"

  xcrun notarytool submit "${NOTARY_ZIP}" \
    --apple-id "${SAGA_NOTARY_APPLE_ID}" \
    --team-id "${SAGA_NOTARY_TEAM_ID}" \
    --password "${SAGA_NOTARY_PASSWORD}" \
    --wait \
    --timeout 30m \
    || fail "notarytool submit fejlede — tjek log via: xcrun notarytool log <submission-id>"

  xcrun stapler staple "${APP_BUILT}" || fail "stapler staple fejlede"
  xcrun stapler validate "${APP_BUILT}" >/dev/null || fail "stapler validate fejlede"
  rm -f "${NOTARY_ZIP}"
  ok "Notariseret + stapled"
else
  warn "Springer notarisering over (sæt SAGA_NOTARIZE=1 for distribution)"
fi

# Stage DMG content
bold "[6/8] Stage DMG-content"
rm -rf "${DMG_TMP}"
mkdir -p "${DMG_TMP}"
cp -R "${APP_BUILT}" "${DMG_TMP}/"
ln -s /Applications "${DMG_TMP}/Applications"
cat > "${DMG_TMP}/Læs mig.txt" <<EOF
Saga ${VERSION}
═══════════════════════════════════════════

Mac-native voice assistant til dansk dictation.
Hold Højre Option, tal dansk, slip → tekst indsættes ved cursor.

Installation
────────────
1. Træk Saga.app over i Applications-mappen
2. Åbn Saga fra Spotlight (Cmd+Space → "Saga")
3. Første gang macOS spørger: tillad mikrofon + accessibility
4. Klik status-bar-ikonet (waveform-cirkel) for indstillinger

Krav
────
• Apple Silicon Mac (M1+)
• macOS 15.0 eller nyere
• 16+ GB RAM (24+ anbefalet)
• Optionelt: LM Studio (lmstudio.ai) for mode-routing

Hvis Saga ikke vil åbne ("kunne ikke verificeres")
─────────────────────────────────────────────────
1. Højre-klik Saga.app i Finder
2. Vælg "Åbn"
3. Klik "Åbn" i sikkerheds-dialogen
4. Saga åbner herefter normalt fra Spotlight

Mere
────
GitHub: https://github.com/Parthee-Vijaya/saga-mac
EOF
ok "Stagedet → ${DMG_TMP}"

# Build DMG
bold "[7/8] Bygger DMG"
rm -f "${DMG_PATH}"
hdiutil create -volname "${VOLUME_NAME}" \
  -srcfolder "${DMG_TMP}" \
  -ov -format UDZO \
  "${DMG_PATH}" 2>&1 | tail -3
DMG_SIZE=$(du -sh "${DMG_PATH}" | cut -f1)
ok "DMG bygget: ${DMG_SIZE}"

# Cleanup staging
rm -rf "${DMG_TMP}"

# Staple notarization ticket onto the DMG itself so Gatekeeper accepts the
# download without an internet round-trip on the user's first launch.
if [[ "${SAGA_NOTARIZE:-0}" == "1" ]]; then
  bold "[7b/8] Stapler ticket på DMG"
  xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${SAGA_NOTARY_APPLE_ID}" \
    --team-id "${SAGA_NOTARY_TEAM_ID}" \
    --password "${SAGA_NOTARY_PASSWORD}" \
    --wait \
    --timeout 30m \
    || fail "DMG-notarisering fejlede"
  xcrun stapler staple "${DMG_PATH}" || fail "DMG stapler staple fejlede"
  ok "DMG notariseret + stapled"
fi

# Final verification
bold "[8/8] Verifikation"
hdiutil verify "${DMG_PATH}" 2>&1 | tail -2 | head -1
if [[ "${SAGA_NOTARIZE:-0}" == "1" ]]; then
  spctl -a -t open --context context:primary-signature "${DMG_PATH}" 2>&1 | head -3 || true
fi
ok "Klar: ${DMG_PATH}"

echo
bold "✓ Færdig"
echo "  ${DMG_PATH}"
echo "  Test: open '${DMG_PATH}'"
echo
