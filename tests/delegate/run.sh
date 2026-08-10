#!/usr/bin/env bash
#
# Tests for agent-implementer/tools/herdr-delegate.sh
#
# Hermetic: `herdr`, `gh` and the agent binary are stubs on PATH (see stubs/),
# and every case runs in a throwaway git repo. Nothing touches a real Herdr
# server, GitHub, or this repo's worktrees.
#
#   bash tests/delegate/run.sh

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/agent-implementer/tools/herdr-delegate.sh"
STUBS="$HERE/stubs"

. "$ROOT/tests/lib/assert.sh"

chmod +x "$STUBS"/* "$SCRIPT" 2>/dev/null

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# --- helpers -----------------------------------------------------------------

new_repo() { # → prints repo path
  d="$(mktemp -d "$TMPROOT/repo.XXXXXX")"
  git -C "$d" init -q -b main
  printf 'seed\n' > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" -c user.email=t@example.com -c user.name=test commit -qm init
  printf '%s' "$d"
}

OUT=""; ERR=""; STATUS=0; CALLS=""; STATE=""
run_delegate() { # <repo> <args...>
  repo="$1"; shift
  STATE="$repo/.stub-state"
  rm -rf "$STATE"; mkdir -p "$STATE"
  OUT="$(cd "$repo" && HERDR_STUB_STATE="$STATE" PATH="$STUBS:$PATH" \
          bash "$SCRIPT" "$@" 2>"$repo/.stderr")"
  STATUS=$?
  ERR="$(cat "$repo/.stderr" 2>/dev/null)"
  CALLS="$(cat "$STATE/calls.log" 2>/dev/null)"
}

branch_exists() { git -C "$1" show-ref --verify --quiet "refs/heads/$2"; }

printf '\nherdr-delegate.sh\n'

# --- argument handling -------------------------------------------------------

t_start "no arguments → usage, exit 1"
  repo="$(new_repo)"; run_delegate "$repo"
  assert_exit "$STATUS" 1 "status"
  assert_contains "$OUT" "Usage: herdr-delegate.sh" "usage text"
t_end

t_start "--help → usage, exit 0"
  repo="$(new_repo)"; run_delegate "$repo" --help
  assert_exit "$STATUS" 0 "status"
  assert_contains "$OUT" "Usage: herdr-delegate.sh" "usage text"
t_end

t_start "non-numeric issue number is rejected"
  repo="$(new_repo)"; run_delegate "$repo" forty-two
  assert_exit "$STATUS" 1 "status"
  assert_contains "$ERR" "must be a positive integer" "error message"
t_end

t_start "--agent without a value is rejected"
  repo="$(new_repo)"; run_delegate "$repo" 42 --agent
  assert_exit "$STATUS" 1 "status"
  assert_contains "$ERR" "--agent requires a value" "error message"
t_end

t_start "a second issue number is rejected"
  repo="$(new_repo)"; run_delegate "$repo" 42 43
  assert_exit "$STATUS" 1 "status"
  assert_contains "$ERR" "unexpected argument" "error message"
t_end

# --- environment preconditions ----------------------------------------------

t_start "outside a git repo → refuses"
  bare="$(mktemp -d "$TMPROOT/bare.XXXXXX")"
  STATE="$bare/.stub-state"; mkdir -p "$STATE"
  OUT="$(cd "$bare" && HERDR_STUB_STATE="$STATE" PATH="$STUBS:$PATH" \
          bash "$SCRIPT" 42 --no-agent 2>"$bare/.stderr")"
  STATUS=$?
  assert_exit "$STATUS" 1 "status"
  assert_contains "$(cat "$bare/.stderr")" "not inside a git repository" "error message"
t_end

t_start "missing herdr binary → refuses before touching the repo"
  repo="$(new_repo)"
  STATE="$repo/.stub-state"; mkdir -p "$STATE"
  OUT="$(cd "$repo" && HERDR_STUB_STATE="$STATE" PATH="/usr/bin:/bin" \
          bash "$SCRIPT" 42 --no-agent 2>"$repo/.stderr")"
  STATUS=$?
  assert_exit "$STATUS" 1 "status"
  assert_contains "$(cat "$repo/.stderr")" "required command not found: herdr" "error message"
  assert_no_file "$repo/worktrees" "no worktrees dir created"
t_end

# --- happy path --------------------------------------------------------------

t_start "--no-agent --no-focus provisions worktree + tabs and prints one JSON line"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; export GH_STUB_FAIL
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_FAIL
  assert_exit "$STATUS" 0 "status"
  assert_eq "$(printf '%s' "$OUT" | wc -l | tr -d ' ')" "0" "stdout holds no embedded newlines (single line)"
  printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 || t_fail "stdout is not valid JSON: $OUT"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.issue')" "42" ".issue"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.branch')" "fix/issue-42" ".branch"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.workspace_id')" "w1" ".workspace_id"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.services_tab_id')" "w1:t1" ".services_tab_id"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.agent_tab_id')" "w1:t2" ".agent_tab_id"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.agent_pane_id')" "w1:p2" ".agent_pane_id falls back to the tab shell pane"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.worktree')" "$(cd "$repo" && pwd -P)/worktrees/$(basename "$repo")-issue-42" ".worktree"
  assert_file "$repo/worktrees/$(basename "$repo")-issue-42/README.md" "worktree checked out"
  branch_exists "$repo" "fix/issue-42" || t_fail "branch fix/issue-42 not created"
  assert_not_contains "$CALLS" "agent start" "no agent started"
  assert_not_contains "$CALLS" "workspace focus" "--no-focus honoured"
  assert_not_contains "$CALLS" "tab focus" "--no-focus honoured"
t_end

t_start "services tab is renamed and runs sail + vite"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; export GH_STUB_FAIL
  run_delegate "$repo" 7 --no-agent --no-focus
  unset GH_STUB_FAIL
  assert_contains "$CALLS" "tab rename w1:t1 services" "services tab renamed"
  assert_contains "$CALLS" "pane run w1:p1 ./vendor/bin/sail up -d && npm run dev" "services command"
t_end

t_start "diagnostics go to stderr, never stdout"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; export GH_STUB_FAIL
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_FAIL
  assert_not_contains "$OUT" "creating worktree" "stdout free of progress noise"
  assert_contains "$ERR" "creating worktree" "progress on stderr"
t_end

t_start "agent is launched with the issue in its prompt, and the spare shell pane is closed"
  repo="$(new_repo)"
  GH_STUB_TITLE="Trial expiry check lets expired accounts through"; export GH_STUB_TITLE
  run_delegate "$repo" 42 --agent fakeagent --no-focus
  unset GH_STUB_TITLE
  assert_exit "$STATUS" 0 "status"
  assert_contains "$CALLS" "agent start fakeagent" "agent started"
  assert_contains "$CALLS" "Implement issue #42: Trial expiry check" "prompt carries issue number and title"
  assert_contains "$CALLS" "Do not commit or open a PR" "prompt carries the no-commit rule"
  assert_contains "$CALLS" "pane close w1:p2" "spare shell pane closed"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.agent_pane_id')" "w1:p3" ".agent_pane_id is the agent pane"
t_end

t_start "agent that dies at startup keeps the shell pane and warns"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; HERDR_STUB_DEAD_PANE=1; export GH_STUB_FAIL HERDR_STUB_DEAD_PANE
  run_delegate "$repo" 42 --agent fakeagent --no-focus
  unset GH_STUB_FAIL HERDR_STUB_DEAD_PANE
  assert_exit "$STATUS" 0 "status"
  assert_contains "$ERR" "exited immediately" "warning emitted"
  assert_not_contains "$CALLS" "pane close" "tab's shell pane kept"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.agent_pane_id')" "w1:p2" ".agent_pane_id falls back"
t_end

t_start "without --no-focus the run surfaces the workspace, tab and agent"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; export GH_STUB_FAIL
  run_delegate "$repo" 42 --agent fakeagent
  unset GH_STUB_FAIL
  assert_exit "$STATUS" 0 "status"
  assert_contains "$CALLS" "workspace focus w1" "workspace focused"
  assert_contains "$CALLS" "tab focus w1:t2" "agent tab focused"
  assert_contains "$CALLS" "agent focus w1:p3" "agent pane focused"
t_end

# --- issue title / slug ------------------------------------------------------

t_start "gh title becomes a slugged workspace label"
  repo="$(new_repo)"
  GH_STUB_TITLE="Fix: Broken Widget!! (urgent)"; export GH_STUB_TITLE
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_TITLE
  assert_eq "$(cat "$STATE/workspace_label")" "$(basename "$repo")-issue-42-fix-broken-widget-urgent" "workspace label"
t_end

t_start "slug is capped at 40 chars"
  repo="$(new_repo)"
  GH_STUB_TITLE="This issue title is deliberately far longer than forty characters in total"
  export GH_STUB_TITLE
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_TITLE
  label="$(cat "$STATE/workspace_label")"
  slug="${label##*-issue-42-}"
  assert_eq "$(printf '%s' "$slug" | wc -c | tr -d ' ')" "40" "slug length"
t_end

t_start "gh failure falls back to a generic label (works offline)"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; export GH_STUB_FAIL
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_FAIL
  assert_exit "$STATUS" 0 "status"
  assert_eq "$(cat "$STATE/workspace_label")" "$(basename "$repo")-issue-42-issue-42" "workspace label"
t_end

# --- guard rails -------------------------------------------------------------

t_start "existing branch → refuses without calling herdr"
  repo="$(new_repo)"
  git -C "$repo" branch fix/issue-42
  run_delegate "$repo" 42 --no-agent --no-focus
  assert_exit "$STATUS" 1 "status"
  assert_contains "$ERR" "already exists" "error message"
  assert_eq "$CALLS" "" "herdr never invoked"
t_end

t_start "existing worktree dir → refuses without calling herdr"
  repo="$(new_repo)"
  mkdir -p "$repo/worktrees/$(basename "$repo")-issue-42"
  run_delegate "$repo" 42 --no-agent --no-focus
  assert_exit "$STATUS" 1 "status"
  assert_contains "$ERR" "worktree dir already exists" "error message"
  assert_eq "$CALLS" "" "herdr never invoked"
t_end

# --- rollback ----------------------------------------------------------------

t_start "failure mid-provision rolls back worktree, branch and workspace"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; HERDR_STUB_FAIL="tab create"; export GH_STUB_FAIL HERDR_STUB_FAIL
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_FAIL HERDR_STUB_FAIL
  [ "$STATUS" -ne 0 ] || t_fail "status: expected non-zero, got 0"
  assert_contains "$ERR" "rolling back" "rollback announced"
  assert_contains "$CALLS" "worktree remove --workspace w1 --force" "herdr workspace torn down"
  assert_no_file "$repo/worktrees/$(basename "$repo")-issue-42" "worktree removed"
  branch_exists "$repo" "fix/issue-42" && t_fail "branch fix/issue-42 left behind"
  assert_not_contains "$(git -C "$repo" worktree list)" "issue-42" "no orphan worktree registration"
t_end

t_start "rollback also works when herdr's own removal fails"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; HERDR_STUB_FAIL="pane run"; export GH_STUB_FAIL HERDR_STUB_FAIL
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_FAIL HERDR_STUB_FAIL
  [ "$STATUS" -ne 0 ] || t_fail "status: expected non-zero, got 0"
  assert_no_file "$repo/worktrees/$(basename "$repo")-issue-42" "worktree removed by the git fallback"
  branch_exists "$repo" "fix/issue-42" && t_fail "branch fix/issue-42 left behind"
t_end

t_start "regression: ids at the top level instead of .result → fails loudly and rolls back"
  repo="$(new_repo)"
  GH_STUB_FAIL=1; HERDR_STUB_TOPLEVEL_IDS=1; export GH_STUB_FAIL HERDR_STUB_TOPLEVEL_IDS
  run_delegate "$repo" 42 --no-agent --no-focus
  unset GH_STUB_FAIL HERDR_STUB_TOPLEVEL_IDS
  assert_exit "$STATUS" 1 "status"
  assert_contains "$ERR" "could not parse workspace id" "error message"
  # KNOWN FAILURE — genuine bug, not a broken test. jq_field's `die` runs inside
  # a command substitution, so it kills the subshell, not the script; set -e then
  # exits with WORKSPACE_ID still empty, and cleanup_on_error's
  # `[ -n "$WORKSPACE_ID" ]` guard skips the rollback entirely. herdr has already
  # created the worktree and branch by that point, so both are orphaned.
  assert_no_file "$repo/worktrees/$(basename "$repo")-issue-42" "worktree removed"
  branch_exists "$repo" "fix/issue-42" && t_fail "branch fix/issue-42 left behind"
t_end

t_summary "delegate"
