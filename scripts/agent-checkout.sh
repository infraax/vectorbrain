#!/usr/bin/env bash
# scripts/agent-checkout.sh — Mark an agent session complete and optionally remove the worktree.
#
# Call this at the end of every agent session. It records what was done,
# links the session to any GitHub issues, and cleans up the worktree.
#
# Usage:
#   ./scripts/agent-checkout.sh SESSION_ID [OPTIONS]
#
# Required:
#   SESSION_ID   The session ID printed at check-in (format: YYYYMMDD-HHMMSS-xxxx)
#
# Optional:
#   --summary TEXT      One-line description of what was accomplished
#   --issues N,N,...    Comma-separated GitHub issue numbers addressed
#   --keep-worktree     Do not remove the worktree (useful if PR not yet created)
#   --status STATUS     "completed" | "abandoned" | "paused" (default: completed)
#
# Examples:
#   ./scripts/agent-checkout.sh 20260325-143022-a3f9 \
#     --summary "implemented event classifier, 12 tests passing" \
#     --issues 42,43
#
#   ./scripts/agent-checkout.sh 20260325-143022-a3f9 --status abandoned \
#     --summary "blocked on SDK auth issue, see issue #47"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_FILE="$REPO_ROOT/agent-sessions.jsonl"
WORKTREES_DIR="$REPO_ROOT/.worktrees"

# ── Argument parsing ───────────────────────────────────────────────────────────

SESSION_ID=""
SUMMARY=""
ISSUES=""
KEEP_WORKTREE=false
STATUS="completed"

# First positional arg is session ID
if [[ $# -gt 0 && "$1" != --* ]]; then
  SESSION_ID="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary)        SUMMARY="$2";        shift 2 ;;
    --issues)         ISSUES="$2";         shift 2 ;;
    --keep-worktree)  KEEP_WORKTREE=true;  shift 1 ;;
    --status)         STATUS="$2";         shift 2 ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SESSION_ID" ]]; then
  echo "ERROR: Session ID required." >&2
  echo "Usage: ./scripts/agent-checkout.sh SESSION_ID [--summary TEXT] [--issues N,N]" >&2
  exit 1
fi

# ── Validate the session exists ────────────────────────────────────────────────

if ! grep -q "\"session_id\":\"${SESSION_ID}\"" "$SESSIONS_FILE" 2>/dev/null; then
  echo "ERROR: Session '${SESSION_ID}' not found in ${SESSIONS_FILE}" >&2
  exit 1
fi

# ── Find worktree path from session log ───────────────────────────────────────

# Extract worktree path from the start record (grep + crude parse, no jq needed)
WORKTREE_RAW="$(grep "\"session_id\":\"${SESSION_ID}\"" "$SESSIONS_FILE" | grep '"type":"start"' | \
  sed 's/.*"worktree":"\([^"]*\)".*/\1/' 2>/dev/null || echo "")"

# ── Timestamps ────────────────────────────────────────────────────────────────

ENDED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ── Append end record ──────────────────────────────────────────────────────────

SUMMARY_CLEAN="$(echo "$SUMMARY" | tr '\n' ' ' | sed 's/"/\\"/g')"

END_JSON=$(cat <<EOF
{"type":"end","session_id":"${SESSION_ID}","status":"${STATUS}","ended_at":"${ENDED_AT}","summary":"${SUMMARY_CLEAN}","issues":"${ISSUES}"}
EOF
)

echo "$END_JSON" >> "$SESSIONS_FILE"

# ── Worktree cleanup ───────────────────────────────────────────────────────────

cd "$REPO_ROOT"

if [[ "$KEEP_WORKTREE" == "false" && -n "$WORKTREE_RAW" && -d "$WORKTREE_RAW" ]]; then
  # Check for uncommitted changes in the worktree before removing
  if git -C "$WORKTREE_RAW" diff --quiet && git -C "$WORKTREE_RAW" diff --cached --quiet 2>/dev/null; then
    git worktree remove "$WORKTREE_RAW" 2>/dev/null || true
    echo "  Worktree removed: $WORKTREE_RAW"
  else
    echo "  WARNING: Worktree has uncommitted changes — keeping it."
    echo "  Path: $WORKTREE_RAW"
    echo "  Commit or stash your changes, then: git worktree remove '$WORKTREE_RAW'"
  fi
fi

# ── Print completion card ──────────────────────────────────────────────────────

STATUS_SYMBOL="✓"
[[ "$STATUS" == "abandoned" ]] && STATUS_SYMBOL="✗"
[[ "$STATUS" == "paused"    ]] && STATUS_SYMBOL="⏸"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
printf "║  AGENT SESSION %-47s ║\n" "${STATUS_SYMBOL} ${STATUS^^}"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Session ID  : %-46s ║\n" "$SESSION_ID"
printf "║  Ended at    : %-46s ║\n" "$ENDED_AT"
if [[ -n "$SUMMARY" ]]; then
  printf "║  Summary     : %-46s ║\n" "${SUMMARY:0:46}"
fi
if [[ -n "$ISSUES" ]]; then
  printf "║  Issues      : %-46s ║\n" "#${ISSUES}"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
