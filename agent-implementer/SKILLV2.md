---
name: fix-simple-issues-implementer
description: >
  Implements a single, well-scoped GitHub issue in an isolated worktree
  provisioned as a Herdr workspace, validates it, logs it for human review,
  and has a Haiku agent review the diff. Trigger on "fix issue #42",
  "implement issue 17", or an issue labeled "Agent". Never commit or open
  a PR.
---

## Purpose

Take one issue, implement it in isolation, hand it back review-ready. The
human owns the commit and the PR.

## Workflow

### 1. Provision (worktree + Herdr workspace)

Never run `git worktree` by hand. From the repo root:

```bash
./tools/herdr-delegate.sh <N>
```

It does, in order:
- `herdr worktree create` — `worktrees/<project>-issue-<N>` off a new
  `fix/issue-<N>` branch, plus the workspace scoped to it, in one call.
- Renames the initial tab **services**, runs `./vendor/bin/sail up -d &&
  npm run dev` there via `herdr pane run`.
- Creates an **agent** tab (`herdr tab create --cwd <worktree>`).
- Starts the coding agent in it (`herdr agent start`), seeded with the
  issue number/title and pointed at Step 2 onward.

On success it prints one JSON line — `workspace_id`, `agent_tab_id`,
`services_tab_id`, `agent_pane_id`, `branch`, `worktree` — for:

```bash
herdr tab focus <agent_tab_id>       # e.g. w7:t2
herdr agent attach <agent_pane_id>   # e.g. w7:p3
```

If you *are* the launched agent, you're already in the right worktree and
tab — go to Step 2.

Guard rails (handled by the script): refuses if the branch or worktree dir
exists; rolls back on any failure (`herdr worktree remove --workspace <id>
--force`, with `git worktree remove` / `git branch -D` fallback). No
orphans left behind.

Flags: `--agent <name>` (default `claude`), `--no-agent` (provision only),
`--no-focus` (provision in background).

**To see the agents**, both must hold:
1. Attached to Herdr — the script talks to the server, so it works from
   any shell, but a workspace created from a plain shell is invisible. Run
   `herdr` to attach; it's already there. The script warns when it detects
   it isn't running inside a Herdr pane.
2. `claude` integration installed — `herdr integration status` shows
   `claude: current`. Without it panes still run but every agent reads
   `unknown`. Fix: `herdr integration install claude`.

`herdr agent list` then shows every running issue agent by name and pane,
across workspaces.

### 2. Implement

Stay inside the issue's scope. Use the `grill` skill — don't guess — when:

- acceptance criteria or expected behavior are ambiguous
- two reasonable approaches exist and the issue doesn't pick one
- technical detail is missing (schema, API shape, edge cases)
- mid-way you find the issue is bigger than stated (expand, split, or stop?)

### 3. Validate

Both must be clean before it's done:

```bash
./vendor/bin/pint
./vendor/bin/phpstan analyse
```

### 4. Log

Write `docs/logs/issue-<N>-agent-trace.md`. Terse and scannable — bullets,
not paragraphs. A reviewer should orient in under a minute.

```markdown
# Issue #<N>: <short title>

## The issue
<2–3 lines: what was broken/missing and the root cause.>

## Changes
- `<file>` — <what changed> → <why>
- `<file>` — <what changed> → <why>

## How it fits together
<3–5 lines or a short list: which files/folders were touched and how they
connect to solve the issue. e.g. request → FormRequest validates →
Controller delegates → Service applies rule → Model persists.>
```

Rules: no change without a `why`. No paragraph over ~40 words. Skip
anything the diff already says plainly.

### 5. Review pass

After the log is written, spawn a review agent:

```
Agent(subagent_type: "general-purpose", model: "haiku",
      description: "Review issue #<N> changes",
      prompt: <see the `agent-diff-reviewer` skill>)
```

Give it the worktree path (the `worktree` field of the delegate script's
JSON), the issue number, and the log path. Wait for its report. Fix
anything it flags as a correctness bug, then re-run pint and phpstan.
Append unresolved or rejected findings to the log under `## Review notes`
with a one-line reason.

### 6. Stop

Leave everything uncommitted. No `git commit`, no PR — that's the human's
call. The workspace and worktree stay up for inspection; tearing them down
(`herdr worktree remove --workspace <id>`, which closes both together) is
also the human's call, not this skill's.
