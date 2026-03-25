#!/usr/bin/env bash
# scripts/agent-release.sh — Release a claimed issue and clean up the worktree.
#
# Three modes:
#   --done      Work complete. Opens a PR (or reminds you to), closes claim.
#   --blocked   Work blocked. Returns issue to Ready with a note.
#   --abandon   Giving up. Returns issue to Backlog, logs reason.
#
# Usage:
#   ./scripts/agent-release.sh ISSUE [OPTIONS]
#
# Required:
#   ISSUE            GitHub issue number
#   --agent    SLUG  Your agent slug (must match the claim label)
#   --session  ID    Your session ID (from agent-checkin / agent-claim output)
#
# Mode (pick one):
#   --done            Mark work complete, move to Review, keep worktree for PR
#   --blocked REASON  Unblock others — returns to Ready with reason
#   --abandon REASON  Release without completing — returns to Backlog
#
# Optional:
#   --summary TEXT    One-line summary of what was done / why blocked
#   --force           Release even if claim label belongs to a different agent
#
# Environment:
#   GITHUB_TOKEN   Required for GitHub API calls
#
# Examples:
#   # Done — open PR
#   GITHUB_TOKEN=ghp_xxx ./scripts/agent-release.sh 42 \
#     --agent claude-code-vscode --session 20260325-143022-a3f9 \
#     --done --summary "event classifier implemented, 14 tests green"
#
#   # Blocked
#   GITHUB_TOKEN=ghp_xxx ./scripts/agent-release.sh 42 \
#     --agent claude-code-vscode --session 20260325-143022-a3f9 \
#     --blocked "waiting on vector-go-sdk auth to be resolved in #38"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_OWNER="infraax"
REPO_NAME="vectorbrain"
GITHUB_API="https://api.github.com"

# ── Argument parsing ───────────────────────────────────────────────────────────

ISSUE_NUMBER=""
AGENT=""
SESSION_ID=""
SUMMARY=""
MODE=""
MODE_REASON=""
FORCE=false

if [[ $# -gt 0 && "$1" != --* ]]; then
  ISSUE_NUMBER="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENT="$2";       shift 2 ;;
    --session)  SESSION_ID="$2";  shift 2 ;;
    --summary)  SUMMARY="$2";     shift 2 ;;
    --force)    FORCE=true;       shift 1 ;;
    --done)
      MODE="done"
      shift 1
      ;;
    --blocked)
      MODE="blocked"
      MODE_REASON="${2:-}"
      [[ -n "${2:-}" ]] && shift
      shift 1
      ;;
    --abandon)
      MODE="abandon"
      MODE_REASON="${2:-}"
      [[ -n "${2:-}" ]] && shift
      shift 1
      ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Validation ─────────────────────────────────────────────────────────────────

MISSING=()
[[ -z "$ISSUE_NUMBER"         ]] && MISSING+=("ISSUE")
[[ -z "$AGENT"                ]] && MISSING+=("--agent")
[[ -z "$SESSION_ID"           ]] && MISSING+=("--session")
[[ -z "$MODE"                 ]] && MISSING+=("--done | --blocked | --abandon")
[[ -z "${GITHUB_TOKEN:-}"     ]] && MISSING+=("GITHUB_TOKEN (env var)")

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
  curl -sf -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "$2" \
    "${GITHUB_API}/$1"
}

gh_patch() {
  curl -sf -X PATCH \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "$2" \
    "${GITHUB_API}/$1"
}

gh_delete() {
  curl -sf -X DELETE \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API}/$1" || true
}

# ── Fetch issue ────────────────────────────────────────────────────────────────

