#!/usr/bin/env bash
# scripts/setup-milestones.sh — One-time setup: create M0–M8 GitHub milestones.
#
# Run once after repo setup. Safe to re-run — existing milestones are not duplicated.
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx ./scripts/setup-milestones.sh
#
# After running, note the milestone numbers printed (used by issue_write --milestone N)

set -euo pipefail

REPO_OWNER="infraax"
REPO_NAME="vectorbrain"
GITHUB_API="https://api.github.com"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: GITHUB_TOKEN environment variable required." >&2
  exit 1
fi

create_milestone() {
  local title="$1"
  local description="$2"

  HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"${title}\",\"description\":\"${description}\"}" \
    "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/milestones")

  HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -1)
  BODY=$(echo "$HTTP_RESPONSE" | head -n -1)

  if [[ "$HTTP_CODE" == "201" ]]; then
    NUMBER=$(echo "$BODY" | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)
    printf "  ✓ created  Milestone #%s — %s\n" "$NUMBER" "$title"
  elif [[ "$HTTP_CODE" == "422" ]]; then
    printf "  ↺ exists   %s (skipped)\n" "$title"
  else
    printf "  ✗ failed   %s (HTTP %s)\n" "$title" "$HTTP_CODE" >&2
  fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  VECTORBRAIN — GitHub Milestone Setup                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

create_milestone "M0 — Scaffolding"          "Both repos compile, /health responds. COMPLETE."
create_milestone "M1 — Robot Connection"      "Persistent SDK connection, events streaming, behavior control held. Verify: live battery in /state."
create_milestone "M2 — Command Execution"     "Vector speaks, animates, moves via API. Verify: curl POST /action {type:say} → Vector speaks."
create_milestone "M3 — Python-Go Bridge"      "Events flow Go→Python, commands flow Python→Go. Verify: touch back → event in Python logs."
create_milestone "M4 — First Voice Conversation" "LLM-powered, in-character voice responses. Verify: Hey Vector → coherent response."
create_milestone "M5 — WirePod Integration"   "Wake word routes to VectorBrain. Verify: Hey Vector, meaning of life? → VB response."
create_milestone "M6 — Mind Loop"             "Continuous inner life, drives, proactive behavior. Verify: walk past → greeted by name."
create_milestone "M7 — Memory"                "Persists across sessions, remembers you specifically. Verify: tell it something Monday, it mentions Wednesday."
create_milestone "M8 — Full Perception + MCP" "Vision, continuous listening, AI dev interface. Verify: Claude Desktop reads robot state via MCP."

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Milestone setup complete.                                   ║"
echo "║                                                              ║"
echo "║  Note the milestone numbers above — use them with           ║"
echo "║  agent-claim.sh and issue creation scripts.                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
