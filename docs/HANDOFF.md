# Saga handoff: fra CLI-maskine → Xcode-maskine

> Dette dokument er en samlet briefing til Claude Code (eller mennesket) på den maskine hvor Xcode + `canary-coreml` faktisk kører. Læs det fra top til bund før du gør noget. Det dækker: hvad der er lavet, hvad der **ikke** er testet, hvad du skal verificere først, og i hvilken rækkefølge ting bør merges.

## TL;DR

10 PR'er er åbne på GitHub. **Ingen af dem er nogensinde compiled** — alt er skrevet på en CLI-maskine uden Xcode. Saga's projekt-config er `SWIFT_STRICT_CONCURRENCY=complete` og `-warnings-as-errors`, så compile-risiko er reel.

**Før du gør noget:** byg `feature/d5-per-app-profiles` (toppen af stakken) og fix compile-fejl før du merger nogetsomhelst til main.

---

## Hvad blev bygget i CLI-sessionen

### Branch-stak

```
main
 ├─ feature/sprint-a-docs-only         (PR #1, docs + community + notarization)
 ├─ feature/sprint-a-public-ready      (LOKAL kun — ikke pushet pga. workflow scope)
 ├─ feature/sprint-b-power-user        (PR #2, vocabulary + VAD + voice-edit)
 └─ feature/sprint-c1-tts-infra        (PR #3, TTS infrastructure)
     └─ feature/sprint-c2-companion-state  (PR #4, Companion state machine)
         └─ feature/sprint-c3-companion-overlay  (PR #5, live-caption overlay)
             └─ feature/d1-settings-split        (PR #6, refactor SettingsView)
                 └─ feature/d2-sparkle-and-slim-dmg  (PR #7, Sparkle + on-demand model)
                     └─ feature/d3-cursor-bubble        (PR #8, cursor-following bubble)
                         └─ feature/d4-live-partial-transcript  (PR #9, SFSpeech parallels)
                             └─ feature/d5-per-app-profiles      (PR #10, per-app overrides)
```

### Filer

| Område | Antal nye filer | Linjer (~) |
|---|---|---|
| Docs (architecture, release, sparkle, contributing) | 7 | 1.500 |
| TTS (Apple, ElevenLabs, coordinator, keychain) | 5 | 600 |
| Companion (session, controller, sentence-flusher, message) | 4 | 600 |
| UI (overlay, cursor-bubble, settings tabs split) | 9 | 1.400 |
| Audio (VAD, live-partial) | 2 | 300 |
| Updates (UpdateManager, ModelStorage, ModelDownloader) | 3 | 350 |
| Profiles (model + store + settings tab) | 3 | 400 |
| Modes (EditMode + SelectionReader) | 2 | 200 |
| Vocabulary (entry + store + post-processor) | 3 | 350 |
| Tests | 6 | 700 |

= ~32 nye filer, ~7.000 linjer Swift + docs, **72 unit-tests** (Swift Testing framework).

### project.yml ændringer

Tilføjet i `feature/d2-sparkle-and-slim-dmg`:

```yaml
packages:
  CanaryKit:
    path: ../../canary-coreml/swift
  Sparkle:                                # NEW
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"

# Info.plist additions:
SUFeedURL: "https://parthee-vijaya.github.io/saga-mac/appcast.xml"   # ← placeholder URL, ikke hostet
SUPublicEDKey: "REPLACE_WITH_BASE64_PUBLIC_KEY_FROM_generate_keys"  # ← MUST FIX før Sparkle virker
SUEnableAutomaticChecks: true
SUScheduledCheckInterval: 86400
```

---

## Hvad der **ikke** er testet (vigtigt)

Alt under er **kun verificeret ved code-review** af den der skrev det. Ingen kompilering, ingen runtime-test.

### Højrisiko — verificér først

