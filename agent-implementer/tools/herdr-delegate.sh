#!/usr/bin/env bash
#
# herdr-delegate.sh — provision an isolated git worktree + Herdr workspace/tabs
# and launch a coding agent into it, for the fix-simple-issues-implementer
# skill's Step 1.
#
# Usage:
#   ./tools/herdr-delegate.sh <issue-number> [--agent <name>] [--no-agent]
#
# Requires: git, herdr, jq. Optionally uses `gh` to pull the real issue
# title (falls back to a generic label if `gh` isn't available or the
# lookup fails — the workflow must still work offline / without GitHub CLI).
#
# Verified against herdr 0.7.0 (protocol 14). herdr CLI responses are
# JSON-RPC shaped: {"id":"cli:<cmd>","result":{...}} on success,
# {"error":{"code":...,"message":...}} + exit 1 on failure. Ids therefore
# live under `.result.*` — never at the top level, where `.id` is the
# command name.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

err() { printf 'herdr-delegate: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

need_bin() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# jq_field <json> <path> <what> — extract a required field or die loudly.
jq_field() {
  local json="$1" path="$2" what="$3" value
  value="$(printf '%s' "$json" | jq -r "${path} // empty" 2>/dev/null || true)"
  [ -n "$value" ] || die "could not parse ${what} from herdr output: ${json}"
  printf '%s' "$value"
}

usage() {
  cat <<'EOF'
Usage: herdr-delegate.sh <issue-number> [--agent <name>] [--no-agent] [--no-focus]

  <issue-number>   Numeric GitHub issue id (e.g. 42)
  --agent <name>   Agent binary to launch in the Herdr agent tab (default: claude)
  --no-agent       Provision the workspace/tabs but don't auto-start an agent
  --no-focus       Provision in the background instead of surfacing the new
                   agent workspace when the run finishes

Prints, on success, a single line of JSON to stdout:
  {"issue":42,"branch":"fix/issue-42","worktree":"...","workspace_id":"w7",
   "agent_tab_id":"w7:t2","services_tab_id":"w7:t1","agent_pane_id":"w7:p3"}
EOF
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

[ "$#" -ge 1 ] || { usage; exit 1; }

ISSUE_NUM=""
AGENT_NAME="claude"
START_AGENT=1
FOCUS=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent)
      [ "$#" -ge 2 ] || die "--agent requires a value"
      AGENT_NAME="$2"; shift 2 ;;
    --no-agent)
      START_AGENT=0; shift ;;
    --no-focus)
      FOCUS=0; shift ;;
    ''|*[!0-9]*)
      die "issue number must be a positive integer, got: '$1'" ;;
    *)
      [ -z "$ISSUE_NUM" ] || die "unexpected argument: $1"
      ISSUE_NUM="$1"; shift ;;
  esac
done

[ -n "$ISSUE_NUM" ] || die "missing issue number"

need_bin git
need_bin herdr
need_bin jq

# ---------------------------------------------------------------------------
# Resolve repo context
# ---------------------------------------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "not inside a git repository"
cd "$REPO_ROOT"

PROJECT_NAME="$(basename "$REPO_ROOT")"
BRANCH="fix/issue-${ISSUE_NUM}"
WORKTREE_DIR="worktrees/${PROJECT_NAME}-issue-${ISSUE_NUM}"
WORKTREE_PATH="${REPO_ROOT}/${WORKTREE_DIR}"

# ---------------------------------------------------------------------------
# Fetch issue title (best-effort — never fatal)
# ---------------------------------------------------------------------------

ISSUE_TITLE=""
if command -v gh >/dev/null 2>&1; then
  ISSUE_TITLE="$(gh issue view "$ISSUE_NUM" --json title -q .title 2>/dev/null || true)"
fi
[ -n "$ISSUE_TITLE" ] || ISSUE_TITLE="Issue #${ISSUE_NUM}"

# slug for labels/workspace names: lowercase, non-alnum -> '-', trim dashes
SLUG="$(printf '%s' "$ISSUE_TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
  | cut -c1-40)"
[ -n "$SLUG" ] || SLUG="untitled"

WORKSPACE_LABEL="${PROJECT_NAME}-issue-${ISSUE_NUM}-${SLUG}"

# ---------------------------------------------------------------------------
# Guard rails: don't clobber an existing worktree/branch
# ---------------------------------------------------------------------------

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  die "branch '${BRANCH}' already exists — resolve or remove it before retrying"
fi

if [ -d "$WORKTREE_PATH" ]; then
  die "worktree dir already exists: ${WORKTREE_DIR} — resolve or remove it before retrying"
fi

mkdir -p "${REPO_ROOT}/worktrees"

# ---------------------------------------------------------------------------
# Cleanup on failure: don't leave a half-provisioned worktree behind.
# `herdr worktree remove --workspace` tears down both the checkout and the
# workspace in one call; the git fallbacks cover a herdr-side failure.
# ---------------------------------------------------------------------------

WORKSPACE_ID=""
cleanup_on_error() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$WORKSPACE_ID" ]; then
    err "failure detected — rolling back worktree ${WORKTREE_DIR}"
    herdr worktree remove --workspace "$WORKSPACE_ID" --force >/dev/null 2>&1 || true
    git worktree remove --force "$WORKTREE_PATH" >/dev/null 2>&1 || true
    git worktree prune >/dev/null 2>&1 || true
    git branch -D "$BRANCH" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup_on_error EXIT

# ---------------------------------------------------------------------------
# 1. Worktree + workspace (one call — herdr creates the git worktree itself)
# ---------------------------------------------------------------------------

