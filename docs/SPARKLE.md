# Sparkle Auto-Update Setup

Saga's auto-update er bygget på [Sparkle 2.x](https://sparkle-project.org/). Dette dokument beskriver hvad du skal gøre én gang for at gøre det operationelt — koden i appen er klar.

## Ét-gangs setup

### 1. Generér EdDSA keypair

Sparkle 2 bruger EdDSA-signering for at sikre at downloads ikke er manipuleret. Du genererer keypair én gang og bevarer den private nøgle sikkert (Keychain anbefales — Sparkle's CLI gør det automatisk).

```bash
# Hent Sparkle's CLI-tools (én gang)
curl -L "https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.6.4.tar.xz" -o sparkle.tar.xz
tar xf sparkle.tar.xz
cd Sparkle-*/bin

# Generér keypair — privat nøgle gemmes i Keychain, public printes til stdout
./generate_keys
```

Output ser sådan ud:
```
A key has been generated and saved in your keychain. Add the following EdDSA key to your Info.plist:
SUPublicEDKey: AbCdEf123...
```

### 2. Indsæt public key i `saga-app/project.yml`

Find linjen:
```yaml
SUPublicEDKey: "REPLACE_WITH_BASE64_PUBLIC_KEY_FROM_generate_keys"
```

Erstat placeholder med din public key.

### 3. Vælg appcast-host

`SUFeedURL` peger pt. på `https://parthee-vijaya.github.io/saga-mac/appcast.xml`. To muligheder:

**Option A: GitHub Pages (gratis)**
1. Opret `gh-pages` branch (eller brug `docs/` mappe på main)
2. Læg `appcast.xml` der
3. Aktivér GitHub Pages i repo settings
4. URL bliver `https://<bruger>.github.io/<repo>/appcast.xml`

**Option B: Egen server**
- Hostr på hvilken som helst HTTPS-server
- Opdat `SUFeedURL` i `project.yml`

### 4. Generér appcast.xml ved hver release

Efter `./scripts/build-dmg.sh` har produceret en signed DMG:

```bash
# Sparkle's CLI signerer DMG'en og laver appcast-entry
./Sparkle-*/bin/generate_appcast \
  --download-url-prefix "https://github.com/Parthee-Vijaya/saga-mac/releases/download/v0.4.0/" \
  dist/

# Output: dist/appcast.xml
```

Push den til din chosen host (gh-pages branch, fx).

### 5. Verificér

I Saga: **Settings → Om → Auto-update → Tjek nu**. Sparkle henter din appcast, sammenligner versions, og prompter hvis ny version findes.

## Hvor Sparkle's logik findes i koden

- `saga-app/Sources/SagaCore/Updates/UpdateManager.swift` — wrapper omkring `SPUStandardUpdaterController`
- `saga-app/project.yml` — Info.plist keys: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`
- `saga-app/Sources/SagaCore/UI/Settings/AboutTab.swift` — `UpdateCard` med toggle og "Tjek nu"

## Slim-DMG distribution (~150 MB i stedet for 1.7 GB)

Saga understøtter to distribution-modeller:

1. **Bundled** (default): mlpackages er pakket ind i `Saga.app/Contents/Resources/mlpackage/`. DMG ~1.7 GB.
2. **Slim**: mlpackages downloades on-demand første gang appen starter. DMG ~150 MB.

### Byg slim-DMG

```bash
SAGA_SLIM=1 ./scripts/build-dmg.sh
# Output: dist/Saga-X.Y.Z.dmg (~150 MB)
```

### Hvor henter app'en mlpackages fra?

`ModelDownloader.defaultBaseURL` peger pt. på `https://github.com/Parthee-Vijaya/canary-coreml/releases/download/v1.0.0`. Forventer disse asset-navne:

- `CanaryEncoder.mlpackage.zip` (~500 MB komprimeret)
- `CanaryDecoderLM.mlpackage.zip` (~100 MB)
- `CanaryPreprocessor.mlpackage.zip` (~1 MB)

### Forbered canary-coreml release-assets

```bash
# I canary-coreml repoet:
cd models/mlpackage

# Pak hver mlpackage som zip (mlpackages er bundles = mapper)
for pkg in CanaryEncoder.mlpackage CanaryDecoderLM.mlpackage CanaryPreprocessor.mlpackage; do
  zip -rq "${pkg}.zip" "${pkg}"
done

# Upload som release assets
gh release create v1.0.0 \
  --title "Canary CoreML v1.0.0" \
  --notes "Initial release for Saga slim-DMG distribution" \
  --repo Parthee-Vijaya/canary-coreml \
  CanaryEncoder.mlpackage.zip \
  CanaryDecoderLM.mlpackage.zip \
  CanaryPreprocessor.mlpackage.zip
```

### Bruger-oplevelsen ved slim-DMG

1. Bruger downloader ~150 MB DMG fra GitHub Releases
2. Træk Saga.app til Applications
3. Første launch: Saga detekterer manglende mlpackages
4. Setup-wizard viser et nyt step: "Download speech-modeller (~1.8 GB)"
5. Progress-bar med per-fil status
6. Når færdig → normal app-start
7. Modellerne ligger nu i `~/Library/Application Support/Saga/Models/`
8. Næste launches: instant — Canary loader fra disk

### Brugerkontroller (Settings → Om)

- **Speech-modeller card** viser: status (Klar/Mangler), disk-usage, "Slet"-knap (med confirm)
- Hvis bruger sletter: næste launch trigger nyt download

### Failure-modes

- **Netværksfejl midt under download**: ModelDownloader bevarer allerede-hentede pakker; resume ved næste forsøg.
- **GitHub Releases nede**: Der er ingen fallback i v1. Bruger venter eller bruger bundled DMG.
- **Disk fuld**: ModelDownloader fejler med klar fejlmeddelelse i UI.

## Roadmap-noter

- Streaming-extract (parallel download + unzip) kan komme i v2 hvis det viser sig at være langsomt
- Self-hosted model-mirror kan tilføjes som UserDefaults-overstyring (`modelDownloader.baseURL`) — koden understøtter det allerede
