# Smoke-test — Saga DMG på frisk Mac

Manuel test-procedure efter `scripts/build-dmg.sh`. Tager ~10 minutter.

## Forudsætninger

- Frisk macOS Sequoia 15+ Mac (eller "fresh" user-account på din egen Mac)
- DMG-fil bygget: `dist/Saga-X.Y.Z.dmg`
- Eventuelt: LM Studio installeret + en model loaded for mode-routing test

## Reset state (hvis du tester på din egen Mac)

```bash
# Ryd alt Saga-state
pkill -x Saga
rm -rf /Applications/Saga.app
rm -rf ~/Library/Application\ Support/Saga
defaults delete dk.parthee.saga 2>/dev/null
tccutil reset Accessibility dk.parthee.saga
tccutil reset Microphone dk.parthee.saga
```

## Trin 1 — DMG-installation

- [ ] Mount DMG ved dobbeltklik. Vindue viser **Saga.app**, **Applications**-symlink, **Læs mig.txt**
- [ ] DMG-titel er "Saga X.Y.Z" (matcher MARKETING_VERSION)
- [ ] Træk Saga.app over Applications-symlinket — kopiering tager ~10-30 sek (1.8 GB)
- [ ] Eject DMG via right-click

## Trin 2 — First launch

- [ ] Højre-klik Saga.app i /Applications → Åbn
- [ ] Sikkerheds-dialog vises ("kunne ikke verificeres" eller lignende)
- [ ] Klik "Åbn"
- [ ] Saga starter — status-bar-ikon (waveform-cirkel) dukker op øverst
- [ ] Ingen ekstra dock-icon (LSUIElement = true)

## Trin 3 — First-run wizard

- [ ] Velkomst-vindue åbner automatisk inden for ~1 sek
- [ ] Titel: "Velkommen til Saga"
- [ ] 4 trin synlige: "Sådan virker det" / "Vælg push-to-talk" / "Permissions" / "LM Studio"
- [ ] Hotkey-picker default = "Højre Option (⌥)"
- [ ] Skift hotkey til "Fn" → orange advarsel om Logitech-keyboards vises
- [ ] Skift tilbage til "Højre Option"

### Permissions

- [ ] Klik "Tillad" ved Mikrofon → macOS dialog "Saga vil have adgang til mikrofonen"
- [ ] Klik "Tillad" → status-row opdaterer til grøn checkmark inden for 2 sek
- [ ] Klik "Åbn Settings" ved Accessibility → System Settings åbner Privacy → Accessibility
- [ ] Find Saga i listen → toggle ON
- [ ] Vend tilbage til Saga wizard → Accessibility-row bliver grøn inden for 2 sek
- [ ] "Kom i gang →"-knap bliver enabled

### LM Studio

Hvis LM Studio kører:
- [ ] Status viser "Fundet på localhost:1234 med X modeller"

Hvis ikke:
- [ ] Status viser "Ingen LM Studio fundet"
- [ ] "Søg igen"-knap virker

- [ ] Klik "Kom i gang →" → wizard lukker

## Trin 4 — Hovedfunktion (dictation)

- [ ] Åbn TextEdit, klik for at sætte cursor i et nyt dokument
- [ ] Hold Højre Option (`⌥`) → HUD popper op nederst på skærmen:
  - [ ] Sky-blue accent (ikke rød)
  - [ ] "Lytter…" + tidstæller (`0.0 s` → `0.5 s` → ...)
  - [ ] Live waveform-bars reagerer på din stemme
- [ ] Sig en kort dansk sætning (fx "Hej, jeg tester Saga lige nu")
- [ ] Slip ⌥
  - [ ] HUD skifter til "Transskriberer" + shimmer-bars
  - [ ] Inden for ~1-2 sek: tekst dukker op i TextEdit ved cursor
- [ ] Verificer teksten er rimelig dansk (kan have små fejl, det er OK)

### First-time vs. warm performance

- [ ] **Første transcribe efter app-launch:** ~5-8 sek inference (CoreML JIT)
- [ ] **Anden transcribe og frem:** <1 sek for 5 sek audio (RTF ~0.15)

## Trin 5 — Status-menu

- [ ] Klik status-bar-ikon
- [ ] Popover åbner med:
  - [ ] State-row øverst (idle / Klar / sky-blue checkmark)
  - [ ] Canary-row: grøn dot + "Klar"
  - [ ] LM Studio-row: grøn dot + model-navn (hvis kørende), ellers orange
  - [ ] Permissions-row: grøn dot hvis begge er tilladt
  - [ ] "Seneste"-sektion med din test-transkription fra Trin 4
- [ ] Klik "Se alle…" → Historik-vindue åbner med fuld transkription

## Trin 6 — Settings

- [ ] Cmd+, eller klik "Indstillinger…" i popover
- [ ] Settings-vindue har 3 tabs: Generelt / Modes / Om
- [ ] Generelt:
  - [ ] Hotkey-picker (alle 5 muligheder)
  - [ ] LM Studio "Find igen"-knap virker
  - [ ] Liste over fundne endpoints med radio-button-valg
  - [ ] Permissions-rækker viser status

## Trin 7 — Persistens efter genstart

- [ ] Cmd+Q for at quit Saga
- [ ] Genåbn Saga via Spotlight
- [ ] Wizard åbner IKKE igen (firstRunComplete=true)
- [ ] Permissions stadig OK (TCC har vores cert pinned)
- [ ] Hotkey + transkribering virker uden setup

## Forventet performance på frisk M-series Mac

| Operation | Forventet tid |
|---|---|
| App-launch til status-bar-icon synlig | <1 sek |
| First-run wizard vises | ~1.5 sek |
| Cold model-load (CoreML JIT) | 8-22 sek |
| Warm transcribe (5 sek audio) | <1 sek |
| Status-popover åbner | <0.5 sek |
| RAM idle | ~80 MB Saga.app |
| RAM med model loaded | ~3.6 GB |

## Hvis noget fejler

Saml log via:
```bash
log show --last 10m --predicate 'subsystem == "dk.parthee.saga"' --info --debug > saga-log.txt
```

Send `saga-log.txt` + skærmbillede af problemet.

## Ship-criteria

DMG er klar til distribution når **alle checkbokse i Trin 1-7 er grønne** på en
frisk Mac (ideelt på en kollegas Mac som du IKKE har brugt til udvikling).
