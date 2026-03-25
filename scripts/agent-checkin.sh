#!/usr/bin/env bash
# scripts/agent-checkin.sh — Register an agent session and optionally create a git worktree.
#
# Every agent (Claude Code on iOS, VSCode extension, web, any model) calls this at session start.
# It logs who is working, on what, from where — and creates an isolated git worktree
# so multiple agents can work simultaneously without colliding.
#
# Usage:
#   ./scripts/agent-checkin.sh [OPTIONS]
#
# Required:
#   --agent    SLUG    Short identifier for this agent instance (e.g. claude-code-ios, claude-code-vscode-laptop)
#   --model    NAME    Model name (e.g. claude-sonnet-4-6, claude-opus-4-6, gpt-4o)
#   --client   NAME    Client software (claude-code-ios | claude-code-vscode | claude-code-web | cursor | other)
#   --scope    PATH    Work scope path: "issue-42" | "issue-42-45" | "bootstrap/create-backlog" | "hotfix/xyz"
#
# Optional:
#   --description TEXT  Human-readable one-line description of what this session will do
#   --no-worktree       Skip worktree creation (use when already on correct branch)
#   --branch    NAME    Explicit branch name override (default: agent/{agent}/{scope})
#
# Examples:
#   # Standard issue work with worktree:
#   ./scripts/agent-checkin.sh --agent claude-code-vscode --model claude-sonnet-4-6 \
#     --client claude-code-vscode --scope issue-42 --description "implement perception loop classifier"
#
#   # Bootstrap work (no worktree, already on right branch):
#   ./scripts/agent-checkin.sh --agent claude-code-web --model claude-sonnet-4-6 \
#     --client claude-code-web --scope bootstrap/agent-workflow --no-worktree \
#     --description "design and implement multi-agent git workflow"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_FILE="$REPO_ROOT/agent-sessions.jsonl"
WORKTREES_DIR="$REPO_ROOT/.worktrees"

# ── Argument parsing ───────────────────────────────────────────────────────────

AGENT=""
MODEL=""
CLIENT=""
SCOPE=""
DESCRIPTION=""
NO_WORKTREE=false
BRANCH_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)       AGENT="$2";         shift 2 ;;
    --model)       MODEL="$2";         shift 2 ;;
    --client)      CLIENT="$2";        shift 2 ;;
    --scope)       SCOPE="$2";         shift 2 ;;
    --description) DESCRIPTION="$2";   shift 2 ;;
    --no-worktree) NO_WORKTREE=true;   shift 1 ;;
    --branch)      BRANCH_OVERRIDE="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      echo "Run with --help or read the header of this script for usage." >&2
      exit 1
      ;;
  esac
done

# ── Validation ─────────────────────────────────────────────────────────────────

MISSING=()
[[ -z "$AGENT"  ]] && MISSING+=("--agent")
[[ -z "$MODEL"  ]] && MISSING+=("--model")
[[ -z "$CLIENT" ]] && MISSING+=("--client")
[[ -z "$SCOPE"  ]] && MISSING+=("--scope")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: Missing required arguments: ${MISSING[*]}" >&2
  exit 1
fi

# ── Session ID and timestamps ──────────────────────────────────────────────────

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
# Generate a short random suffix (4 hex chars) without requiring uuidgen
RAND_SUFFIX="$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 4 || echo "xxxx")"
SESSION_ID="${TIMESTAMP}-${RAND_SUFFIX}"
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ── Branch name ────────────────────────────────────────────────────────────────
# Convention: agent/{agent-slug}/{scope}
# Slashes in scope are preserved (creates nested namespace in branch listing)
# Examples:
#   agent/claude-code-ios/issue-42
#   agent/claude-code-vscode/bootstrap/create-backlog
#   agent/claude-opus-laptop/issue-15-23

if [[ -n "$BRANCH_OVERRIDE" ]]; then
  BRANCH="$BRANCH_OVERRIDE"
else
  # Sanitize scope: lowercase, replace spaces with hyphens
  SCOPE_CLEAN="$(echo "$SCOPE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
  BRANCH="agent/${AGENT}/${SCOPE_CLEAN}"
fi

# Worktree directory name = last path segment of the branch (slug after final slash)
WORKTREE_SLUG="${BRANCH##*/}"
WORKTREE_PATH="${WORKTREES_DIR}/${SESSION_ID}-${WORKTREE_SLUG}"

# ── Current git context ────────────────────────────────────────────────────────

cd "$REPO_ROOT"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
CURRENT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# ── Worktree creation ──────────────────────────────────────────────────────────

ACTUAL_WORKTREE_PATH=""

if [[ "$NO_WORKTREE" == "false" ]]; then
  mkdir -p "$WORKTREES_DIR"

  # Create branch if it doesn't exist
  if ! git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git branch "$BRANCH"
    echo "  Created branch: $BRANCH"
  else
    echo "  Reusing existing branch: $BRANCH"
  fi

  # Create worktree
  git worktree add "$WORKTREE_PATH" "$BRANCH"
  ACTUAL_WORKTREE_PATH="$WORKTREE_PATH"
  echo "  Worktree created at: .worktrees/${SESSION_ID}-${WORKTREE_SLUG}"
else
  ACTUAL_WORKTREE_PATH="(main working tree — $CURRENT_BRANCH)"
fi

# ── Append to session log ──────────────────────────────────────────────────────

# Write a clean JSON line. We avoid jq dependency by building it manually.
# All values are single-line strings — newlines in description are stripped.
DESC_CLEAN="$(echo "$DESCRIPTION" | tr '\n' ' ' | sed 's/"/\\"/g')"

SESSION_JSON=$(cat <<EOF
{"type":"start","session_id":"${SESSION_ID}","agent":"${AGENT}","model":"${MODEL}","client":"${CLIENT}","scope":"${SCOPE}","branch":"${BRANCH}","worktree":"${ACTUAL_WORKTREE_PATH}","started_at":"${STARTED_AT}","description":"${DESC_CLEAN}","base_branch":"${CURRENT_BRANCH}","base_commit":"${CURRENT_COMMIT}"}
EOF
)

echo "$SESSION_JSON" >> "$SESSIONS_FILE"

# ── Print session card ─────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  AGENT SESSION STARTED                                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Session ID  : %-46s ║\n" "$SESSION_ID"
printf "║  Agent       : %-46s ║\n" "$AGENT"
printf "║  Model       : %-46s ║\n" "$MODEL"
printf "║  Client      : %-46s ║\n" "$CLIENT"
printf "║  Scope       : %-46s ║\n" "$SCOPE"
printf "║  Branch      : %-46s ║\n" "$BRANCH"
if [[ "$NO_WORKTREE" == "false" ]]; then
  WSLUG_DISPLAY=".worktrees/${SESSION_ID}-${WORKTREE_SLUG}"
  printf "║  Worktree    : %-46s ║\n" "${WSLUG_DISPLAY:0:46}"
else
  printf "║  Worktree    : %-46s ║\n" "none (main working tree)"
fi
if [[ -n "$DESCRIPTION" ]]; then
  printf "║  Task        : %-46s ║\n" "${DESCRIPTION:0:46}"
fi
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  To complete this session, run:                              ║"
printf "║    ./scripts/agent-checkout.sh %-30s ║\n" "$SESSION_ID"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Export session ID so calling shell can capture it
echo "SESSION_ID=$SESSION_ID"
