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

### 2. Implement (TDD)

Test-first, not test-after: a test written against code that already
exists tends to describe whatever was built rather than pin down what was
required. Ambiguity in the issue also surfaces earlier this way — writing
a concrete test forces you to commit to an interpretation before any code
exists to anchor you to it.

**2a. Write failing tests first.**

Read the relevant files first — existing patterns, interfaces, naming —
so the tests aren't written blind against an API that doesn't exist yet.
This is a read-through, not an implementation pass; don't write
production code here.

Use the `grill-with-docs` skill — don't guess — when writing the test
makes any of this apparent:

- acceptance criteria or expected behavior are ambiguous
- two reasonable approaches exist and the issue doesn't pick one
- technical detail is missing (schema, API shape, edge cases)
- the issue is bigger than stated (expand, split, or stop?)

Use the Skill tool to load the `tdd` skill and follow it to write or
extend tests that pin down the issue's acceptance criteria.

Run the tests and confirm they fail (red). A test that doesn't fail
before the fix isn't testing anything — flag it and rewrite it.

**2b. Implement.**

Write the minimum code needed to make the tests pass (green), staying
inside the issue's scope. Don't expand beyond what the tests require.

If implementation reveals scope beyond what the tests anticipated, stop and use `grill-with-docs` rather than expanding silently.

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
