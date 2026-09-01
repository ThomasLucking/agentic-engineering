---
name: fix-simple-issues-implementer
description: >
  Implements a single, well-scoped GitHub issue in an isolated worktree,
  validates it, and has an Opus agent run /code-review on the diff.
  Trigger on "fix issue #42", "implement issue 17", or an issue labeled
  "Agent". Never commit or open a PR.
---

## Purpose

Take one issue, implement it in isolation, hand it back review-ready. The
human owns the commit and the PR.

## Workflow

### 1. Worktree

All worktrees live under a `worktrees/` folder at the repo root — one per
issue, so parallel work never collides:

```bash
git worktree add worktrees/<project>-issue-<N> -b fix/issue-<N>
```

Get it runnable so you can verify, not just read:

```bash
./vendor/bin/sail up -d
npm run dev   # separate terminal
```

### 2. Implement

Stay inside the issue's scope. Use the `grill` skill — don't guess — when:

- acceptance criteria or expected behavior are ambiguous
- two reasonable approaches exist and the issue doesn't pick one
- technical detail is missing (schema, API shape, edge cases)
- mid-way you find the issue is bigger than stated (expand, split, or stop?)

### 3. Validate

All three must be clean before it's done:

```bash
./vendor/bin/pint
./vendor/bin/phpstan analyse
./vendor/bin/sail artisan test
```

### 4. Review pass

Spawn a review agent that chains into the `/code-review` skill itself —
don't inline its instructions here:

```
Agent(subagent_type: "general-purpose", model: "opus",
      description: "Review issue #<N> changes",
      prompt: "Use the Skill tool to load the `code-review` skill, then
                follow it against the diff in worktree <worktree path>
                for issue #<N>.")
```

Give it the worktree path and the issue number. Wait for its report. Fix
every **Critical** and **Important** finding, then re-run pint, phpstan,
and the test suite.

### 5. Stop

Leave everything uncommitted. No `git commit`, no PR — that's the human's
call.
