#!/usr/bin/env bash
# scripts/agent-status.sh — Show all agent sessions, active and recent.
#
# Reads agent-sessions.jsonl and prints a summary table.
# Active sessions are those with a "start" record but no corresponding "end" record.
#
# Usage:
#   ./scripts/agent-status.sh [--all] [--active-only]
#
# Options:
#   --all          Show all sessions including old completed ones
#   --active-only  Show only currently active sessions (default)
#   --last N       Show last N sessions of any status (default: 20)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_FILE="$REPO_ROOT/agent-sessions.jsonl"

SHOW_ALL=false
ACTIVE_ONLY=true
LAST_N=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)         SHOW_ALL=true; ACTIVE_ONLY=false; shift ;;
    --active-only) ACTIVE_ONLY=true; shift ;;
    --last)        LAST_N="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo "No session log found at $SESSIONS_FILE"
  exit 0
fi

# ── Parse sessions ─────────────────────────────────────────────────────────────
# We process the JSONL without jq by using grep and sed.
# Each line is a complete JSON object.

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════════════╗"
echo "║  VECTORBRAIN AGENT SESSIONS                                                          ║"
echo "╠══════════════════════════════════════════════════════════════════════════════════════╣"
printf "║  %-20s  %-22s  %-12s  %-10s  %-14s ║\n" "SESSION ID" "AGENT" "MODEL" "STATUS" "STARTED"
echo "╠══════════════════════════════════════════════════════════════════════════════════════╣"

# Build list of session IDs that have an "end" record
declare -A ENDED_SESSIONS
while IFS= read -r line; do
  if echo "$line" | grep -q '"type":"end"'; then
    sid="$(echo "$line" | sed 's/.*"session_id":"\([^"]*\)".*/\1/')"
    status="$(echo "$line" | sed 's/.*"status":"\([^"]*\)".*/\1/')"
    ENDED_SESSIONS["$sid"]="$status"
  fi
done < "$SESSIONS_FILE"

COUNT=0
ACTIVE_COUNT=0

while IFS= read -r line; do
  if ! echo "$line" | grep -q '"type":"start"'; then
    continue
  fi

  sid="$(echo "$line"      | sed 's/.*"session_id":"\([^"]*\)".*/\1/')"
  agent="$(echo "$line"    | sed 's/.*"agent":"\([^"]*\)".*/\1/')"
  model="$(echo "$line"    | sed 's/.*"model":"\([^"]*\)".*/\1/')"
  scope="$(echo "$line"    | sed 's/.*"scope":"\([^"]*\)".*/\1/')"
  started="$(echo "$line"  | sed 's/.*"started_at":"\([^"]*\)".*/\1/')"
  branch="$(echo "$line"   | sed 's/.*"branch":"\([^"]*\)".*/\1/')"

  # Determine status
  if [[ -v "ENDED_SESSIONS[$sid]" ]]; then
    status="${ENDED_SESSIONS[$sid]}"
  else
    status="active"
    ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
  fi

  # Filter
  if [[ "$ACTIVE_ONLY" == "true" && "$status" != "active" ]]; then
    continue
  fi

  COUNT=$((COUNT + 1))
  if [[ "$SHOW_ALL" == "false" && $COUNT -gt $LAST_N ]]; then
    break
  fi

  # Truncate for display
  agent_d="${agent:0:22}"
  model_d="${model:0:12}"
  scope_d="${scope:0:20}"
  started_d="${started:0:16}"  # YYYY-MM-DDTHH:MM

  # Status display
  case "$status" in
    active)    status_d="● ACTIVE    " ;;
    completed) status_d="✓ done      " ;;
    abandoned) status_d="✗ abandoned " ;;
    paused)    status_d="⏸ paused    " ;;
    *)         status_d="? $status   " ;;
  esac

  printf "║  %-20s  %-22s  %-12s  %-10s  %-14s ║\n" \
    "$sid" "$agent_d" "$model_d" "${status_d:0:10}" "$started_d"
  printf "║    scope: %-75s ║\n" "$scope_d"
  printf "║    branch: %-74s ║\n" "${branch:0:74}"
  echo "║                                                                                      ║"

done < "$SESSIONS_FILE"

if [[ $COUNT -eq 0 ]]; then
  echo "║  No sessions found.                                                                  ║"
  echo "║                                                                                      ║"
fi

echo "╠══════════════════════════════════════════════════════════════════════════════════════╣"
printf "║  Active sessions: %-67s ║\n" "$ACTIVE_COUNT"
echo "╚══════════════════════════════════════════════════════════════════════════════════════╝"
echo ""
