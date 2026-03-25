#!/usr/bin/env bash
# scripts/agent-claim.sh — Claim a GitHub issue and create a worktree for it.
#
# Implements the mutex: checks no other agent holds the issue, sets the
# claim label, creates a worktree via agent-checkin.sh, and posts a comment.
#
# Usage:
#   ./scripts/agent-claim.sh ISSUE [OPTIONS]
#
# Required:
#   ISSUE         GitHub issue number to claim
#
# Required env / options:
#   --agent    SLUG    Your agent slug  (e.g. claude-code-ios)
#   --model    NAME    Your model       (e.g. claude-sonnet-4-6)
#   --client   NAME    Your client      (e.g. claude-code-ios)
#
# Optional:
#   --description TEXT  What you plan to do (added to comment + session log)
#   --dry-run           Print what would happen without making any changes
#
# Environment:
#   GITHUB_TOKEN   Required for GitHub API calls (label + comment operations)
#
# Example:
#   GITHUB_TOKEN=ghp_xxx ./scripts/agent-claim.sh 42 \
#     --agent claude-code-vscode \
#     --model claude-sonnet-4-6 \
#     --client claude-code-vscode \
#     --description "implement event stream classifier"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_OWNER="infraax"
REPO_NAME="vectorbrain"
GITHUB_API="https://api.github.com"

# ── Argument parsing ───────────────────────────────────────────────────────────

ISSUE_NUMBER=""
AGENT=""
MODEL=""
CLIENT=""
DESCRIPTION=""
DRY_RUN=false

if [[ $# -gt 0 && "$1" != --* ]]; then
  ISSUE_NUMBER="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)       AGENT="$2";       shift 2 ;;
    --model)       MODEL="$2";       shift 2 ;;
    --client)      CLIENT="$2";      shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true;     shift 1 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Validation ─────────────────────────────────────────────────────────────────

MISSING=()
[[ -z "$ISSUE_NUMBER" ]] && MISSING+=("ISSUE")
[[ -z "$AGENT"        ]] && MISSING+=("--agent")
[[ -z "$MODEL"        ]] && MISSING+=("--model")
[[ -z "$CLIENT"       ]] && MISSING+=("--client")
[[ -z "${GITHUB_TOKEN:-}" ]] && MISSING+=("GITHUB_TOKEN (env var)")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: Missing required arguments: ${MISSING[*]}" >&2
  exit 1
fi

CLAIM_LABEL="claimed:${AGENT}"

# ── GitHub API helpers ─────────────────────────────────────────────────────────

gh_get() {
  curl -sf \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API}/$1"
}

gh_post() {
  local endpoint="$1"
  local data="$2"
  curl -sf \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "$data" \
    "${GITHUB_API}/${endpoint}"
}

gh_patch() {
  local endpoint="$1"
  local data="$2"
  curl -sf \
    -X PATCH \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "$data" \
    "${GITHUB_API}/${endpoint}"
}

# ── Fetch issue ────────────────────────────────────────────────────────────────

echo "Fetching issue #${ISSUE_NUMBER}..."
ISSUE_JSON="$(gh_get "repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}")"

if [[ -z "$ISSUE_JSON" ]]; then
  echo "ERROR: Could not fetch issue #${ISSUE_NUMBER}" >&2
  exit 1
fi

