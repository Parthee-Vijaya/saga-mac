# Installation — Saga

Installations-guide til frisk Mac. Kun 3 trin.

## Krav

| Mac | macOS | RAM | Disk |
|---|---|---|---|
| **M1 eller nyere** (Apple Silicon) | **15.0** (Sequoia) eller nyere | 16 GB+ | 5 GB+ ledig |

> Intel-Macs er ikke supporterede — Saga's CoreML-modeller bruger Apple Neural Engine.

Optionelt: **LM Studio** for mode-routing (oversæt, opsummer, formatér). Saga
fungerer fuldt med pure dictation uden LM Studio.

## Trin 1 — Download + installér

### Mulighed A — `gh` CLI (anbefalet)

```bash
brew install gh                 # kun første gang
gh auth login                   # følg prompts (1 minut)
gh release download v0.1.0 \
  --repo Parthee-Vijaya/saga-mac \
  --pattern "Saga-*.dmg"
open Saga-0.1.0.dmg
```

### Mulighed B — curl + GitHub Personal Access Token

```bash
# 1. Generér PAT med 'repo'-scope: https://github.com/settings/tokens
export GH_TOKEN="ghp_din_token_her"

# 2. Find asset-id og download
ASSET_ID=$(curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/Parthee-Vijaya/saga-mac/releases/tags/v0.1.0" \
  | grep '"id"' | head -2 | tail -1 | grep -oE '[0-9]+')

curl -L -o Saga-0.1.0.dmg \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/Parthee-Vijaya/saga-mac/releases/assets/$ASSET_ID"

open Saga-0.1.0.dmg
```

### Mulighed C — browser

1. Gå til [GitHub Releases](https://github.com/Parthee-Vijaya/saga-mac/releases/tag/v0.1.0)
2. Klik `Saga-0.1.0.dmg` for at downloade
3. Dobbeltklik for at mounte

### Installér

1. DMG-vinduet viser **Saga.app** + **Applications**-genvej
2. Træk **Saga.app** over på **Applications**-genvejen
3. Eject DMG'en (right-click → Eject)

## Trin 2 — Første åbning (Gatekeeper)

Saga er signed med en Apple Developer-cert, men ikke notariseret hos Apple
(kræver Apple Developer-account hos brugeren). Derfor:

1. Åbn `Applications` i Finder
2. **Højre-klik** på Saga.app → **Åbn**
3. Klik **"Åbn"** i sikkerheds-dialogen
4. Saga åbner herefter normalt fra Spotlight (`Cmd+Space → Saga`)

Næste gang du åbner Saga, vises ingen advarsel — macOS husker dit valg.

## Trin 3 — First-run wizard

Første gang Saga starter, vises et velkomst-vindue der guider dig gennem:

1. **Vælg push-to-talk-tast** — default er **Højre Option** (`⌥`).
   Apple-keyboard-brugere kan vælge `Fn` (globe-tast).
2. **Mikrofon** — Saga beder macOS om adgang. Klik "Tillad".
3. **Accessibility** — kræves for at registrere push-to-talk-tasten og indsætte
   tekst. Klik "Åbn Settings" → toggle Saga ON. Saga opdager det automatisk.
4. **LM Studio** — hvis du har LM Studio kørende, opdager Saga den automatisk.
   Hvis ikke, kan du installere senere fra [lmstudio.ai](https://lmstudio.ai).

Klik **"Kom i gang →"** når mic + AX er grantet.

## Brug

1. Sæt cursor i hvilket-som-helst tekstfelt (Notes, Mail, Slack, Claude Code, …)
2. **Hold ⌥ Højre Option** → tal dansk → slip
3. Tekst indsættes ved cursor
4. Klik status-bar-ikon (`waveform.circle`) for live status, historik og indstillinger

## LM Studio (valgfri)

For mode-routing (oversæt/opsummer/formatér):

1. Hent fra [lmstudio.ai](https://lmstudio.ai)
2. Søg + download fx `gemma-4-26b-a4b` (~16 GB)
3. Klik "Start Server" i LM Studio (default port 1234)
4. Saga finder den automatisk ved næste app-start, eller klik "Find LM Studio
   igen" i Saga's Settings

Mindre RAM-modeller hvis 16 GB er stramt:
- `gemma-2-9b-it` (~5 GB)
- `llama-3.1-8b-instruct` (~5 GB)
- `qwen2.5-7b-instruct` (~4 GB)

## Fejlfinding

### "Saga kunne ikke åbnes — kunne ikke verificeres"
Højre-klik Saga.app → Åbn (se Trin 2 ovenfor). Engangs-bypass.

### Hotkey reagerer ikke
- Tjek at Saga er TILLADT i System Settings → Privacy & Security → Accessibility
- Hvis du bruger Logitech/3rd-party keyboard: vælg **Højre Option** i Settings (ikke Fn)

### Status-bar viser "Indlæser ASR-model" i lang tid
- Første cold-start: ~10-22 sek (CoreML kompilerer ANE-kerner)
- Efterfølgende app-starts: ~5-8 sek
- Hvis det varer >60 sek: kvit Saga, åbn igen

### Tekst indsættes ikke
- Verificer cursor er i et redigerbart felt (ikke en webside-overskrift)
- macOS blokerer keyboard-injection i adgangskode-felter — by design

### Tekst er forkert / kvalitet er dårlig
- Sørg for stille omgivelser
- Tal tydeligt og naturligt — ikke for hurtigt
- WER på dansk: ~8% (read-aloud), ~15% (samtale-tale)

## Afinstallation

1. Træk Saga.app fra Applications til Papirkurv
2. Slet historik: `~/Library/Application Support/Saga/`
3. Slet preferences: `defaults delete dk.parthee.saga`
4. Reset permissions: System Settings → Privacy & Security → Microphone /
   Accessibility → Saga → "−"-knap

## Opdatering

Træk ny Saga.app fra DMG over den gamle i Applications. macOS spørger om
overskrivning — sig "Erstat".

Permissions overlever opdateringer (samme code-signing identity).

## Privacy

- **Audio forlader ikke maskinen.** Canary kører lokalt på Apple Silicon.
- **Ingen telemetri, ingen analytics.**
- **Transkripter** gemmes lokalt i `~/Library/Application Support/Saga/history.json`
  (max 100 entries). Kan slettes via "Ryd alt"-knap.
- **Mode-routing** sender prompt-tekst til din egen LM Studio på localhost
  — aldrig til cloud.

## Support

GitHub: https://github.com/Parthee-Vijaya/saga-mac (privat repo)
