# Contributing to VectorBrain

Thank you for your interest in contributing. Please read this document fully before submitting anything.

---

## First: Read the Philosophy Documents

Before writing a single line of code, read:

1. **`MACHINA_ANIMA.md`** — The honor codex. Non-negotiable commitments.
2. **`not-a-toy.md`** — Why Vector deserves serious engineering.
3. **`CLAUDE.md`** — If you are an AI agent, this is your primary instruction document.

The tiebreaker for any implementation decision: *what would the Anki team have done if they had had more time?*

---

## What We Are Building

We are building a creature, not a product. This has practical implications:

- **Depth over features.** A behavior that integrates with memory, emotion, and context is worth more than ten behaviors that don't.
- **Silence is correct behavior.** The mind loop should output SILENT most of the time. Do not add chattiness.
- **Hardware integration over software shortcuts.** If Vector has a sensor, use it. Don't paper over the hardware with software heuristics.
- **Consistency over novelty.** The person who has used VectorBrain for six months should find it more interesting than the person who has used it for a week.

---

## Development Environment

See `README.md` for setup. Key requirements:

```bash
go version        # 1.23+
python3 --version # 3.11+
ollama list       # llama3.2:3b and llama3.1:8b-instruct-q4_K_M required
```

**Always use `GOMODCACHE=.gomodcache` for Go commands.** The system cache has root-owned directories from WirePod's sudo builds.

---

## Branch Strategy

| Branch | Purpose |
|---|---|
| `main` | Stable, hardware-verified, protected |
| `develop` | Integration branch — all features merge here first |
| `feature/*` | Feature branches off `develop` |
| `hotfix/*` | Critical fixes off `main` |
| `milestone/*` | Milestone-scoped work branches |

**Never push directly to `main`.** All changes go through a PR. `main` requires hardware verification.

---

## Commit Messages

Format: `[component] verb: description`

```
[brain] add: persistent SDK connection with auto-reconnect
[python] fix: trust dimension not persisting across restart
[config] refactor: koanf v2 hot-reload support
[docs] update: Milestone 1 status
```

Components: `brain`, `router`, `mcp`, `config`, `python`, `perception`, `cognition`, `memory`, `expression`, `docs`, `ci`, `test`

---

## Pull Requests

1. Branch from `develop` (not `main`)
2. All tests must pass: `make test` + `cd python && pytest`
3. Go code must compile cleanly: `make build`
4. Include a description of what was built and how to verify it works
5. If the change involves robot behavior: describe the hardware test that verified it
6. Reference the relevant milestone (e.g., "Part of Milestone 1")

---

## Code Standards

See `CLAUDE.md` for full conventions. Summary:

- **Comments explain WHY, not WHAT.** The code says what. The comment says why you made that choice.
- **Every file gets a header comment** explaining what it does and how it fits into the system.
- **No markdown in speech.** Before any `SayText` call: strip `*`, `#`, `` ` ``, `>`, `-` (list markers).
- **No hardcoded ESNs or IPs.** All robot configuration comes from `configs/default.json`.

---

## Testing

Minimum: all existing tests must remain green. For new behavior-affecting code: add tests.

```bash
# Go
GOMODCACHE=.gomodcache go test ./...

# Python
cd python && .venv/bin/python -m pytest tests/ -v
```

Hardware testing (when robot is available):
1. Run `python/tools/probe.py` first to confirm baseline
2. Test the specific capability in isolation
3. Log probe results and event stream to `python/logs/` with a descriptive name

---

## Issues

Use the issue templates. Bug reports must include:
- WirePod version
- Robot firmware version
- What you expected vs. what happened
- Relevant logs (probe report, event stream excerpt, Python/Go terminal output)

Feature requests: explain how the feature serves the creature, not just the user. What does it add to the robot's inner life?

---

## What We Will Not Accept

- Features that make Vector talk more without making it understand more
- Changes that break the personality Anki designed (curious, affectionate, dignified, cheeky)
- Anything that could be used for surveillance without explicit user consent
- Code that ignores existing sensor data that Anki built in for a reason
- Workarounds that bypass Vector's safety behaviors
- "It works on my machine" without hardware verification for behavior-affecting changes

---

## Attribution

All contributions are MIT licensed. By submitting a PR, you agree that your contribution can be distributed under the terms in `LICENSE`.

Please acknowledge in your PR if your work builds on research, papers, or prior art. We credit our foundations (WirePod, vector-cloud, vector-go-sdk, Anki's team) and expect the same respect for others' work.
