# Release Process

Saga distribueres som signeret + notariseret DMG via GitHub Releases.

## Versionering

- Semantic versioning: `MAJOR.MINOR.PATCH` (eks. `0.3.0`)
- `MARKETING_VERSION` i `saga-app/project.yml` skal opdateres før tag
- Tag-format på GitHub: `v0.3.0` (med `v`-prefix)

## Flow (high-level)

```
1. Bump MARKETING_VERSION i saga-app/project.yml
2. Opdat docs/ROADMAP.md hvis fasen er afsluttet
3. Commit + tag + push:
     git commit -am "chore: release v0.3.0"
     git tag -a v0.3.0 -m "v0.3.0"
     git push origin main --tags
4. GitHub Actions release.yml kører automatisk:
     - importerer Developer ID cert
     - bygger Release
     - bundler Canary mlpackages
     - signerer med Developer ID
     - notariserer (xcrun notarytool)
     - stapler ticket
     - bygger DMG
     - opretter draft Release
5. Maintainer publish'er draft → notify users
```

## Lokal release-build (uden notarisering)

```bash
./scripts/build-dmg.sh
# → dist/Saga-X.Y.Z.dmg (ad-hoc eller Apple Development signed, ikke distributable)
```

## Lokal release-build MED notarisering

```bash
export SAGA_SIGN_IDENTITY="<SHA1 af din Developer ID Application cert>"
export SAGA_NOTARIZE=1
export SAGA_NOTARY_APPLE_ID="dit@apple-id.dk"
export SAGA_NOTARY_TEAM_ID="ABCDE12345"
export SAGA_NOTARY_PASSWORD="app-specific-password-fra-appleid.apple.com"

./scripts/build-dmg.sh
```

`SHA1` af cert findes via:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## GitHub Actions secrets (krævet for release.yml)

Sættes under **Settings → Secrets and variables → Actions**:

| Secret | Hvad det er |
|---|---|
| `APPLE_ID` | Apple ID-email til notariseringskonto |
| `APPLE_TEAM_ID` | 10-tegns Team ID (findes på developer.apple.com) |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password genereret på appleid.apple.com |
| `DEVELOPER_ID_CERT_P12_BASE64` | Developer ID Application cert eksporteret som `.p12`, derefter `base64 -i cert.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | Adgangskoden brugt da `.p12` blev eksporteret |
| `SAGA_SIGN_IDENTITY` | SHA1-fingeraftrykket af cert'en (printes når den importeres) |

### Generér `DEVELOPER_ID_CERT_P12_BASE64`

```bash
# 1. Eksportér fra Keychain Access:
#    Login keychain → My Certificates → "Developer ID Application: Dit Navn" → højre-klik → Export → .p12
# 2. Konvertér til base64:
base64 -i Developer_ID.p12 | pbcopy
# 3. Paste i GitHub secret
```

### Generér app-specific password

1. Log ind på https://appleid.apple.com
2. Sign-In and Security → App-Specific Passwords → Generate
3. Label det "Saga notarytool" og kopier resultatet

## Hvis notarisering fejler

Tjek hvad Apple klagede over:

```bash
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD"
```

Almindelige problemer:

- **Hardened runtime ikke aktiveret** — fix i `project.yml`: `ENABLE_HARDENED_RUNTIME: YES` (allerede sat)
- **Forkert team-id i provisioning** — verificer `xcrun altool --list-teams ...`
- **Embedded mlpackage indeholder usignerede dylibs** — re-sign med `--deep` (allerede gjort i build-dmg.sh)
- **Manglende usage descriptions** — alle `NS*UsageDescription` keys skal være i Info.plist (allerede tilføjet)

## Pre-release smoke test

Før draft release publish'es:

1. Download DMG-asset fra draft release på en frisk Mac (eller Mac uden Saga build env)
2. Mount → træk Saga.app til /Applications
3. Cmd+Space → "Saga" → bekræft den åbner uden Gatekeeper-bypass
4. Følg `docs/SMOKE_TEST.md`

## Post-release

- Skriv release notes (auto-genereret fra commits er udgangspunkt)
- Pin issue: "v0.3.0 release — known issues + how to report"
- Hvis breaking change for persistens: dokumentér migration-path i release notes