ISSUE_TITLE="$(echo "$ISSUE_JSON" | grep -o '"title":"[^"]*"' | head -1 | sed 's/"title":"//;s/"//')"
ISSUE_STATE="$(echo "$ISSUE_JSON" | grep -o '"state":"[^"]*"' | head -1 | sed 's/"state":"//;s/"//')"

echo "  Title: $ISSUE_TITLE"
echo "  State: $ISSUE_STATE"

# Check issue is open
if [[ "$ISSUE_STATE" != "open" ]]; then
  echo "ERROR: Issue #${ISSUE_NUMBER} is ${ISSUE_STATE}, not open." >&2
  exit 1
fi

# ── Check for existing claim ───────────────────────────────────────────────────
# Extract all label names from the issue JSON

EXISTING_LABELS="$(echo "$ISSUE_JSON" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')"

# Check for any claim: label
EXISTING_CLAIM="$(echo "$EXISTING_LABELS" | grep '^claimed:' || true)"

if [[ -n "$EXISTING_CLAIM" ]]; then
  echo ""
  echo "ERROR: Issue #${ISSUE_NUMBER} is already claimed." >&2
  echo "  Held by: $EXISTING_CLAIM" >&2
  echo ""
  echo "  If that agent session is dead, run:" >&2
  echo "    ./scripts/agent-release.sh ${ISSUE_NUMBER} --agent ${EXISTING_CLAIM#claimed:} --force" >&2
  exit 1
fi

# ── Dry run check ──────────────────────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "[DRY RUN] Would:"
  echo "  1. Add label '$CLAIM_LABEL' to issue #${ISSUE_NUMBER}"
  echo "  2. Add label 'status: in-progress' to issue #${ISSUE_NUMBER}"
  echo "  3. Post check-in comment on issue #${ISSUE_NUMBER}"
  echo "  4. Run agent-checkin.sh --scope issue-${ISSUE_NUMBER}"
  echo ""
  exit 0
fi

# ── Ensure claim label exists ──────────────────────────────────────────────────
# Try to create it (no-op if already exists, GitHub returns 422 which we ignore)

curl -sf \
  -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${CLAIM_LABEL}\",\"color\":\"0075ca\",\"description\":\"Currently claimed by agent ${AGENT}\"}" \
  "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/labels" > /dev/null 2>&1 || true

# ── Apply labels ───────────────────────────────────────────────────────────────

echo "Setting claim label '$CLAIM_LABEL'..."

# Build updated label list: keep existing labels, add claim + in-progress
LABELS_TO_SET="$(echo "$EXISTING_LABELS" | grep -v '^claimed:' | grep -v '^status:' || true)"
LABELS_JSON="[$(echo "$LABELS_TO_SET" | grep -v '^$' | sed 's/.*/\"&\"/' | paste -sd ',' -)]"

# Append our new labels
if [[ "$LABELS_JSON" == "[]" ]] || [[ "$LABELS_JSON" == "[\"\"]" ]]; then
  LABELS_JSON="[\"${CLAIM_LABEL}\",\"status: in-progress\"]"
else
  LABELS_JSON="${LABELS_JSON%]},\"${CLAIM_LABEL}\",\"status: in-progress\"]"
fi

gh_patch "repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}" \
  "{\"labels\":${LABELS_JSON}}" > /dev/null

echo "  Labels updated."

# ── Run agent-checkin ──────────────────────────────────────────────────────────

echo "Creating worktree and session..."

CHECKIN_OUTPUT="$("${REPO_ROOT}/scripts/agent-checkin.sh" \
  --agent "$AGENT" \
  --model "$MODEL" \
  --client "$CLIENT" \
  --scope "issue-${ISSUE_NUMBER}" \
  --description "${DESCRIPTION:-working on issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}}")"

echo "$CHECKIN_OUTPUT"

SESSION_ID="$(echo "$CHECKIN_OUTPUT" | grep '^SESSION_ID=' | cut -d= -f2)"
BRANCH="agent/${AGENT}/issue-${ISSUE_NUMBER}"

# ── Post comment on issue ──────────────────────────────────────────────────────

COMMENT_BODY="### 🤖 Agent Session Started

**Agent:** \`${AGENT}\`
**Model:** \`${MODEL}\`
**Client:** \`${CLIENT}\`
**Session ID:** \`${SESSION_ID}\`
**Branch:** \`${BRANCH}\`
$([ -n "$DESCRIPTION" ] && echo "**Plan:** ${DESCRIPTION}" || true)

*Issue claimed. Worktree created. Work in progress.*

---
*To see all active sessions: \`./scripts/agent-status.sh\`*"

gh_post "repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}/comments" \
  "{\"body\":$(echo "$COMMENT_BODY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" > /dev/null

echo "  Comment posted on issue #${ISSUE_NUMBER}."

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ISSUE CLAIMED                                               ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Issue       : #%-44s ║\n" "${ISSUE_NUMBER} — ${ISSUE_TITLE:0:40}"
printf "║  Claim label : %-46s ║\n" "$CLAIM_LABEL"
printf "║  Session     : %-46s ║\n" "$SESSION_ID"
printf "║  Branch      : %-46s ║\n" "$BRANCH"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Work in your worktree, then:                                ║"
printf "║    ./scripts/agent-release.sh %-30s ║\n" "${ISSUE_NUMBER} --done"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
