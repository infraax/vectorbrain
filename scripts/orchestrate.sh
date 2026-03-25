#!/usr/bin/env bash
# scripts/orchestrate.sh — Invoke the Orchestrator agent (Claude Opus).
#
# The Orchestrator is a higher-tier agent (Opus) that surveys the full project
# state and performs board management that worker agents shouldn't do:
#   - Promote Backlog issues to Ready when dependencies are met
#   - Detect stale In Progress issues (session dead, no commits in 24h+)
#   - Review open PRs and flag for human attention
#   - Update MEMORY.md with current project state
#   - Generate a prioritized work queue for the next work session
#
# Two modes:
#   1. With ANTHROPIC_API_KEY set: calls Claude API directly (Opus model)
#   2. Without: prints a fully-formed brief to paste into any Claude session
#
# Usage:
#   ./scripts/orchestrate.sh [OPTIONS]
#
# Options:
#   --mode survey       Survey board + generate next-actions report (default)
#   --mode promote      Promote ready issues from Backlog → Ready
#   --mode triage       Review stale sessions, blocked issues, open PRs
#   --mode full         Run all three in sequence
#   --dry-run           Print what would change without writing anything
#   --no-api            Force print-only mode even if ANTHROPIC_API_KEY is set
#
# Environment:
#   GITHUB_TOKEN       For GitHub API calls (issue state, PR list)
#   ANTHROPIC_API_KEY  For direct Opus invocation (optional)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_OWNER="infraax"
REPO_NAME="vectorbrain"
GITHUB_API="https://api.github.com"
ORCHESTRATOR_MODEL="claude-opus-4-6"

# ── Argument parsing ───────────────────────────────────────────────────────────

MODE="survey"
DRY_RUN=false
NO_API=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)    MODE="$2";    shift 2 ;;
    --dry-run) DRY_RUN=true; shift 1 ;;
    --no-api)  NO_API=true;  shift 1 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Gather project state ───────────────────────────────────────────────────────

echo "Gathering project state..."

# Git state
RECENT_COMMITS="$(git -C "$REPO_ROOT" log --oneline -10 \
  --format='%h %s [%an]' 2>/dev/null || echo "(none)")"

RECENT_TRAILERS="$(git -C "$REPO_ROOT" log -10 \
  --format='%h|%(trailers:key=Agent-Name,valueonly,separator=)|%(trailers:key=Issue,valueonly,separator=)|%(trailers:key=Session-Id,valueonly,separator=)' \
  2>/dev/null | grep -v '|||' | head -10 || echo "(none)")"

CURRENT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
MODIFIED_FILES="$(git -C "$REPO_ROOT" diff --name-only HEAD~1..HEAD 2>/dev/null | head -10 || echo "(none)")"

