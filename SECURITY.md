# Security Policy

## Supported Versions

Security fixes are applied to the latest released version on the `main` branch. Older versions are not maintained.

| Version | Supported          |
| ------- | ------------------ |
| Latest `main` / most recent release | ✅ |
| Older releases | ❌ |

## Reporting a Vulnerability

**Please do not file public GitHub issues for security vulnerabilities.**

Saga runs locally and processes audio + cursor input — vulnerabilities could expose user dictation history, allow arbitrary text injection, or escalate accessibility-permission abuse. Take care.

### How to report

Send a private email describing the issue to the maintainer (see GitHub profile of [@Parthee-Vijaya](https://github.com/Parthee-Vijaya) for current contact). Include:

- A clear description of the issue and its security impact
- Steps to reproduce (or proof-of-concept)
- Affected version(s) (commit SHA or release tag)
- Your name/handle if you'd like to be credited (optional)

If your report involves a third-party dependency (CanaryKit, LM Studio, etc.), please indicate that — we may need to coordinate with the upstream project.

### What to expect

- **Initial response**: within 5 business days
- **Triage and severity assessment**: within 14 days
- **Fix timeline**: depends on severity, typically 30–90 days
- **Credit**: reporters are credited in release notes unless they request anonymity

### Scope

In scope:

- Saga.app itself (Swift/SwiftUI code)
- `scripts/build-dmg.sh` and other release tooling
- Persistence layer (`~/Library/Application Support/Saga/`)
- HTTP bridges to LM Studio (input validation, response handling)

Out of scope:

- Vulnerabilities in LM Studio, NVIDIA Canary, or other third-party software
- Issues requiring physical access to an unlocked Mac
- Social engineering attacks against maintainers
- Theoretical issues without concrete impact

### Privacy considerations

Saga does not transmit audio off-device. If you discover a way to cause Saga to leak audio, transcripts, or screenshots over the network unintentionally, that is **always** in scope and considered high severity.
