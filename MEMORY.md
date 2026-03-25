# VectorBrain — Project Memory

*This file is updated by agents at session end. It is the first thing any new agent reads.*
*Keep it tight — max 200 lines. Every line earns its place.*

---

## Current Milestone

**M1 — Robot Connection** (in progress)
Goal: Persistent SDK connection to ESN `008093b9` at `192.168.178.67`, events streaming, behavior control held.
Verify: `GET /api/v1/robots/008093b9/state` shows live battery.

---

## What Is Working

- Go package builds cleanly (`make build`)
- Python app: 24 tests passing (`cd python && pytest`)
- `/health` endpoint responds on both Go (:8070) and Python (:8090)
- Agent workflow system live: checkin/checkout/status/claim/release scripts
- GitHub labels + milestone structure set up (run `scripts/setup-labels.sh` to apply)

---

## What Is Not Working Yet

- No `vector-go-sdk` dependency in `go.mod` — M1 cannot start without this
- `llama3.1:8b-instruct-q4_K_M` not installed on robot host machine
- Voice endpoint returns placeholder text (real LLM call is M4)
- No SDK connection manager, brain registry, or event bridge in Go yet

---

## Known Traps

- **Always use `GOMODCACHE=.gomodcache`** for all Go commands. The system Go cache has root-owned dirs from WirePod sudo builds that block module resolution.
- **No markdown in speech.** Strip `*`, `#`, `` ` ``, `>`, `-` before any SayText call.
- **Events are non-blocking.** If Python is slow, drop the event. Never block the Go event stream goroutine.
- **One connection per robot.** Never create a second SDK connection.
- **`RESERVE_BEHAVIORS` not `OVERRIDE`** — Priority 30. Safety behaviors at Priority 10 always preempt.

---

## Robot Hardware

- ESN: `008093b9`
- IP: `192.168.178.67`
- WirePod: running separately (must be up before VectorBrain starts)
- Last hardware test: **none yet** (Milestone 0 only verified via compile + /health)

---

## Architecture Decisions (final — do not revisit without strong reason)

- **Go handles** robot SDK connections, event streaming, behavior control, HTTP API (:8070)
- **Python handles** all AI/ML — perception, cognition, emotion, drives, memory, expression (:8090)
- **LLM split**: `llama3.2:3b` for voice responses (<1s), `llama3.1:8b-instruct-q4_K_M` for mind loop
- **Silence is default** — mind loop outputs SILENT 80%+ of the time
- **Trust persists** — only emotion dimension saved across sessions

---

## Active Agents

*Updated by agent-checkin.sh and agent-checkout.sh. See agent-sessions.jsonl for full log.*

Run `./scripts/agent-status.sh` for live view.

---

## What the Next Agent Should Do

1. Run `./scripts/setup-labels.sh` if GitHub labels aren't set up yet (needs `GITHUB_TOKEN`)
2. Pick up the first `status: ready` issue from the board
3. Use `./scripts/agent-claim.sh ISSUE --agent ... --model ... --client ...` to claim it
4. The first ready issues will be M1 tasks: adding `vector-go-sdk` to `go.mod` and building the connection manager

---

## Open Questions (need hardware to answer)

- Which exact fields does `robot_state` event contain on firmware version on ESN `008093b9`?
- Does `RESERVE_BEHAVIORS` reliably hold on this firmware version or does it need periodic re-acquisition?
- What is the reconnection behavior when WirePod restarts mid-session?

---

## Issue Map (quick reference)

| # | Type | Title | Status |
|---|---|---|---|
| #4 | epic | M1 — Robot Connection | open |
| #5 | epic | M2 — Command Execution | open |
| #6 | epic | M3 — Python-Go Bridge | open |
| #7 | epic | M4 — First Voice Conversation | open |
| #8 | epic | M5 — WirePod Integration | open |
| #9 | epic | M6 — Mind Loop | open |
| #10 | epic | M7 — Memory | open |
| #11 | epic | M8 — Full Perception + MCP | open |
| #12 | epic | VectorFriends | open |
| #13 | epic | Infrastructure / Agent Workflow | open |
| #14 | task | Add vector-go-sdk to go.mod | **READY — claim this first** |
| #15 | task | BrainRegistry | ready (needs #14) |
| #16 | task | ConnectionManager | ready (needs #14, #15) |
| #17 | task | RESERVE_BEHAVIORS control | ready (needs #16) |
| #18 | task | EventStream | ready (needs #16) |
| #19 | task | GET /robots/{esn}/state | ready (needs #15, #18) |
| #20 | epic | M0 — Scaffolding | **closed — complete** |
| #21 | task | agent-brief.sh | ready |
| #22 | task | issue-context.sh | ready |
| #23 | task | .claude/settings.json hook | ready (needs #21) |
| #24 | task | GitHub Actions CI | ready |

**First task for any new agent:** claim #14 (add vector-go-sdk) — it unblocks all of M1.

---

## Session History Summary

| Date | Agent | Scope | Outcome |
|---|---|---|---|
| 2026-03-25 | claude-code-web | bootstrap/agent-workflow-and-backlog | Multi-agent workflow system + 21 GitHub issues created (epics #4–13, M1 tasks #14–19, infra tasks #21–24) |

---

| 2026-03-25 | claude-code-web | bootstrap/phase2-orchestration-ci | Phase 2 complete: orchestrate.sh, agent-ci.yml, session-linker.yml, MEMORY.md au |
*Last updated: 2026-03-25 by claude-code-web / session end*
