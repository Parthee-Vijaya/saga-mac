# Contributing to Saga

Tak for din interesse i at bidrage til Saga! / Thanks for your interest in contributing to Saga!

> 🇬🇧 English version below the Danish section.

---

## 🇩🇰 Bidrag på dansk

### Licensstatus (vigtigt)

Saga er pt. udgivet under "All Rights Reserved" (se `LICENSE`). Repository'et er offentligt for transparens og feedback, men en formel open source-licens er **endnu ikke valgt**. Indtil det er afklaret, accepteres bidrag kun som forslag/PR'er ejeren manuelt kan integrere — ikke som forks under en bestemt fri licens.

Hvis du planlægger større bidrag, så åbn et issue først, så vi kan tale licens og scope.

### Forudsætninger

- macOS 15.0+ med Apple Silicon (M1+)
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [canary-coreml](https://github.com/Parthee-Vijaya/canary-coreml) klonet som søsterprojekt (samme niveau som `saga-mac`)

### Kom i gang

```bash
# Klon repo + canary-coreml-pakken som søster-mappe
git clone https://github.com/Parthee-Vijaya/saga-mac.git
git clone https://github.com/Parthee-Vijaya/canary-coreml.git  # samme niveau

cd saga-mac/saga-app
xcodegen generate          # genererer Saga.xcodeproj
open Saga.xcodeproj         # eller xcodebuild fra CLI
```

### Workflow

1. Opret en feature-branch: `git checkout -b feature/min-feature`
2. Skriv kode + tests
3. Kør lokal build: `xcodebuild -scheme Saga -configuration Debug`
4. Åbn en PR med beskrivelse af hvad og hvorfor
5. Sørg for at CI er grøn

### Kodestil

- Swift 6, strict concurrency
- Warnings-as-errors er aktiveret — alle warnings skal fixes
- Følg eksisterende mønstre i `Sources/SagaCore/` (én feature pr. mappe)
- Foretrukne navne: PascalCase for typer, camelCase for properties/methods
- `MainActor` for UI; aktor-isoleret kode for delt state

### Tests

Tests ligger i `saga-app/Tests/`. Kør med:

```bash
xcodebuild test -scheme Saga -destination "platform=macOS"
```

Pure-logic moduler bør have tests. Audio capture, CoreML inference, og CGEvent injection kræver hardware/permissions og skal smoke-testes manuelt.

### Commit-besked

Følg [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: tilføj voice-edit mode
fix: ret HUD-flicker når mode skifter
docs: opdater INSTALL.md med Apple Silicon krav
refactor: split SagaController i tre koordinatorer
test: tilføj tests for ModeRouter
```

### PR-checklist

Før du markerer en PR klar:

- [ ] Builder lokalt (Debug + Release)
- [ ] Tests passerer
- [ ] Ingen nye warnings
- [ ] Manuel smoke-test på din egen Mac
- [ ] Dokumentation opdateret hvis API ændres
- [ ] Commit-beskeder følger Conventional Commits

### Hvor stiller jeg spørgsmål?

- **Bug eller fejl**: Åbn et issue med "bug" template
- **Feature-forslag**: Åbn et issue med "feature request" template
- **Generelle spørgsmål**: GitHub Discussions (når aktiveret)
- **Sikkerhedshul**: Se [SECURITY.md](SECURITY.md) — rapportér privat

---

## 🇬🇧 Contributing in English

### License status (important)

Saga is currently released under "All Rights Reserved" (see `LICENSE`). The repository is public for transparency and feedback, but a formal open source license has **not yet been chosen**. Until that's resolved, contributions are accepted only as suggestions/PRs the maintainer can manually integrate — not as forks under a specific free license.

If you're planning a larger contribution, please open an issue first to discuss license and scope.

### Prerequisites

- macOS 15.0+ on Apple Silicon (M1+)
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [canary-coreml](https://github.com/Parthee-Vijaya/canary-coreml) cloned as a sibling directory next to `saga-mac`

### Getting started

```bash
git clone https://github.com/Parthee-Vijaya/saga-mac.git
git clone https://github.com/Parthee-Vijaya/canary-coreml.git  # sibling

cd saga-mac/saga-app
xcodegen generate
open Saga.xcodeproj
```

### Workflow

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Write code + tests
3. Build locally: `xcodebuild -scheme Saga -configuration Debug`
4. Open a PR describing what and why
5. Make sure CI is green

### Code style

- Swift 6 with strict concurrency
- Warnings-as-errors is enabled — all warnings must be fixed
- Follow existing patterns in `Sources/SagaCore/` (one feature per directory)
- PascalCase for types, camelCase for properties/methods
- `MainActor` for UI; actor-isolated code for shared state

### Tests

Tests live in `saga-app/Tests/`. Run with:

```bash
xcodebuild test -scheme Saga -destination "platform=macOS"
```

Pure-logic modules should have tests. Audio capture, CoreML inference, and CGEvent injection require hardware/permissions and must be smoke-tested manually.

### Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add voice-edit mode
fix: HUD flicker when mode changes
docs: update INSTALL.md with Apple Silicon requirements
refactor: split SagaController into three coordinators
test: add tests for ModeRouter
```

### PR checklist

Before marking a PR ready:

- [ ] Builds locally (Debug + Release)
- [ ] Tests pass
- [ ] No new warnings
- [ ] Manual smoke-test on your own Mac
- [ ] Documentation updated if API changes
- [ ] Commit messages follow Conventional Commits

### Where to ask questions

- **Bug or defect**: Open an issue with the "bug" template
- **Feature request**: Open an issue with the "feature request" template
- **General questions**: GitHub Discussions (when enabled)
- **Security issue**: See [SECURITY.md](SECURITY.md) — report privately