err "creating worktree ${WORKTREE_DIR} on branch ${BRANCH}"
WORKTREE_JSON="$(herdr worktree create \
  --cwd "$REPO_ROOT" \
  --branch "$BRANCH" \
  --path "$WORKTREE_PATH" \
  --label "$WORKSPACE_LABEL" \
  --no-focus \
  --json)" \
  || die "herdr worktree create failed"

WORKSPACE_ID="$(jq_field "$WORKTREE_JSON" '.result.workspace.workspace_id' 'workspace id')"
SERVICES_TAB_ID="$(jq_field "$WORKTREE_JSON" '.result.tab.tab_id' 'services tab id')"
SERVICES_PANE_ID="$(jq_field "$WORKTREE_JSON" '.result.root_pane.pane_id' 'services pane id')"

# ---------------------------------------------------------------------------
# 2. Services tab — reuse the workspace's initial tab, don't create a spare
# ---------------------------------------------------------------------------

err "configuring services tab ${SERVICES_TAB_ID}"
herdr tab rename "$SERVICES_TAB_ID" "services" >/dev/null \
  || die "herdr tab rename (services) failed"
herdr pane run "$SERVICES_PANE_ID" "./vendor/bin/sail up -d && npm run dev" >/dev/null \
  || die "herdr pane run (services) failed"

# ---------------------------------------------------------------------------
# 3. Agent tab
# ---------------------------------------------------------------------------

err "creating agent tab"
AGENT_TAB_JSON="$(herdr tab create \
  --workspace "$WORKSPACE_ID" \
  --cwd "$WORKTREE_PATH" \
  --label "agent" \
  --no-focus)" \
  || die "herdr tab create (agent) failed"

AGENT_TAB_ID="$(jq_field "$AGENT_TAB_JSON" '.result.tab.tab_id' 'agent tab id')"
AGENT_TAB_ROOT_PANE="$(jq_field "$AGENT_TAB_JSON" '.result.root_pane.pane_id' 'agent tab root pane id')"

# ---------------------------------------------------------------------------
# 4. Launch the agent into the agent tab
# ---------------------------------------------------------------------------

AGENT_PANE_ID=""
if [ "$START_AGENT" -eq 1 ]; then
  need_bin "$AGENT_NAME"

  PROMPT="Implement issue #${ISSUE_NUM}: ${ISSUE_TITLE}. Follow the fix-simple-issues-implementer skill from Step 2 onward (Implement / Validate / Log / Review). Do not commit or open a PR."

  err "starting agent '${AGENT_NAME}' in tab ${AGENT_TAB_ID}"
  AGENT_JSON="$(herdr agent start "$AGENT_NAME" \
    --workspace "$WORKSPACE_ID" \
    --tab "$AGENT_TAB_ID" \
    --cwd "$WORKTREE_PATH" \
    --no-focus \
    -- "$AGENT_NAME" "$PROMPT")" \
    || die "herdr agent start failed"

  AGENT_PANE_ID="$(jq_field "$AGENT_JSON" '.result.agent.pane_id' 'agent pane id')"

  # `agent start --tab` splits a fresh pane into the tab, leaving the tab's
  # original empty shell pane behind. Drop it so the tab is just the agent —
  # but only if the agent pane is actually still alive. An agent that exits
  # immediately (bad binary, bad argv) would otherwise leave a zero-pane tab
  # that herdr closes, taking the whole agent tab with it.
  if herdr pane get "$AGENT_PANE_ID" >/dev/null 2>&1; then
    herdr pane close "$AGENT_TAB_ROOT_PANE" >/dev/null 2>&1 || true
  else
    err "warning: agent pane ${AGENT_PANE_ID} exited immediately — keeping the tab's shell pane; check '${AGENT_NAME}' starts cleanly"
    AGENT_PANE_ID="$AGENT_TAB_ROOT_PANE"
  fi
else
  err "--no-agent set: workspace and tabs provisioned, agent not started"
  AGENT_PANE_ID="$AGENT_TAB_ROOT_PANE"
fi

# ---------------------------------------------------------------------------
# 5. Surface it. Intermediate steps run --no-focus to avoid yanking the caller
# around mid-provision; we focus once, at the end, so the run lands on the
# live agent. Non-fatal: a focus failure must not roll back a good workspace.
# ---------------------------------------------------------------------------

if [ "$FOCUS" -eq 1 ]; then
  herdr workspace focus "$WORKSPACE_ID" >/dev/null 2>&1 || true
  herdr tab focus "$AGENT_TAB_ID" >/dev/null 2>&1 || true
  if [ "$START_AGENT" -eq 1 ]; then
    herdr agent focus "$AGENT_PANE_ID" >/dev/null 2>&1 || true
  fi
fi

# herdr exports HERDR_PANE_ID into every pane it owns. Its absence means the
# caller is in a plain terminal: provisioning still lands in the herdr server,
# but nothing is on screen until they attach.
if [ -z "${HERDR_PANE_ID:-}" ]; then
  err "note: not running inside Herdr — run 'herdr' to attach; the new workspace is ${WORKSPACE_ID} (tab ${AGENT_TAB_ID})"
fi

trap - EXIT

jq -n -c \
  --arg issue "$ISSUE_NUM" \
  --arg branch "$BRANCH" \
  --arg worktree "$WORKTREE_PATH" \
  --arg workspace_id "$WORKSPACE_ID" \
  --arg agent_tab_id "$AGENT_TAB_ID" \
  --arg services_tab_id "$SERVICES_TAB_ID" \
  --arg agent_pane_id "$AGENT_PANE_ID" \
  '{issue: ($issue|tonumber), branch: $branch, worktree: $worktree,
    workspace_id: $workspace_id, agent_tab_id: $agent_tab_id,
    services_tab_id: $services_tab_id, agent_pane_id: $agent_pane_id}'
