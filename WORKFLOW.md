# VectorBrain Multi-Agent Workflow

*How multiple AI agents (different models, clients, sessions) collaborate on VectorBrain without colliding.*

---

## Why This Exists

VectorBrain is built by multiple agents running simultaneously:
- Claude Code on iPhone (iOS app)
- Claude Code in VSCode (desktop extension)
- Claude Code on the web
- Future: other models (Gemini, Grok, local models) via their respective clients

Each agent needs an isolated working directory, a clear link to what it's working on, and a way to leave a trace that others can see. This system provides that.

---

## Quick Start

### Check in at session start

```bash
# Working on a GitHub issue — creates a worktree automatically
./scripts/agent-checkin.sh \
  --agent claude-code-vscode \
  --model claude-sonnet-4-6 \
  --client claude-code-vscode \
  --scope issue-42 \
  --description "implement event stream classifier for perception loop"

# Bootstrap / infrastructure work — no worktree needed
./scripts/agent-checkin.sh \
  --agent claude-code-ios \
  --model claude-sonnet-4-6 \
  --client claude-code-ios \
  --scope bootstrap/create-backlog \
  --no-worktree \
  --description "extract backlog from MACHINA_ANIMA and create GitHub issues"
```

The script prints a session card with your **Session ID**. Keep it — you need it to check out.

### Check out at session end

```bash
./scripts/agent-checkout.sh 20260325-143022-a3f9 \
  --summary "event classifier implemented, routes urgent/notable/background, 14 tests green" \
  --issues 42,43
```

### View active sessions

```bash
./scripts/agent-status.sh               # active sessions only (default)
./scripts/agent-status.sh --all         # all sessions
./scripts/agent-status.sh --last 50     # last 50 sessions
```

---

## Agent Identity

Every check-in requires four identifiers:

| Field | What it is | Examples |
|---|---|---|
| `--agent` | Unique slug for this agent instance | `claude-code-ios`, `claude-code-vscode-laptop`, `cursor-desktop` |
| `--model` | The AI model powering it | `claude-sonnet-4-6`, `claude-opus-4-6`, `gpt-4o` |
| `--client` | The software client | `claude-code-ios`, `claude-code-vscode`, `claude-code-web`, `cursor`, `other` |
| `--scope` | What work this session covers | `issue-42`, `issue-42-43`, `bootstrap/create-backlog`, `hotfix/connection-crash` |

**Agent slug convention:** `{client}-{location-or-device}` when there could be ambiguity.
- `claude-code-ios` — only one iOS instance likely
- `claude-code-vscode-laptop` — if there's also a desktop
- `claude-code-vscode-ci` — if running in CI

---

## Branch and Worktree Convention

### Branch naming

```
agent/{agent-slug}/{scope}
```

Examples:
```
agent/claude-code-ios/bootstrap/create-backlog
agent/claude-code-vscode/issue-42
agent/claude-code-vscode/issue-42-45
agent/cursor-desktop/hotfix/connection-crash
```

### Worktree location

Worktrees are created under `.worktrees/` in the repo root (gitignored).
Each worktree is named: `.worktrees/{session-id}-{scope-slug}`

```
.worktrees/
  20260325-143022-a3f9-issue-42/    ← claude-code-vscode working on issue 42
  20260325-151100-b7d2-issue-15/    ← claude-code-ios working on issue 15
```

Multiple agents can work simultaneously in different worktrees on different branches.

### When NOT to create a worktree

Use `--no-worktree` when:
- Doing bootstrap work (e.g., creating the first issues, setting up infrastructure)
- You're already on the correct branch (e.g., your session branch was pre-assigned)
- The work is repo-wide (e.g., updating CLAUDE.md, WORKFLOW.md)

---

## Commit Message Format

Every commit made during a session should include agent metadata as git trailers:

```
feat(perception): implement event stream classifier

Routes incoming WirePod events into urgent/notable/background buckets.
Urgent events trigger immediate LLM reasoning. Notable events update
the world model and queue for background integration. Background events
(pose updates, odometry) are silently committed to the world model.

Agent-Name: claude-code-vscode
Agent-Model: claude-sonnet-4-6
Session-Id: 20260325-143022-a3f9
Issue: #42
```

