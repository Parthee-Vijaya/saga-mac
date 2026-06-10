# Bidrage til Saga

Velkommen — bug-rapporter, feature-forslag og pull requests er alle velkomne.

## Inden du starter

- Læs [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — Contributor Covenant 2.1.
- For større ændringer (nye features, refactors): åbn en issue først så vi kan diskutere retning før du investerer tid.
- For bug-fixes: gå direkte til en PR.

## Build lokalt

### Forudsætninger

- macOS 15+ (Sequoia eller nyere) — Saga's deployment-target
- Apple Silicon Mac (M1+) — Canary CoreML kører kun på Apple Neural Engine
- Xcode 16+ med Command Line Tools
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [gh CLI](https://cli.github.com/) — anbefales for at downloade canary-coreml-modeller

### Klon + sæt op

Saga afhænger af **canary-coreml** (CoreML-konverterede ASR-modeller, ~1.8 GB) og valgfrit **hviske-coreml** (~2.9 GB). Begge skal ligge ved siden af saga-repoet:

```bash
mkdir -p ~/projekter && cd ~/projekter
git clone https://github.com/Parthee-Vijaya/saga-mac.git saga
git clone https://github.com/Parthee-Vijaya/canary-coreml.git
# (valgfrit) git clone https://github.com/Parthee-Vijaya/hviske-coreml.git

cd saga/saga-app
xcodegen generate                    # genererer SagaApp.xcodeproj
open SagaApp.xcodeproj                # Cmd+R bygger + kører
```

`canary-coreml`-modellerne skal være i `../canary-coreml/models/mlpackage/`. Hvis ikke, skal du enten downloade dem fra [canary-coreml's release](https://github.com/Parthee-Vijaya/canary-coreml/releases) eller køre Python-pipelinen i `canary-coreml/python/`.

### Build fra CLI

```bash
# Build Release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project saga-app/SagaApp.xcodeproj \
  -scheme Saga \
  -configuration Release \
  -destination "platform=macOS" \
  build

# Kør hele test-suiten (Swift Testing framework)
xcodebuild -project saga-app/SagaApp.xcodeproj -scheme Saga test \
  -destination "platform=macOS"

# Kør én testfil
xcodebuild -project saga-app/SagaApp.xcodeproj -scheme Saga test \
  -destination "platform=macOS" \
  -only-testing:SagaCoreTests/ModeRouterTests
```

### Bygge DMG

```bash
./scripts/build-dmg.sh                  # full DMG (~1.7 GB, mlpackages bundlet)
SAGA_SLIM=1 ./scripts/build-dmg.sh      # slim DMG (~12 MB, modeller downloades)
```

## Kode-stil

### Sprog

- **Dansk** i UI-strenge, kommentarer, log-strings, error-messages, README, ROADMAP, test-navne.
- **Engelsk** i type-navne, function-navne, variable-navne, file-navne (Swift convention).
- Mix-eksempel: `func handleHoldStart(...) { log.info("Recording startet") }`.

### Swift

- Swift 6 strict concurrency er aktiveret (`SWIFT_STRICT_CONCURRENCY: complete`) — Sendable og actor-isolation skal være eksplicit.
- `OTHER_SWIFT_FLAGS: -warnings-as-errors` — selv små advarsler failer build'et.
- Brug `@MainActor` på UI-klasser. Bridge-klasser der wrapper non-Sendable CoreML-typer bruger `@unchecked Sendable` med en serial DispatchQueue.
- Foretræk `let` over `var`. Foretræk computed properties over stored der kan udledes.

### Arkitektur-mønstre

- `SagaController` er top-level orkestrator — al state lever der.
- Bridge-klasser (`CanaryASRBridge`, `HviskeASRBridge`, `LMStudioBridge`) wrapper eksterne afhængigheder. Følg eksisterende mønster ved nye integrations.
- Settings-tabs ligger i `Sources/SagaCore/UI/Settings/` — én fil per tab.
- Mode-routing håndteres af `ModeRouter` med eksplicit prioritet (Reminder → Calendar → Vision → Odin → Edit → built-in trigger).

### Tests

- Test-framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`) — ikke XCTest.
- Test-target: `SagaCoreTests` (tester via `@testable import Saga`).
- CoreML-modeller loades IKKE i tests — hold dig til pure logik (vocabulary, mode-matching, sentence-flushing, VAD).
- Integration-tests er manuelle — se [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md).

## PR-checklist

Før du sender PR:

- [ ] `xcodegen generate` + Release-build er grøn med strict concurrency + warnings-as-errors
- [ ] `xcodebuild test` passer alle tests
- [ ] Nye public API'er har doc-comments (`///`)
- [ ] Dansk i UI/log/comments er konsistent
- [ ] [README.md](README.md) opdateret hvis brugbar feature
- [ ] [docs/ROADMAP.md](docs/ROADMAP.md) opdateret hvis det matcher en milestone
- [ ] Commit-besked i `type(scope): beskrivelse`-format på dansk eller engelsk

## Model-konvertering (avanceret)

Hvis du ændrer i ASR-pipelinen:

- **canary-coreml**: Python-pipeline der konverterer NVIDIA Canary `.nemo` → CoreML mlpackage. Kør `cd canary-coreml/python && uv venv && uv pip install -r requirements.txt && python 01_download.py && python 03_pytorch_to_coreml.py`. Kræver 16+ GB RAM under conversion.
- **hviske-coreml**: Konverterer syv.ai's Hviske-v3 (Whisper-large-v3-turbo finetune) via Argmax's whisperkit-tools. Kør `cd hviske-coreml/python && uv venv && uv pip install -r requirements.txt && python v3_convert.py`.

Output ender i hver søsterprojekts `models/`-mappe. Saga's bridge-klasser `locateModelsDirectory` søger flere fallback-paths inkl. `~/Desktop/Claude/projekter/aktive/{canary,hviske}-coreml/models/...`.

## Localization

Saga er dansk-first — det meste UI er hardcoded dansk. Infrastrukturen til oversættelser ligger klar:

- `saga-app/Resources/da.lproj/Localizable.strings` — dansk (udviklings-sprog)
- `saga-app/Resources/en.lproj/Localizable.strings` — engelsk skabelon

**Status:** Kun menubar'ens state-labels (`saga.state.*`) går gennem `NSLocalizedString` indtil videre (se `StatusView.stateText` som mønster). Resten af nøglerne i .strings-filerne er forberedt men ikke wiret.

**Vil du bidrage en oversættelse?**
1. Wire flere strings: wrap hardcodede danske strenge i `NSLocalizedString("nøgle", value: "Dansk fallback", comment: "kontekst")` og tilføj nøglen til begge .strings-filer
2. Nyt sprog: kopiér `en.lproj` til fx `sv.lproj`, oversæt værdierne, registrér mappen i `project.yml` under `sources:`

## Spørgsmål?

- Issue: https://github.com/Parthee-Vijaya/saga-mac/issues
- Email: parti.vijaya1@gmail.com

Tak fordi du bidrager!
