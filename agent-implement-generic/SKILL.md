---
name: fix-simple-issues-implementer-generic
description: >
  Implements a single, well-scoped GitHub issue in an isolated worktree,
  validates it, and has an Opus agent run /code-review on the diff.
  Stack-agnostic — detects the project's own test/lint/format tooling
  instead of assuming Laravel. Trigger on "fix issue #42", "implement
  issue 17", or an issue labeled "Agent". Never commit or open a PR.
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

Get it runnable so you can verify, not just read. Use whatever this
project actually uses to start — check for `docker-compose.yml`,
`Makefile`, `package.json` scripts, `Procfile`, etc., and run the
project's own dev/start command in the worktree (e.g. `docker compose up
-d`, `make dev`, `npm run dev`, `poetry run <cmd>`). If unsure, use
`agent-state procs` to see what's already running, or ask.

### 2. Implement

Stay inside the issue's scope. Use the `grill-with-docs` skill — don't
guess — when:

- acceptance criteria or expected behavior are ambiguous
- two reasonable approaches exist and the issue doesn't pick one
- technical detail is missing (schema, API shape, edge cases)
- mid-way you find the issue is bigger than stated (expand, split, or stop?)

### 3. Self-verify (TDD)

Before validating or requesting review, use the Skill tool to load the
`tdd` skill and follow it to verify your own implementation — write or
extend tests that pin down the issue's acceptance criteria, confirm they
fail without the fix and pass with it (red-green), and close any gap
between "the code runs" and "the behavior is proven." Don't hand off
unverified work.

### 4. Validate

Detect the project's own tooling rather than assuming a stack. Prefer
`agent-state test` and `agent-state lint` (auto-detects Jest, Vitest,
Mocha, pytest, PHPUnit, cargo, go, ESLint, golangci-lint, clippy, PHPStan,
ruff, etc.) — run `agent-state all --pretty` first if unsure what's
available. Fall back to reading `package.json` scripts, `Makefile`
targets, or config files (`pyproject.toml`, `Cargo.toml`, `composer.json`)
to find the project's format/lint/typecheck/test commands.

All of the following must be clean before it's done (skip any that don't
apply to this stack):

- **format** — e.g. `prettier --check`, `pint`, `black --check`, `gofmt -l`, `cargo fmt --check`
- **lint / static analysis** — e.g. `eslint`, `phpstan analyse`, `ruff check`, `clippy`, `golangci-lint run`
- **tests** — e.g. `npm test`, `pytest`, `cargo test`, `go test ./...`, `sail artisan test`

### 5. Review pass

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
every **Critical** and **Important** finding, then re-run the project's
format, lint, and test commands from step 4.

### 6. Stop

Leave everything uncommitted. No `git commit`, no PR — that's the human's
call.
