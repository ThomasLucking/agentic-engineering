# agent-workflow

Claude Code skills for handing a single GitHub issue to an agent, implementing it
in an isolated worktree, and getting it back review-ready — uncommitted, with a
second-pass code review.

The human owns the commit and the PR. The agents never do.

## Layout

```
agent-implement-laravel/
  SKILL.md              # Laravel/Sail-specific: worktree, implement, validate, review
agent-implement-generic/
  SKILL.md              # stack-agnostic: detects the project's own tooling
```

`~/.claude/skills/agent-implement-laravel` and
`~/.claude/skills/agent-implement-generic` are symlinks into this repo — edit
the skills here, not the installed copies.

## Skills

### `fix-simple-issues-implementer` (`agent-implement-laravel`)

Laravel/Sail-specific. Takes one well-scoped issue and runs it end to end:

1. **Provision** — isolated worktree at `worktrees/<project>-issue-<N>` on branch
   `fix/issue-<N>`, with `sail up -d` and `npm run dev` running.
2. **Implement** — stays in scope; escalates to the `grill-with-docs` skill when
   acceptance criteria, approach, or technical detail are ambiguous.
3. **Self-verify** — runs the `tdd` skill to red-green the fix before handing off.
4. **Validate** — `./vendor/bin/pint`, `./vendor/bin/phpstan analyse`, and
   `./vendor/bin/sail artisan test` must be clean.
5. **Review pass** — spawns an Opus agent that chains into the `/code-review`
   skill via the `Skill` tool (rather than inlining its instructions), fixes
   every Critical/Important finding, then re-runs validation.
6. **Stop** — leaves everything uncommitted.

### `fix-simple-issues-implementer-generic` (`agent-implement-generic`)

Same flow, stack-agnostic. Detects the project's own dev/start command
(`docker-compose.yml`, `Makefile`, `package.json` scripts, `Procfile`, …) and
its own format/lint/test tooling via `agent-state test`/`agent-state lint`
(Jest, Vitest, Mocha, pytest, PHPUnit, cargo, go, ESLint, golangci-lint,
clippy, PHPStan, ruff, etc.) instead of assuming Laravel.

## Tests

None currently — the hermetic Herdr-delegate suite and the agent-diff-reviewer
recall eval were both removed along with the code they tested. `/code-review` is
Anthropic's shipped skill, not something this repo evaluates.

## Assumptions

`agent-implement-laravel` is Laravel-specific (Sail, Pint, PHPStan, Vite). Use
`agent-implement-generic` for any other stack.
