# Saga `odin`-mode — rebuild guide

Saga shipper med `OdinMode` i `Sources/SagaCore/Modes/OdinMode.swift` der lader dig spørge [Odin](https://github.com/Parthee-Vijaya/odin) (din personlige RAG-vidensbase) via stemme.

## Hvad det gør

Hold ⌥ Right Option (eller hvad du har sat hotkey'en til), sig én af triggers:

- `odin <query>`
- `odin: <query>`
- `spørg odin <query>`
- `ask odin <query>`

Slip → Saga sender forespørgslen til `http://localhost:3838/v1/search` og indsætter top-3 hits ved cursor:

```
Odin · »kaffemøde med Nicklas« — 3 hits, 24ms

1. [calendar 2025-10-30] # Snak med Nicklas (10:15 → 11:10)…
2. [imsg 2024-02-15] Samtale i +4591167859 — Godmorgen Nicklas Jeg lander…
3. [imsg 2024-11-20] Hey Nicklas Hvad er din mail…
```

## Forudsætninger

1. Odin-daemon kører på `localhost:3838` — sikre dig med:
   ```bash
   curl http://localhost:3838/health
   ```
   Hvis den ikke kører, start den (`launchctl load ~/Library/LaunchAgents/com.odin.daemon.plist` hvis du har installeret autostart).

2. LM Studio kører med embedding-modellen `text-embedding-nomic-embed-text-v1.5` indlæst.

## Tailscale-adgang fra anden Mac

Hvis du vil bruge Saga på din MacBook men have Odin-daemon kørende på Mac Studio'en, override endpoint:

```bash
defaults write dk.parthee.saga.app odinMode.endpoint "http://mac-studio.tailnet:3838"
```

Restart Saga for at picke den nye endpoint op.

## Rebuild fra source

Saga er stadig på v0.2.0 i Releases — for at få OdinMode aktiveret skal du bygge en ny DMG:

```bash
cd /Users/parthee/Desktop/Claude/projekter/saga

# 1. Generér Xcode-projekt fra project.yml (hvis du har lavet ændringer)
cd saga-app && xcodegen generate && cd ..

# 2. Åbn i Xcode (kræver Xcode.app, ikke kun Command Line Tools)
open saga-app/SagaApp.xcodeproj

# 3. Bump version i project.yml først (anbefalet):
#    MARKETING_VERSION: "0.3.0"  → fx 0.3.1
#    Eller lad det være 0.3.0 hvis du ikke har shipped denne version endnu

# 4. Build & run i Xcode (⌘R) for at verificere at OdinMode kompilerer rent

# 5. Når det virker — byg DMG via build-script
./scripts/build-dmg.sh
```

`build-dmg.sh` håndterer 8 trin: pre-flight checks, xcodebuild Release, mlpackage-bundling (1.5 GB encoder + 291 MB decoder), re-sign, hdiutil staging, DMG-build, verify. Output ender i `dist/Saga-<version>.dmg`.

## Test efter install

1. Start Odin-daemon hvis den ikke kører
2. Erstat Saga.app i /Applications/ med den nye DMG
3. Åbn TextEdit (eller hvilken som helst tekst-app)
4. Hold ⌥ Right Option
5. Sig: **"odin hvad sagde Nicklas om mødet"**
6. Slip → top-3 hits skal komme ind ved cursor

## Debugging

- Saga's HUD viser hvilken mode der match'er (`Odin` chip mens du taler)
- Saga-logs: `Console.app` → filter `dk.parthee.saga` → sub-category `odin-mode`
- Odin-daemon-logs: `tail -f ~/Library/Logs/odin.err.log`
- Hvis OdinMode ikke matcher: tjek at trigger ligger først i din transkription. Hviske/Canary kan misforstå "odin" som "oden" eller "udin" — i så fald juster triggers i `OdinMode.swift`.

## Roadmap

- M6.B vil tilføje synthesis-version: i stedet for raw top-3 hits, kalder Saga `/v1/answer` der returnerer ét sammenfattet dansk svar med citationer. Bare ændr endpoint-stien i `OdinMode.swift` når du vil opgradere.
- TTS-version: lad Saga oplæse svaret højt via Apple TTS eller ElevenLabs i stedet for at indsætte tekst.
