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

Don't run `git worktree` by hand. Delegate the whole infrastructure setup —
worktree creation, branch checkout, Herdr workspace, tabs, and agent
launch — to the orchestration script in `tools/`, run from the repo root:

```bash
./tools/herdr-delegate.sh <N>
```

This does, in order:
- `herdr worktree create` — makes `worktrees/<project>-issue-<N>` off a new
  `fix/issue-<N>` branch *and* the Herdr workspace scoped to it in one call,
  so parallel work on other issues never collides.
- Renames that workspace's initial tab to **services** and runs
  `./vendor/bin/sail up -d && npm run dev` in it via `herdr pane run`.
- Creates a second **agent** tab with `herdr tab create --cwd <worktree>`.
- Launches the coding agent into that tab via `herdr agent start`, seeded
  with the issue number/title and pointed at this skill's Step 2 onward.

The script prints a single JSON line on success — `workspace_id`,
`agent_tab_id`, `services_tab_id`, `agent_pane_id`, `branch`, `worktree` —
so you (or the agent itself, if launched from outside Herdr) can focus or
attach to the right pane:

```bash
herdr tab focus <agent_tab_id>       # e.g. w7:t2
herdr agent attach <agent_pane_id>   # e.g. w7:p3
```

If you're already the agent that `herdr-delegate.sh` launched, you're
already running inside the correct worktree and tab — skip straight to
Step 2.

Guard rails already handled by the script: it refuses to run if the
branch or worktree dir already exists, and on any provisioning failure it
rolls back via `herdr worktree remove --workspace <id> --force` plus a
`git worktree remove` / `git branch -D` fallback, so a failed run never
leaves an orphaned worktree, branch, or workspace behind.

Flags: `--agent <name>` picks the agent binary (default `claude`);
`--no-agent` provisions the workspace and tabs without starting one;
`--no-focus` provisions in the background instead of surfacing the new
workspace at the end of the run.

**Seeing the agents.** The whole point of this step is that every issue
becomes a workspace you can watch live. Two things have to be true:

1. **Be attached to Herdr.** The script talks to the Herdr *server*, so it
   works from any terminal — but if you run it from a plain shell, the
   workspace is created where you can't see it. Run `herdr` to attach to
   the persistent session; the new workspace is already there. The script
   prints a reminder when it detects it isn't running inside a Herdr pane.
2. **Keep the `claude` integration installed.** `herdr integration status`
   should show `claude: current`. That hook is what reports each agent's
   working / idle / blocked state up to the workspace switcher — without
   it the panes still run, but every agent shows as `unknown`. Reinstall
   with `herdr integration install claude`.

Once attached, `herdr agent list` shows every running issue agent by name
and pane, across all workspaces.

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

Give it the worktree path (the `worktree` field of the
`tools/herdr-delegate.sh` JSON output), the
issue number, and the log path. Wait for its report. Fix anything it
flags as a correctness bug, then re-run pint and phpstan. Append
unresolved or rejected findings to the log under `## Review notes` with a
one-line reason.

### 6. Stop

Leave everything uncommitted. No `git commit`, no PR — that's the
human's call. The Herdr workspace and its worktree stay up for the human
to inspect; tearing it down (`herdr worktree remove --workspace <id>`,
which closes the workspace and drops the checkout together) is also the
human's call, not this skill's.
