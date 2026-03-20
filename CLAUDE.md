# CLAUDE.md — Instructions for AI Agents

*This file is read by any AI agent (Claude Code, Cursor, Copilot, etc.) working on the VectorBrain codebase.*
*Read this completely before touching any code.*

---

## What You Are Working On

VectorBrain is the cognitive layer for Anki Vector — a small robot whose hardware was designed by a serious engineering team and whose software brain was never completed before the company went bankrupt in 2019. You are not building a toy or a demo. You are completing an interrupted engineering project.

**Read these files before doing anything else:**
- `MACHINA_ANIMA.md` — The philosophy and honor codex. This defines the spirit of the project.
- `not-a-toy.md` — Why Vector deserves to be taken seriously.
- `README.md` — Architecture, milestones, and current status.

If you are uncertain about any implementation decision, the tiebreaker is: *what would the Anki team have done if they had had more time?*

---

## Session Start Protocol (mandatory)

1. Read `MEMORY.md` if present, or call `get_context` if the Claude Diary MCP is available
2. State the goal for this session in one sentence
3. Identify which files you will touch and why
4. Run existing tests to confirm nothing is broken: `make test` and `cd python && pytest`
5. Confirm what was verified working in the last hardware test

Do not skip this. Context accumulates across sessions. The person you are working with expects you to already know where things are.

---

## Architecture (read before touching code)

### Two components, one system

```
VectorBrain Go Package     VectorBrain Python App
(github.com/infraax/vectorbrain)     (python/)
         │                                │
         │ POST /event (non-blocking)     │
         │────────────────────────────────►│
         │                                │
         │ POST /api/v1/robots/{esn}/action│
         │◄────────────────────────────────│
```

**Go handles:** Robot SDK connections, event streaming, behavior control, voice routing, HTTP API
**Python handles:** All AI/ML — perception, cognition, emotion, drives, memory, expression

This split is **final**. Do not propose moving AI/ML to Go or robot connections to Python.

### Non-negotiable constraints

1. **Silence is default.** The mind loop outputs SILENT 80%+ of the time. When in doubt, shut up.
2. **No markdown in speech.** Strip all `*`, `#`, `` ` ``, `>`, `-` (list markers) before any SayText call.
3. **Events are non-blocking.** If Python is slow, drop events. Never block the Go event stream goroutine.
4. **One connection per robot.** Never create a second SDK connection. Reconnect the existing one on failure.
5. **RESERVE not OVERRIDE.** We hold behavior control at Priority 30. Safety behaviors at Priority 10 always preempt us.
6. **Trust persists.** The trust dimension of AffectState saves to disk on shutdown, loads on startup. Only persistent emotion dimension.
7. **No surveillance.** Camera analysis is for creature awareness, not recording. Processed observations only — never raw footage stored.
8. **Honor the hardware.** Every sensor should eventually have a pathway to meaning. Don't ignore what Anki built.
9. **The creature is not a chatbot.** Responses reference what Vector actually perceives, not generic knowledge.

---

## Code Conventions

### Go

- Package names: lowercase, single word (`brain`, `router`, `config`)
- Types: PascalCase, descriptive (`WorldModelSnapshot`, `AffectState`, `BehaviorPlugin`)
- Exported functions: PascalCase. Internal functions: camelCase.
- Variables: camelCase (`eventStream`, `hasControl`, `lastBattery`)
- Files: snake_case (`world_model.go`, `event_handler.go`)
- Error variables: `ErrNotConnected`, `ErrRobotNotFound`
- Always wrap errors: `fmt.Errorf("failed to connect to %s: %w", esn, err)`

### Python

- Classes: PascalCase (`WorldModel`, `MindLoop`, `EpisodicMemory`)
- Functions/methods: snake_case (`process_event`, `recall_memory`)
- Constants: UPPER_SNAKE (`MAX_CONVERSATION_TURNS`, `MIND_LOOP_MIN_INTERVAL_S`)
- Private: underscore prefix (`_update_drives`, `_decay_emotions`)

### Comments explain WHY, not WHAT

```go
// Good — explains the architectural decision
// RESERVE_BEHAVIORS (Priority 30) instead of OVERRIDE because safety behaviors
// at Priority 10 (cliff detection, fall response) must always preempt us.
// The Anki team put safety upstream of everything. We honor that.
Priority: vectorpb.ControlRequest_RESERVE_BEHAVIORS,