# Active sessions from log
ACTIVE_SESSIONS="$(grep '"type":"start"' "$REPO_ROOT/agent-sessions.jsonl" 2>/dev/null | \
  while IFS= read -r line; do
    sid="$(echo "$line" | sed 's/.*"session_id":"\([^"]*\)".*/\1/')"
    # Check if this session has been ended
    if ! grep -q "\"type\":\"end\".*\"session_id\":\"${sid}\"" "$REPO_ROOT/agent-sessions.jsonl" 2>/dev/null && \
       ! grep -q "\"session_id\":\"${sid}\".*\"type\":\"end\"" "$REPO_ROOT/agent-sessions.jsonl" 2>/dev/null; then
      agent="$(echo "$line"   | sed 's/.*"agent":"\([^"]*\)".*/\1/')"
      scope="$(echo "$line"   | sed 's/.*"scope":"\([^"]*\)".*/\1/')"
      started="$(echo "$line" | sed 's/.*"started_at":"\([^"]*\)".*/\1/')"
      echo "  ACTIVE  $sid | $agent | $scope | started: $started"
    fi
  done || echo "  (none)")"

# MEMORY.md content
MEMORY_CONTENT="$(cat "$REPO_ROOT/MEMORY.md" 2>/dev/null || echo "(not found)")"

# GitHub data (if token available)
GH_ISSUES_SUMMARY=""
GH_PRS_SUMMARY=""

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "  Fetching GitHub issues..."
  OPEN_ISSUES="$(curl -sf \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/issues?state=open&per_page=50" \
    2>/dev/null || echo "[]")"

  # Parse issue list into readable summary
  GH_ISSUES_SUMMARY="$(echo "$OPEN_ISSUES" | \
    python3 -c "
import json,sys
issues = json.load(sys.stdin)
for i in issues:
    num = i.get('number','?')
    title = i.get('title','?')[:70]
    labels = [l['name'] for l in i.get('labels',[])]
    label_str = ', '.join(labels[:4]) if labels else 'no labels'
    print(f'  #{num}  [{label_str}]  {title}')
" 2>/dev/null || echo "  (parse error)")"

  echo "  Fetching open PRs..."
  OPEN_PRS="$(curl -sf \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/pulls?state=open" \
    2>/dev/null || echo "[]")"

  GH_PRS_SUMMARY="$(echo "$OPEN_PRS" | \
    python3 -c "
import json,sys
prs = json.load(sys.stdin)
if not prs:
    print('  (none)')
else:
    for p in prs:
        print(f'  #{p[\"number\"]}  {p[\"head\"][\"ref\"]} → {p[\"base\"][\"ref\"]}  \"{p[\"title\"][:60]}\"')
" 2>/dev/null || echo "  (parse error)")"
else
  GH_ISSUES_SUMMARY="  (GITHUB_TOKEN not set — run with GITHUB_TOKEN=xxx for live issue data)"
  GH_PRS_SUMMARY="  (GITHUB_TOKEN not set)"
fi

# ── Build the orchestrator prompt ─────────────────────────────────────────────

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

read -r -d '' ORCHESTRATOR_PROMPT << PROMPT_EOF || true
You are the VectorBrain Orchestrator — a senior agent (Claude Opus) responsible for
project-level board management and coordination. You are NOT a worker agent.
You do NOT write code. You manage the board so worker agents can work efficiently.

## Your role
- Survey the project state below
- Identify what needs to change on the GitHub board (promote/block/flag issues)
- Detect stale or dead sessions
- Update MEMORY.md with the current state
- Output a prioritized work queue for the next session
- Flag anything needing human (Dexter) attention

## Project: VectorBrain
Repository: infraax/vectorbrain
Honor codex: MACHINA_ANIMA.md (read it — this is not a toy project)
Architecture: Go (robot SDK + API) + Python (all AI/ML). Split is FINAL.

## Current timestamp
${TIMESTAMP}

---

## MEMORY.md (current)
${MEMORY_CONTENT}

---

## Active agent sessions
${ACTIVE_SESSIONS}

---

## Recent commits (last 10)
${RECENT_COMMITS}

---

## Recent commit trailers (agent/issue/session)
${RECENT_TRAILERS}

---

## Open GitHub issues
${GH_ISSUES_SUMMARY}

---

## Open pull requests
${GH_PRS_SUMMARY}

---

## Current git branch
${CURRENT_BRANCH}

## Files changed in last commit
${MODIFIED_FILES}

---

## Your tasks for this orchestration run (mode: ${MODE})

$(case "$MODE" in
survey)
cat << 'SURVEY_EOF'
1. SURVEY: Read all state above. Identify:
   - What is the current milestone and how close are we?
   - Which issues are genuinely Ready (dependencies met, not claimed)?
   - Which issues are blocked and why?
   - Are any In Progress issues stale (session active but no recent commits)?
   - Any PRs that need attention?

2. NEXT ACTIONS: Output a prioritized list of the 3–5 most important things
   for worker agents to work on next. Format:
   ```
   NEXT WORK QUEUE:
   1. #14 [xs][go] Add vector-go-sdk — first, unblocks all M1
   2. #21 [s][infra] agent-brief.sh — needed for token efficiency
   3. ...
   ```

3. MEMORY UPDATE: Write an updated MEMORY.md "What the Next Agent Should Do"
   section reflecting current state.

4. FLAGS FOR DEXTER: Anything needing human decision or attention.
SURVEY_EOF
;;
promote)
cat << 'PROMOTE_EOF'
1. PROMOTE: For each Backlog issue, check if its dependencies (mentioned in
   the issue body as "Depends on: #N") are closed/completed.
   If yes → move to Ready (output: "PROMOTE #N: {reason}").
   If no → leave in Backlog (output: "LEAVE #N: blocked on #M").

2. Output a list of promote/leave decisions with reasoning.
3. If GITHUB_TOKEN is available, the calling script will apply these.
PROMOTE_EOF
;;
triage)
cat << 'TRIAGE_EOF'
1. STALE SESSIONS: Any session in agent-sessions.jsonl with status "active"
   that has no commits in the last 24h should be flagged.
   Output: "STALE SESSION: {session_id} | {agent} | last activity: {date}"

2. BLOCKED ISSUES: Any issue with "status: blocked" label — summarize why
   and whether the blocker is resolved based on recent commits.

3. PR REVIEW: For each open PR, assess:
   - Is it targeting main? (good)
   - Does it reference an issue via trailers? (required)
   - Is there anything obviously wrong? (flag for human)

4. RECOMMENDATIONS: Output specific actions for each finding.
TRIAGE_EOF
;;
full)
echo "Run all three: survey, promote, and triage in sequence."
;;
esac)

---

## Output format

Structure your response as:

### Board State Assessment
[2-3 sentences on overall project health]

### Issue Status
[table or list of key issues and their actual status]

### Next Work Queue
[numbered priority list for worker agents]

### Stale/Blocked Flags
[anything needing attention]

### MEMORY.md Update
[the exact text to replace the "What the Next Agent Should Do" section with]

### Flags for Dexter
[anything needing human decision]
PROMPT_EOF

# ── Execute or print ───────────────────────────────────────────────────────────

USE_API=false
if [[ -n "${ANTHROPIC_API_KEY:-}" && "$NO_API" == "false" ]]; then
  USE_API=true
fi

if [[ "$USE_API" == "true" ]]; then
  echo "Invoking $ORCHESTRATOR_MODEL via Claude API..."
  echo ""

  # Call Claude API directly
  API_RESPONSE="$(curl -sf \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(python3 -c "
import json, sys
prompt = sys.stdin.read()
payload = {
    'model': '${ORCHESTRATOR_MODEL}',
    'max_tokens': 4096,
    'messages': [{'role': 'user', 'content': prompt}]
}
print(json.dumps(payload))
" <<< "$ORCHESTRATOR_PROMPT")" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)"

  # Extract and print the text response
  echo "$API_RESPONSE" | python3 -c "
import json, sys
resp = json.load(sys.stdin)
if 'content' in resp:
    for block in resp['content']:
        if block.get('type') == 'text':
            print(block['text'])
elif 'error' in resp:
    print(f'API ERROR: {resp[\"error\"]}', file=sys.stderr)
" 2>&1

  echo ""
  echo "─────────────────────────────────────────────────────"
  echo "Orchestration complete. Apply any board changes above."
  echo "─────────────────────────────────────────────────────"

else
  # Print-only mode: output the prompt for the human to use
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  ORCHESTRATOR BRIEF — paste into a Claude Opus session              ║"
  echo "║  Or set ANTHROPIC_API_KEY to invoke directly                        ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "$ORCHESTRATOR_PROMPT"
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  To invoke directly:                                                ║"
  echo "║    ANTHROPIC_API_KEY=sk-ant-xxx ./scripts/orchestrate.sh           ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
fi
