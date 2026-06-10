# Saga ASR-benchmarks

Side-by-side WER + RTF for Canary vs Hviske på dine egne dansk-samples.
Bruges som F7-decision-point: er Hviske ≥3% bedre end Canary på samtale-data
før vi gør den til default-engine?

## Forudsætninger

```bash
# 1. Installér WER-tool
pip install jiwer

# 2. Byg saga-cli (én gang)
cd saga-app && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SagaApp.xcodeproj -scheme saga-cli -configuration Debug build

# 3. Verificér ASR-modellerne er på plads
# (repos forventes klonet side-om-side med saga — juster paths efter dit setup)
ls ../canary-coreml/models/mlpackage/
ls ../hviske-coreml/models/whisperkit/syvai_hviske-v3/
```

## Tilføj samples

Læg dansk audio + ground-truth i `samples/`:

```
benchmarks/samples/
├── samtale-1.wav
├── samtale-1.txt    ← korrekt transcript (ground truth)
├── opslag.wav
├── opslag.txt
└── ...
```

Anbefalet: 5-10 samples på 5-30 sekunder hver. Mix af:
- Naturlig samtale (Saga's primære use-case)
- Højtlæsning (vis Canary's clean-read styrke)
- Fag-terminologi (test vocabulary-coverage)
- Code-switching dansk/engelsk

## Kør benchmark

```bash
./benchmarks/run-benchmark.sh
```

Output: `benchmarks/results/<dato>.csv` + console-summary med gennemsnits-WER og RTF per engine.

## Beslutnings-kriterium

| Hviske vs Canary | Anbefaling |
|---|---|
| Hviske ≥3% bedre WER på samtale | Gør Hviske til default for dansk |
| Hviske 1-3% bedre | Behold Canary som default, lad Hviske være opt-in |
| Hviske ≤1% bedre eller værre | Drop hviske-coreml-projektet — kompleksitet ikke værd det |

## Eksisterende resultater

| Dato | Samples | Canary WER | Hviske WER | Vinder |
|---|---|---|---|---|
| _Ingen kørsler endnu_ | — | — | — | — |

(Opdateres efter hver F7-iteration.)