echo "Fetching issue #${ISSUE_NUMBER}..."
ISSUE_JSON="$(gh_get "repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}")"
ISSUE_TITLE="$(echo "$ISSUE_JSON" | grep -o '"title":"[^"]*"' | head -1 | sed 's/"title":"//;s/"//')"
EXISTING_LABELS="$(echo "$ISSUE_JSON" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')"
CURRENT_CLAIM="$(echo "$EXISTING_LABELS" | grep '^claimed:' || true)"

echo "  Title:        $ISSUE_TITLE"
echo "  Current claim: ${CURRENT_CLAIM:-none}"

# ── Verify claim ownership ─────────────────────────────────────────────────────

if [[ -z "$CURRENT_CLAIM" ]]; then
  echo "WARNING: Issue #${ISSUE_NUMBER} has no claim label — releasing anyway."
elif [[ "$CURRENT_CLAIM" != "$CLAIM_LABEL" && "$FORCE" == "false" ]]; then
  echo "ERROR: Issue #${ISSUE_NUMBER} is claimed by '$CURRENT_CLAIM', not '$CLAIM_LABEL'." >&2
  echo "  Use --force to release it anyway (e.g. recovering an abandoned session)." >&2
  exit 1
fi

# ── Determine new status label and comment tone ────────────────────────────────

case "$MODE" in
  done)
    NEW_STATUS="status: review"
    EMOJI="✅"
    ACTION_LINE="Work complete. PR should be opened targeting \`main\`."
    CHECKOUT_STATUS="completed"
    ;;
  blocked)
    NEW_STATUS="status: blocked"
    EMOJI="🚧"
    ACTION_LINE="Issue returned to blocked state. Reason: ${MODE_REASON:-unspecified}"
    CHECKOUT_STATUS="paused"
    ;;
  abandon)
    NEW_STATUS="status: ready"
    EMOJI="↩️"
    ACTION_LINE="Session abandoned. Issue returned to Ready for another agent."
    CHECKOUT_STATUS="abandoned"
    ;;
esac

# ── Update labels ──────────────────────────────────────────────────────────────

echo "Updating labels..."

# Remove claim and old status labels, add new status
CLEAN_LABELS="$(echo "$EXISTING_LABELS" | grep -v '^claimed:' | grep -v '^status:' || true)"
LABELS_JSON="[$(echo "$CLEAN_LABELS" | grep -v '^$' | sed 's/.*/\"&\"/' | paste -sd ',' -)]"

if [[ "$LABELS_JSON" == "[]" ]] || [[ "$LABELS_JSON" == "[\"\"]" ]]; then
  LABELS_JSON="[\"${NEW_STATUS}\"]"
else
  LABELS_JSON="${LABELS_JSON%]},\"${NEW_STATUS}\"]"
fi

gh_patch "repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}" \
  "{\"labels\":${LABELS_JSON}}" > /dev/null

echo "  Labels updated → $NEW_STATUS"

# ── Call agent-checkout ────────────────────────────────────────────────────────

echo "Logging session end..."

"${REPO_ROOT}/scripts/agent-checkout.sh" "$SESSION_ID" \
  --status "$CHECKOUT_STATUS" \
  --summary "${SUMMARY:-${MODE_REASON:-${MODE}}}" \
  --issues "$ISSUE_NUMBER" \
  $([ "$MODE" == "done" ] && echo "--keep-worktree" || true)

# ── Post comment on issue ──────────────────────────────────────────────────────

SUMMARY_LINE=""
[[ -n "$SUMMARY" ]] && SUMMARY_LINE="**Summary:** ${SUMMARY}"
REASON_LINE=""
[[ -n "$MODE_REASON" ]] && REASON_LINE="**Reason:** ${MODE_REASON}"

COMMENT_BODY="${EMOJI} **Agent Session Ended** — \`${AGENT}\` (session \`${SESSION_ID}\`)

${ACTION_LINE}
${SUMMARY_LINE}
${REASON_LINE}

| Field | Value |
|---|---|
| Agent | \`${AGENT}\` |
| Session | \`${SESSION_ID}\` |
| Status | ${CHECKOUT_STATUS} |"

if [[ "$MODE" == "done" ]]; then
  BRANCH="agent/${AGENT}/issue-${ISSUE_NUMBER}"
  COMMENT_BODY="${COMMENT_BODY}
| Branch | \`${BRANCH}\` |

**Next step:** Open a PR from \`${BRANCH}\` → \`main\`"
fi

gh_post "repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}/comments" \
  "{\"body\":$(echo "$COMMENT_BODY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" > /dev/null

echo "  Comment posted on issue #${ISSUE_NUMBER}."

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
printf "║  ISSUE RELEASED %-45s ║\n" "($MODE)"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Issue   : #%-48s ║\n" "${ISSUE_NUMBER} — ${ISSUE_TITLE:0:42}"
printf "║  Status  : %-46s ║\n" "$NEW_STATUS"
printf "║  Session : %-46s ║\n" "$SESSION_ID"
if [[ "$MODE" == "done" ]]; then
  echo "╠══════════════════════════════════════════════════════════════╣"
  printf "║  Open PR : agent/%-s → main\n" "${AGENT}/issue-${ISSUE_NUMBER}"
  echo "║  Then: ./scripts/agent-release.sh will be called by CI      ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
