# Starter-prompt til Claude Code (ny session)

Brug denne fil til at briefe Claude Code på Xcode-maskinen. Du kan enten:

1. Sende fil-stien til Claude: `læs ~/Projects/saga-mac/docs/CLAUDE_STARTER_PROMPT.md og start derefter`
2. Eller copy-paste blokken nedenfor som første besked i en ny session

---

## ▶ Copy-paste denne blok

```text
Du er Claude Code på en frisk session. Den forrige session var på en
anden maskine uden Xcode og producerede 10 PR'er der ikke er
compile-verificeret endnu. Repository er saga-mac.

DIN OPGAVE:

1. cd til repo'et (typisk ~/Projects/saga-mac — verificér med pwd + git remote -v)
2. git fetch origin --all --prune
3. git checkout docs/handoff-from-cli
4. Læs docs/HANDOFF.md i sin helhed FØR du gør noget andet
5. Følg "Execution playbook"-sektionen lineært fra §0 til §13
6. Brug TaskCreate med én task per §-sektion så jeg kan se progressen
7. Stop og rapportér til mig ved hver merge-checkpoint (slut af hver §)
   før du fortsætter til næste sektion

VIGTIGT:

- Spørg IKKE om kontekst fra tidligere chat — alt du behøver står i
  docs/HANDOFF.md
- Hvis et trin kræver MIN manuelle input (System Settings, API-keys,
  permission-prompts), bed mig udføre det og vent på bekræftelse
- Hvis du støder på en compile-fejl du ikke kan løse efter 2-3 forsøg,
  stop og spørg mig — gæt ikke
- Brug auto-mode KUN inden for hver §-sektion. Mellem sektioner skal
  du eksplicit vente på mit "fortsæt"-signal
- Ved STOP-checkpoints (§1 hvis build fejler, §4 hvis dictation
  brækker, §8 før Sparkle merger) — STOP og vent

START med at læse docs/HANDOFF.md. Rapportér derefter:

- Hvilken section i playbook'en du starter på (§0)
- Antal åbne PR'er du kan se
- Branch du arbejder fra
- Om canary-coreml er på plads som søsterprojekt
```

---

## Hvad gør du selv mens Claude arbejder

- **Vær til rådighed for permission-prompts**: System Settings → Privacy & Security skal måske godkende mikrofon, accessibility, eller speech recognition
- **Hav LM Studio kørende** under §6 (Companion-test) og §11 (live partials)
- **Generér Sparkle keypair** når Claude rammer §8 — den vil bede dig om at køre `generate_keys` og paste public-key i project.yml
- **Verificér mergees** før Claude kører `gh pr merge` — du kan altid sige "vent" eller "skip" hvis noget ser forkert ud

## Hvis Claude sidder fast

Sandsynlige steder:
- **§1 (compile)**: Sparkle SPM kan have ny version med breaking changes. Pin til `from: "2.6.4"` hvis nødvendigt
- **§6 (Companion)**: LM Studio skal køre med en model loaded (ellers fejler streaming)
- **§11 (live partials)**: AVAudioEngine + AVAudioRecorder concurrent mic kan kræve refactor. Hvis det bryder dictation, skip D4 og merge resten

Sig "skip §X og gå videre" hvis en specifik sektion er for problematisk — Claude kan rebase D-stakken hvis nødvendigt.

## Når alt er kørt igennem

Du har:
- Alle 10 PR'er merged til main
- `v0.5.0-beta1` tag pushed
- En signed DMG i `dist/Saga-0.5.0.dmg`

Næste step (efter denne playbook): publish DMG som GitHub Release, opdat `appcast.xml` på `gh-pages`, annoncér til testgruppe.