1. **Sparkle SPM-dependency** (PR #7 / D2)
   - SPM kan finde "no compatible versions" hvis Sparkle 2.6+ kræver en specifik Swift/macOS-version der ikke er præcis på din maskine
   - `SUPublicEDKey` er en placeholder → app vil starte, men "Tjek for opdatering" vil fail med signature-error når den henter appcast.xml
   - **Action**: kør `xcodegen generate` → `xcodebuild build` på `feature/d2-sparkle-and-slim-dmg`. Hvis Sparkle ikke resolver, prøv `from: "2.6.4"` (specifik version) i `project.yml`

2. **LivePartialTranscriber + AudioCapture concurrent mic-access** (PR #9 / D4)
   - To audio-subsystemer på samme mic: AVAudioEngine (SFSpeechRecognizer) + AVAudioRecorder (Canary). På macOS deler de typisk uden problem, men ikke verificeret
   - **Symptom hvis det fejler**: AudioCapture skriver tom WAV, eller AVAudioEngine.start() throw'er
   - **Action**: hold push-to-talk i Companion test-conversation, tjek at både live-caption opdateres og at Canary's transcript er ikke-tom

3. **CompanionController inline silence-detection** (PR #4 / C2)
   - Polling-baseret VAD via `audio.levelHistory.last`. Sprint B's `EnergyVAD` er på en parallel branch (PR #2), ikke merged. Den inline-implementation er enklere men ikke battle-tested
   - **Symptom hvis det fejler**: Companion-tur slutter aldrig, eller slutter for tidligt
   - **Action**: tune `silenceThreshold = 0.05` i `CompanionController` hvis nødvendigt

4. **Cursor-bubble global mouse monitor** (PR #8 / D3)
   - `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` skulle virke med eksisterende Accessibility-permission, men der er edge-cases på macOS Sequoia hvor den fejler silent
   - **Symptom**: bubble vises men flytter sig ikke
   - **Action**: hvis det fejler, fall back til polling NSEvent.mouseLocation hver 50ms

### Mediumrisiko

5. **LMStudioBridge.chatStream SSE parser** (PR #4 / C2)
   - LM Studio's `stream=true` SSE er kompatibel med OpenAI, men nogle modeller respekterer det ikke. Fallback-path eksisterer men er ikke testet
   - **Action**: kør test-conversation. Hvis Saga venter længe før første sætning, tjek Console.app for "Server returnerede ikke SSE — falder til non-streaming"

6. **ElevenLabs API integration** (PR #3 / C1)
   - HTTP-flow: POST /v1/text-to-speech/{voiceID}, MP3 → AVAudioPlayer. Den nøgle bruger delte i chat var allerede 401 (revoked/udløbet), så endpoint-format er ikke bekræftet med live API
   - **Action**: indsæt en gyldig key i Settings → Companion → ElevenLabs → "Tilføj key", klik "Test TTS". Hvis det fejler, tjek `ElevenLabsTTSEngine.downloadMP3` for evt. format-fejl

7. **VAD auto-stop med EnergyVAD** (PR #2 / Sprint B)
   - Min/max værdier er valgt på fornemmelse: silenceThreshold=0.05, silenceDuration=1.2s. Kan være forkert for high-noise mics
   - **Action**: aktivér VAD i Settings → Stemme, hold hotkey, hør om auto-stop føles snappy

### Lavrisiko (men stadig untested)

8. **Settings UI rendering** — alle nye tabs (Companion, Apps) kan have layout-issues på 13" Mac
9. **Multi-monitor positioning** — overlay og bubble bruger NSScreen.screens.first { $0.frame.contains(mouse) }. Kan ramme edge-cases ved mismatched DPI
10. **Vocabulary regex med Unicode word-boundaries** — testet med tests, ikke med rigtig Canary-output

---

## Pre-build setup (én-gangs ting)

Disse skal være på plads FØR du kører `xcodegen generate`.

### 1. Verificér canary-coreml er på plads

```bash
ls ~/Projects/canary-coreml/swift/Package.swift  # eller hvor du har det
ls ~/Projects/canary-coreml/models/mlpackage/CanaryEncoder.mlpackage
```

`saga-app/project.yml` peger på `../../canary-coreml/swift` — saga-mac og canary-coreml skal være søsterprojekter.

### 2. Sparkle EdDSA keypair (kun nødvendigt hvis du vil teste auto-update)

```bash
# Hent Sparkle CLI-tools (én gang)
brew install sparkle  # eller download fra https://github.com/sparkle-project/Sparkle/releases

# Generér keypair — privat nøgle gemmes i Keychain, public printes
generate_keys

# Output indeholder linjen:
#   SUPublicEDKey: AbCdEfGh...
```

Kopiér public-key-værdien til `saga-app/project.yml`:
```yaml
SUPublicEDKey: "AbCdEfGhDinPubliKey..."  # erstat REPLACE_WITH_BASE64_PUBLIC_KEY_FROM_generate_keys
```

**Hvis du ikke vil køre Sparkle**: lad placeholder stå. App'en starter, men "Tjek for opdatering"-knappen vil fejle. Det blokerer ikke andet.

### 3. Push den lokale workflow-branch (kun hvis du vil have CI)

På CLI-maskinen ligger `feature/sprint-a-public-ready` lokalt med GitHub Actions workflows som ikke kunne pushes pga. token-scope.

```bash
gh auth refresh -h github.com -s workflow
git checkout feature/sprint-a-public-ready
git push -u origin feature/sprint-a-public-ready
```

Den branch indeholder kun `.github/workflows/{ci,lint,release}.yml` + `.swiftlint.yml`. Den er ortogonal til alt det andet.

### 4. (Kun for slim-DMG-test) Upload canary-coreml release-assets

Hvis du vil teste D2's slim-DMG-flow:
```bash
cd ~/Projects/canary-coreml/models/mlpackage
for pkg in CanaryEncoder.mlpackage CanaryDecoderLM.mlpackage CanaryPreprocessor.mlpackage; do
  zip -rq "${pkg}.zip" "${pkg}"
done
gh release create v1.0.0 \
  --repo Parthee-Vijaya/canary-coreml \
  CanaryEncoder.mlpackage.zip CanaryDecoderLM.mlpackage.zip CanaryPreprocessor.mlpackage.zip
```

Hvis du ikke vil: lad være, og byg DMG'en uden `SAGA_SLIM=1`. Den falder bare tilbage til den eksisterende 1.7 GB bundled-build.

---

## Build-verifikation pr. branch

**Anbefaling**: byg D5 først (toppen). Hvis den compiler, compiler alt under den også. Hvis ikke, isolér hvilken D# der introducerer fejlen.

```bash
cd ~/Projects/saga-mac
git fetch origin

# Top af stakken — indeholder alt
git checkout feature/d5-per-app-profiles

cd saga-app
xcodegen generate
xcodebuild -project Saga.xcodeproj \
  -scheme Saga \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -50
```

**Hvis det fejler**: noter fejl-linje, `git checkout` ned ad stakken én ad gangen indtil branch'en der introducerer fejlen findes. Fix der, push, så bygger alle ovenpå.

### Forventet error-pattern

- **"Cannot find type 'Sparkle' in scope"** → SPM-dep ikke resolved. Kør `xcodegen generate` igen og åbn `.xcodeproj` i Xcode først så SPM-resolve kører
- **"Sendable conformance" warnings** → strict concurrency kan flagge `@unchecked Sendable` jeg har brugt
- **"Property 'audioEngine' not concurrency-safe"** → LivePartialTranscriber edge-case
- **"missing argument labels"** — generelt kompile-fejl

### Test-suite

```bash
xcodebuild test \
  -project Saga.xcodeproj \
  -scheme Saga \
  -destination 'platform=macOS,arch=arm64' \
  -enableCodeCoverage YES 2>&1 | tail -30
```

72 tests i `saga-app/Tests/SagaCoreTests/`. De skulle alle passere. Hvis ikke, det er sandsynligvis tegn på kompile-issue snarere end logic-fejl.

---

## Manuelle smoke-tests pr. feature

Kør disse i rækkefølge efter build er grøn. Hver test antager den foregående virker.

### Test 1: Push-to-talk dictation (regression)

1. Cmd+R i Xcode
2. Granté Mikrofon + Accessibility i System Settings hvis ikke allerede
3. Hold højre Option, sig "hej verden", slip
4. Verificér tekst dukker op ved cursor i et tekstfelt
5. **Hvis fejler**: tjek at canary-coreml mlpackages er bundlet korrekt

### Test 2: Vocabulary post-processor (Sprint B)

1. Settings → Ordforråd → "Ny entry"
2. Pattern: `xcodegen`, Replacement: `XcodeGen` (case)
3. Sig push-to-talk: "jeg bruger xcodegen til build"
4. Verificér output: "jeg bruger XcodeGen til build"

### Test 3: VAD auto-stop (Sprint B)

1. Settings → Stemme → "Aktivér auto-stop"
2. Hold hotkey, sig en sætning, vent 1.2s i stilhed
3. Verificér at recording stopper automatisk (transcript indsættes)

### Test 4: Voice-edit mode (Sprint B)

1. Åbn Notes, skriv "dette er en grim sætning", markér det
2. Hold hotkey, sig "ret kolon gør den mere formel"
3. Verificér markeret tekst overskrives med poleret version (kræver LM Studio kører)

### Test 5: Apple TTS (Sprint C1)

1. Settings → Companion → Engine: Apple
2. Klik "Test TTS"
3. Verificér Sara/dansk-stemme siger "Hej, jeg er Saga"

### Test 6: ElevenLabs TTS (Sprint C1)

1. Settings → Companion → Engine: ElevenLabs
2. "Tilføj key" → indsæt gyldig API-key (få fra elevenlabs.io)
3. Klik refresh i voice-listen → vælg en stemme
4. Klik "Test TTS"
5. Verificér ElevenLabs-stemme afspilles
6. Sluk Wi-Fi → klik "Test TTS" igen → skal fall back til Apple

### Test 7: Companion conversation (Sprint C2 + C3)

1. Settings → Stemme → wake-word ON
2. Settings → Companion → Aktivér Companion
3. Klik "Start test-conversation" (eller sig "Hej Saga")
4. Verificér overlay glider ind nederst på skærm
5. Sig "hvad er klokken" — verificér:
   - Live caption opdateres MENS du taler (D4 — partial transcripts)
   - Caption skifter til Canary's authoritative version efter du stopper
   - Saga svarer via TTS (D1's hørbare bevis)
   - Reply-tekst bygges i overlay som tokens streames
6. Sig "kan du gentage" uden re-wake-word — verificér samtalen fortsætter med kontekst
7. Sig "tak" — verificér overlay fader ud

### Test 8: Cursor-bubble (D3)

1. Settings → Companion → "Cursor-bubble" ON
2. Start test-conversation
3. Verificér lille bubble dukker op nær cursor med state-ikon
4. Flyt musen — verificér bubble følger med
5. Flyt mod højre kant — verificér bubble flipper til venstre side

### Test 9: Slim-DMG model-download (D2)

1. Slet bundled mlpackage: byg appen med `SAGA_SLIM=1 ./scripts/build-dmg.sh`
2. Drag-and-drop til /Applications, åbn
3. Verificér setup-wizard *eller* Settings → Om → ModelStorage viser "Mangler"
4. (Future: trigger download fra wizard. Pt. er der ingen UI til det — `controller.modelDownloader.startDownload()` skal kaldes manuelt fra debug-Console)

### Test 10: Per-app profil (D5)

1. Åbn Notes
2. Settings → Apps → "Profil for Notes" (knap pre-fylder bundle-id)
3. Forced mode: "format"
4. Skift til Notes, hold push-to-talk, sig noget rod
5. Verificér output er poleret tekst (format-mode auto-applied)

---

## Bør jeg merge til main før jeg har testet i Xcode?

**Nej.** Konkret pr. PR:

| PR | Risiko | Sikker at merge før Xcode-test? |
|---|---|---|
| #1 Sprint A (docs only) | None | **Ja** — ren dokumentation |
| #2 Sprint B (vocabulary, VAD, voice-edit) | Compile-risk i SelectionReader force-cast + AX-API | Nej, byg først |
| #3 Sprint C1 (TTS) | Sendable issues mulige | Nej, byg først |
| #4 Sprint C2 (Companion) | Streaming logic, inline VAD | Nej, byg + test conversation først |
| #5 Sprint C3 (overlay) | SwiftUI rendering | Nej, byg først |
| #6 D1 (refactor) | Lav — pure file-move | Sandsynligvis OK, men byg først |
| #7 D2 (Sparkle + slim) | **Høj** — SPM dep + Info.plist placeholder | **Bestemt nej** |
| #8 D3 (cursor bubble) | Global event monitor edge-cases | Nej, byg + test først |
| #9 D4 (live partial) | **Høj** — concurrent mic access | **Bestemt nej** |
| #10 D5 (per-app) | Lav | Byg først, men sikker logic |

**Anbefalet flow:**

1. Byg `feature/d5-per-app-profiles` (toppen). Fix evt. compile-fejl. Push fixes til samme branch.
2. Kør test 1 (regression — push-to-talk dictation virker stadig)
3. Kør test 7 (Companion happy path — det er den mest komplekse integration)
4. Hvis begge passerer, **merge i denne rækkefølge til main**:
   - PR #1 (docs) først, fordi den er konfliktfri
   - PR #2 (Sprint B) — separat track
   - PR #3 (C1) → #4 (C2) → #5 (C3) som stack — merge én ad gangen
   - PR #6 (D1) — refactor
   - PR #7 (D2) — kun efter Sparkle key er sat og du har testet at app'en boot'er
   - PR #8 (D3) — efter test 8 passerer
   - PR #9 (D4) — efter test 7 viser at live-partials faktisk virker
   - PR #10 (D5) — sidst

5. Efter D2 merger: tag som `v0.5.0-beta1`, byg slim-DMG, test installation på en frisk Mac

**Genvej hvis du vil leve farligt**: merger D5 direkte til main hvis byggene er grønne. Det giver alle 10 PR'er på én gang. Ulempen er at hvis ét feature-flag fejler runtime, har du ikke et bisect-punkt.

---

## Kendte problemer der skal fixes før v0.5.0 er klar

Dette er items jeg kalder ud fordi jeg er stødt på dem under skrivning men ikke kunne fixe uden at compile:

1. **SagaController.swift bliver stor** (~500+ linjer efter D5). Bør splittes som beskrevet i `docs/ARCHITECTURE.md`'s technical debt-sektion.
2. **`saga-sidecar/` mappe + Hviske-referencer i `scripts/setup.sh`** er døde siden M0.D. Bør slettes som separat cleanup-PR.
3. **LICENSE er stadig "All Rights Reserved"** — blokerer reelle forks. Beslut MIT vs Apache-2.0 vs noget andet før public-promotion.
4. **`docs/SMOKE_TEST.md`** er ikke opdateret med Companion/D-features — bør tilføjes når D-stack er merged.
5. **GitHub Actions CI** kører ikke endnu fordi `feature/sprint-a-public-ready` ikke er pushet (workflow scope-issue).

---

## Hvordan du fortsætter herfra

### Hvis du vil fortsætte med Claude Code

```bash
cd ~/Projects/saga-mac
git fetch origin
git checkout feature/d5-per-app-profiles

# Start Claude Code, og giv den dette dokument som første prompt:
claude --continue
# eller en ny session — bare paste dette dokument's TL;DR som første besked
```

Bed Claude:
1. Læs `docs/HANDOFF.md` (dette dokument)
2. Byg projektet, fix compile-fejl
3. Kør test-suite
4. Tag derefter manual-smoke-tests i den foreslåede rækkefølge
5. Når alle grønne: assist med merge til main

### Hvis du vil fortsætte uden Claude

Kør sektionen "Build-verifikation pr. branch" → fix → "Manuelle smoke-tests" → merge i den anbefalede rækkefølge.

---

## Kontakt-info

Repo: https://github.com/Parthee-Vijaya/people-Vijaya/saga-mac (verificér URL)

PR'er åbne: https://github.com/Parthee-Vijaya/saga-mac/pulls

Plan-fil med oprindelig kontekst (kun lokal til CLI-maskinen):
`/Users/parthee/.claude/plans/giv-mig-en-plan-toasty-goblet.md`

---

**Slutbemærkninger**:

- Sikkerhed: ElevenLabs API-key delt i tidligere chat-session er HTTP 401 (revoked). Brug en frisk når du tester. Den lander i Keychain, aldrig i git/logs/UserDefaults.
- Privacy: Saga's identitet er stadig "lokal-først". ElevenLabs er opt-in cloud, alt andet kører lokalt.
- Auto-update: Sparkle er klar i koden, men `SUPublicEDKey` placeholder skal erstattes for at virke i produktion.