**Trailers** (the last block, after a blank line):
- `Agent-Name:` — the `--agent` value from check-in
- `Agent-Model:` — the `--model` value from check-in
- `Session-Id:` — the session ID from check-in
- `Issue:` — GitHub issue(s) this commit addresses (use `#N` format)

The trailers are machine-readable via `git log --format='%(trailers)'` and allow
filtering history by agent, model, or issue without any external tooling.

---

## Session Log Format

`agent-sessions.jsonl` is an append-only log tracked in git. Each line is a JSON object.

**Start record** (written at check-in):
```json
{"type":"start","session_id":"20260325-143022-a3f9","agent":"claude-code-vscode","model":"claude-sonnet-4-6","client":"claude-code-vscode","scope":"issue-42","branch":"agent/claude-code-vscode/issue-42","worktree":".worktrees/20260325-143022-a3f9-issue-42","started_at":"2026-03-25T14:30:22Z","description":"implement event stream classifier","base_branch":"main","base_commit":"07a1159"}
```

**End record** (written at checkout):
```json
{"type":"end","session_id":"20260325-143022-a3f9","status":"completed","ended_at":"2026-03-25T16:45:00Z","summary":"classifier implemented, 14 tests green","issues":"42,43"}
```

Status values: `completed` | `abandoned` | `paused`

---

## Working in a Worktree

After check-in creates your worktree:

```bash
cd .worktrees/{your-session-worktree}/

# This is a full git checkout on your agent branch.
# Make changes, run tests, commit — exactly as you would in the main repo.

# Build (Go)
GOMODCACHE=../../.gomodcache go build ./...

# Test (Go)
GOMODCACHE=../../.gomodcache go test ./...

# Test (Python)
cd python && ../.venv/bin/python -m pytest tests/ -v

# Commit with proper trailers
git commit -m "$(cat <<'EOF'
feat(perception): implement event classifier

Routes events into urgent/notable/background.

Agent-Name: claude-code-vscode
Agent-Model: claude-sonnet-4-6
Session-Id: 20260325-143022-a3f9
Issue: #42
EOF
)"

# Push your branch
git push -u origin agent/claude-code-vscode/issue-42
```

---

## Full Session Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│                    AGENT SESSION LIFECYCLE               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. READ          Read MEMORY.md (or this WORKFLOW.md)  │
│                   Read CLAUDE.md for architecture rules  │
│                                                         │
│  2. CHECK IN      ./scripts/agent-checkin.sh ...        │
│                   → creates branch + worktree           │
│                   → logs session start                  │
│                   → prints Session ID                   │
│                                                         │
│  3. WORK          cd into worktree (or stay in main)    │
│                   make changes                          │
│                   run tests                             │
│                   commit with trailers                  │
│                                                         │
│  4. CHECK OUT     ./scripts/agent-checkout.sh SID ...   │
│                   → logs session end + summary          │
│                   → removes worktree (if clean)         │
│                                                         │
│  5. PUSH & PR     git push -u origin {branch}           │
│                   open PR targeting main                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Conflict Prevention

- Each agent works in its own worktree on its own branch — no collisions
- `agent-sessions.jsonl` is the only shared file; it's append-only, so concurrent writes just interleave lines (acceptable for a log)
- If two agents need to edit the same file, coordinate via GitHub issues before starting
- The `agent-status.sh` script shows who is actively working and on what

---

## Session Log as Audit Trail

The `agent-sessions.jsonl` file is committed to the repo. This means:
- You can `git log agent-sessions.jsonl` to see the full history of agent activity
- You can `grep "claude-code-ios" agent-sessions.jsonl` to see all iOS sessions
- You can trace any commit back to a session, and any session back to an issue
- Future agents reading the log know exactly what has been done, by whom, and when

---

## For CLAUDE.md Compliance

This workflow is part of the mandatory Session Start Protocol in `CLAUDE.md`.
Every agent session must begin with a check-in. Every session must end with a checkout.
No exceptions — even for "quick fixes". The log is the memory of the project's activity.
