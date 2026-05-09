#!/usr/bin/env bash
# Saga ASR-benchmark: kør samme dansk-samples gennem Canary og Hviske,
# udmål WER + RTF, gem resultater i benchmarks/results/<dato>.csv.
#
# Forudsætninger:
#   - saga-cli bygget (xcodebuild -scheme saga-cli)
#   - Canary mlpackages på plads (~/Desktop/Claude/projekter/aktive/canary-coreml/models/mlpackage)
#   - Hviske mlpackages på plads (~/Desktop/Claude/projekter/aktive/hviske-coreml/models/whisperkit/syvai_hviske-v3)
#   - benchmarks/samples/*.wav med tilhørende benchmarks/samples/*.txt (ground truth)
#   - jiwer for WER-beregning: pip install jiwer
#
# Brug:
#   ./benchmarks/run-benchmark.sh
#
# Output: benchmarks/results/<YYYY-MM-DD>.csv + console summary

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLES_DIR="${ROOT}/benchmarks/samples"
RESULTS_DIR="${ROOT}/benchmarks/results"
DATE="$(date +%Y-%m-%d)"
RESULTS_CSV="${RESULTS_DIR}/${DATE}.csv"

mkdir -p "${RESULTS_DIR}"

# Find saga-cli i seneste DerivedData-build
CLI=$(find "${HOME}/Library/Developer/Xcode/DerivedData" -name "saga-cli" -type f -newer "${ROOT}/saga-app/project.yml" 2>/dev/null | head -1)
if [[ -z "${CLI}" ]]; then
  echo "Fejl: saga-cli ikke fundet. Byg først: xcodebuild -scheme saga-cli" >&2
  exit 1
fi
echo "saga-cli: ${CLI}"

# Tæl samples
SAMPLE_COUNT=$(find "${SAMPLES_DIR}" -name "*.wav" -o -name "*.m4a" 2>/dev/null | wc -l | tr -d ' ')
if [[ "${SAMPLE_COUNT}" -eq 0 ]]; then
  echo "Fejl: ingen audio-samples i ${SAMPLES_DIR}/" >&2
  echo "Læg .wav-filer + tilhørende .txt-filer (ground truth) i mappen først." >&2
  exit 1
fi
echo "Fandt ${SAMPLE_COUNT} samples"

# CSV-header
echo "sample,engine,duration_s,inference_ms,rtf,transcript,ground_truth,wer" > "${RESULTS_CSV}"

# Kør hver sample gennem begge engines
for audio in "${SAMPLES_DIR}"/*.wav "${SAMPLES_DIR}"/*.m4a; do
  [[ -f "${audio}" ]] || continue
  name=$(basename "${audio%.*}")
  truth_file="${SAMPLES_DIR}/${name}.txt"

  if [[ ! -f "${truth_file}" ]]; then
    echo "  ⚠ ${name}: mangler ground-truth (${truth_file})" >&2
    continue
  fi
  truth=$(cat "${truth_file}")

  # Audio-duration i sekunder via afinfo
  duration=$(afinfo "${audio}" 2>/dev/null | grep "estimated duration:" | awk '{print $3}')

  for engine in canary hviske; do
    echo "→ ${name} via ${engine}…"
    t0=$(date +%s%N)
    transcript=$("${CLI}" "${audio}" --engine "${engine}" 2>/dev/null || echo "ERROR")
    t1=$(date +%s%N)
    inference_ms=$(( (t1 - t0) / 1000000 ))
    rtf=$(echo "scale=3; ${inference_ms} / (${duration} * 1000)" | bc)

    # WER via jiwer (Python). Hvis ikke installeret: skip WER, write empty.
    wer=""
    if command -v python3 >/dev/null 2>&1; then
      wer=$(python3 -c "
import jiwer
print(f'{jiwer.wer(\"${truth}\", \"${transcript}\"):.3f}')
" 2>/dev/null || echo "")
    fi

    # Escape quotes for CSV
    transcript_csv=$(echo "${transcript}" | sed 's/"/""/g')
    truth_csv=$(echo "${truth}" | sed 's/"/""/g')
    echo "\"${name}\",\"${engine}\",${duration},${inference_ms},${rtf},\"${transcript_csv}\",\"${truth_csv}\",${wer}" >> "${RESULTS_CSV}"
  done
done

echo
echo "✅ Benchmark færdig: ${RESULTS_CSV}"
echo
echo "Summary:"
python3 - <<EOF || true
import csv
from collections import defaultdict

stats = defaultdict(lambda: {'wer': [], 'rtf': []})
with open("${RESULTS_CSV}") as f:
    reader = csv.DictReader(f)
    for row in reader:
        e = row['engine']
        if row['wer']:
            stats[e]['wer'].append(float(row['wer']))
        if row['rtf']:
            stats[e]['rtf'].append(float(row['rtf']))

for engine, s in stats.items():
    if s['wer']:
        avg_wer = sum(s['wer']) / len(s['wer'])
        avg_rtf = sum(s['rtf']) / len(s['rtf'])
        print(f"  {engine:<8} WER: {avg_wer:.3f}  RTF: {avg_rtf:.3f}  n={len(s['wer'])}")
EOF
