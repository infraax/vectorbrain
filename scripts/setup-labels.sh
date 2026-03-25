#!/usr/bin/env bash
# scripts/setup-labels.sh — One-time setup: create all GitHub labels for the project board.
#
# Run this ONCE after cloning or when setting up a new repository.
# Safe to re-run — existing labels are updated, not duplicated.
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx ./scripts/setup-labels.sh
#
# Environment:
#   GITHUB_TOKEN   Personal access token with repo scope (or fine-grained with Issues write)

set -euo pipefail

REPO_OWNER="infraax"
REPO_NAME="vectorbrain"
GITHUB_API="https://api.github.com"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: GITHUB_TOKEN environment variable required." >&2
  echo "  export GITHUB_TOKEN=ghp_your_token_here" >&2
  exit 1
fi

# ── Label upsert function ──────────────────────────────────────────────────────
# Creates label if it doesn't exist, updates color/description if it does.

create_or_update_label() {
  local name="$1"
  local color="$2"   # hex without #
  local description="$3"

  # Try to create
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"color\":\"${color}\",\"description\":\"${description}\"}" \
    "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/labels")

  if [[ "$HTTP_CODE" == "201" ]]; then
    printf "  ✓ created  %s\n" "$name"
  elif [[ "$HTTP_CODE" == "422" ]]; then
    # Already exists — update it
    NAME_ENCODED="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${name}'))")"
    curl -sf \
      -X PATCH \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      -d "{\"color\":\"${color}\",\"description\":\"${description}\"}" \
      "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/labels/${NAME_ENCODED}" > /dev/null
    printf "  ↺ updated  %s\n" "$name"
  else
    printf "  ✗ failed   %s (HTTP %s)\n" "$name" "$HTTP_CODE" >&2
  fi
}

# ── Delete GitHub default labels (optional cleanup) ───────────────────────────

delete_default_labels() {
  local defaults=("bug" "documentation" "duplicate" "enhancement" "good first issue"
                  "help wanted" "invalid" "question" "wontfix")
  echo "Removing GitHub default labels..."
  for label in "${defaults[@]}"; do
    NAME_ENCODED="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${label}'))")"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X DELETE \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/labels/${NAME_ENCODED}")
    [[ "$HTTP_CODE" == "204" ]] && printf "  ✓ deleted  %s\n" "$label" || true
  done
}

# ── Create all labels ──────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  VECTORBRAIN — GitHub Label Setup                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Optionally clean up GitHub defaults
if [[ "${CLEAN_DEFAULTS:-false}" == "true" ]]; then
  delete_default_labels
  echo ""
fi

# ── TYPE ──────────────────────────────────────────────────────────────────────
echo "Type labels..."
create_or_update_label "type: epic"     "6B46C1" "Large system pillar spanning multiple milestones"
create_or_update_label "type: feature"  "0075ca" "A complete capability within an epic"
create_or_update_label "type: task"     "cfd3d7" "A concrete unit of work within a feature"
create_or_update_label "type: bug"      "d73a4a" "Something broken that needs fixing"
create_or_update_label "type: research" "e4e669" "Investigation or spike — output is knowledge, not code"
create_or_update_label "type: chore"    "fef2c0" "Maintenance, tooling, config — no new functionality"

# ── PRIORITY ──────────────────────────────────────────────────────────────────
echo ""
echo "Priority labels..."
create_or_update_label "priority: p0-critical" "b60205" "Blocking everything — drop other work"
create_or_update_label "priority: p1-high"     "d93f0b" "Important, do soon"
create_or_update_label "priority: p2-medium"   "e99695" "Normal priority"
create_or_update_label "priority: p3-low"      "f9d0c4" "Nice to have, do when nothing else is urgent"

# ── SIZE ──────────────────────────────────────────────────────────────────────
echo ""
echo "Size labels..."
create_or_update_label "size: xs"  "c2e0c6" "< 1 hour"
create_or_update_label "size: s"   "0e8a16" "1–4 hours"
create_or_update_label "size: m"   "e4e669" "4–8 hours (one session)"
create_or_update_label "size: l"   "d93f0b" "Multiple sessions / 1+ day"

# ── CAPABILITY ────────────────────────────────────────────────────────────────
echo ""
echo "Capability labels..."
create_or_update_label "cap: go"      "00ADD8" "Requires Go work (SDK, API server, event bridge)"
create_or_update_label "cap: python"  "3776AB" "Requires Python work (mind loop, perception, memory)"
create_or_update_label "cap: ai-ml"   "9B59B6" "Requires AI/ML work (LLM, embeddings, perception models)"
create_or_update_label "cap: infra"   "95A5A6" "Infrastructure (CI, scripts, tooling, GitHub Actions)"
create_or_update_label "cap: docs"    "BDC3C7" "Documentation only"

# ── STATUS ────────────────────────────────────────────────────────────────────
echo ""
echo "Status labels..."
create_or_update_label "status: backlog"     "ededed" "Not yet ready to work on — dependencies unmet"
create_or_update_label "status: ready"       "0e8a16" "Dependencies met — available for an agent to claim"
create_or_update_label "status: in-progress" "0052CC" "An agent has this claimed and is actively working"
create_or_update_label "status: blocked"     "d93f0b" "Work started but stuck — needs external resolution"
create_or_update_label "status: review"      "7057FF" "PR open — needs review before merge"
create_or_update_label "status: needs-hardware" "F9A825" "Requires physical Vector robot to verify"
create_or_update_label "status: needs-research" "FFF9C4" "Needs investigation before implementation can start"

# ── MILESTONE TAGS ────────────────────────────────────────────────────────────
echo ""
echo "Milestone labels..."
create_or_update_label "milestone: M0" "c5def5" "Scaffolding (complete)"
create_or_update_label "milestone: M1" "bfd4f2" "Robot Connection"
create_or_update_label "milestone: M2" "d4c5f9" "Command Execution"
create_or_update_label "milestone: M3" "f9c5c5" "Python-Go Bridge"
create_or_update_label "milestone: M4" "f9e4c5" "First Voice Conversation"
create_or_update_label "milestone: M5" "f9f4c5" "WirePod Integration"
create_or_update_label "milestone: M6" "e4f9c5" "Mind Loop"
create_or_update_label "milestone: M7" "c5f9d4" "Memory"
create_or_update_label "milestone: M8" "c5f9f4" "Full Perception + MCP"

# ── AGENT CLAIM (pre-create common ones) ──────────────────────────────────────
echo ""
echo "Agent claim labels..."
create_or_update_label "claimed: claude-code-ios"    "0075ca" "Claimed by claude-code-ios agent"
create_or_update_label "claimed: claude-code-vscode" "0075ca" "Claimed by claude-code-vscode agent"
create_or_update_label "claimed: claude-code-web"    "0075ca" "Claimed by claude-code-web agent"
create_or_update_label "claimed: orchestrator"       "6B46C1" "Claimed by orchestrator agent"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Label setup complete.                                       ║"
echo "║                                                              ║"
echo "║  Next: create the GitHub Project board manually             ║"
echo "║  (see WORKFLOW.md — Project Board Setup section)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