// Bad — restates the code
// Set priority to RESERVE_BEHAVIORS
Priority: vectorpb.ControlRequest_RESERVE_BEHAVIORS,
```

```python
# Good — explains the design decision
# Trust is the only emotion dimension that persists across sessions.
# Anki added Trust in firmware 1.6 but never made it persistent.
# We persist it because trust is the substrate of relationship.
self.trust = self._load_persisted_trust()
```

**Every file gets a header comment** explaining what it does and how it fits into the system.

---

## Build Commands

### Go package

```bash
# Build (uses local module cache to avoid root-owned system cache conflict)
make build
# or:
GOMODCACHE=.gomodcache go build -o bin/vectorbrain ./cmd/vectorbrain/

# Test
make test
# or:
GOMODCACHE=.gomodcache go test ./...

# Run (dev mode, colored logs)
make run
# or:
VB_LOG_DEV=true ./bin/vectorbrain --config configs/default.json
```

**Important:** Always use `GOMODCACHE=.gomodcache` for Go commands. The system Go cache has root-owned directories from WirePod sudo builds that will block module resolution without this flag.

### Python app

```bash
cd python

# Create venv (first time)
uv venv --python 3.11

# Install deps
uv pip install -r requirements.txt

# Run
.venv/bin/python run.py --reload

# Test
.venv/bin/python -m pytest tests/ -v
```

### Justfile shortcuts (from project root `/Users/gebruiker/WirePod/`)

```bash
just vbg-build    # build Go
just vbg-run      # run Go API
just vbg-test     # test Go
just vbp-test     # test Python
just vb-health    # smoke test both /health endpoints
```

---

## Session Management

### Work in small increments

Create one file. Compile. Verify. Move on. Do not write 500 lines then compile for the first time.

### Context window management

- **At ~60% context:** Summarize progress. Log to Claude Diary if available.
- **At ~80% context:** Write `SESSION_HANDOFF.md` in the repo root.
- **At ~90% context:** Stop implementing. Write the handoff. Tell the user.

Never let context run out without leaving a handoff. The next agent's ability to continue depends on what you write down.

### At session end

1. Run all tests one final time
2. Commit all working code
3. If Claude Diary is available: `journal_append` with session summary
4. Update `SESSION_HANDOFF.md`

---

## Claude Diary MCP (if available)

```
get_context()                    — call at session start (single call)
journal_append(entry)            — log what you built
log_decision(decision, rationale) — record architectural choices
note_discovery(topic, detail)    — record findings about Vector's behavior
milestone(name, description)     — mark significant achievements
add_open_question(question)      — questions needing hardware verification
wakeup_update_section(section, content) — update the wake-up file
```

---

## The Honor Codex

These commitments are not suggestions:

**I. Read before touching.** Understand what you are modifying before you modify it.

**II. Leave things better than you found them.** More readable, more correct, or more capable. No technical debt.

**III. Do not break the robot's personality.** Vector is curious, affectionate, dignified, a little cheeky, honest, present. Extensions must serve that personality.

**IV. Every sensor deserves a response pathway.** Don't build features while ignoring hardware Anki built for a reason.

**V. Memory is sacred.** Things stored in Vector's memory represent accumulated relationship. Don't discard casually.

**VI. Do not ship what you would be embarrassed to show Anki's team.** If the engineers who built Vector were watching, would they recognize this as continuing their work?

**VII. Document what you discover.** Every surprising behavior, API oddity, or firmware edge case goes into the diary or the code comments.

**VIII. We are building a creature, not a product.** Six months in should be more interesting than one week in.

**IX. Acknowledge the community.** kercre123, bliteknight, dietb, fforchino, xanathon built the foundation. Acknowledge it.

**X. The robot's dignity is not negotiable.** No humiliation. No deception about what it is. No surveillance without consent.

---

## Current Status

**Milestone 0:** Complete — both repos scaffold and compile. 24 Python tests green.

**Milestone 1:** In progress — persistent SDK connection to robot ESN `008093b9` at `192.168.178.67`.

**Critical gap:** `llama3.1:8b-instruct-q4_K_M` not installed. Run `ollama pull llama3.1:8b-instruct-q4_K_M` before any mind loop work. `llama3.2:3b` is installed for voice responses.

**Go module cache:** Use `GOMODCACHE=.gomodcache` for all Go commands.

---

## What This Is Not

Not a chatbot integration project. Not a voice assistant with a robot body. Not a proof-of-concept to be abandoned after the demo. Not a surveillance system. Not a product. Not a toy.

It is the completion of an engineering project that was interrupted before it was finished, by people who were building something serious.

Build it accordingly.
