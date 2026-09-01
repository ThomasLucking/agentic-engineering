# agent-workflow

Claude Code skills for handing a single GitHub issue to an agent, implementing it
in an isolated worktree, and getting it back review-ready — uncommitted, with a
second-pass code review.

The human owns the commit and the PR. The agents never do.

## Layout

```
agent-implementer/
  SKILL.md              # provisions a git worktree, implements, validates, reviews
```

`~/.claude/skills/agent-implementer` is a symlink into this repo — edit the
skill here, not the installed copy.

## Skills

### `fix-simple-issues-implementer`

Takes one well-scoped issue and runs it end to end:

1. **Provision** — isolated worktree at `worktrees/<project>-issue-<N>` on branch
   `fix/issue-<N>`, with services (`sail up -d`, `npm run dev`) running.
2. **Implement** — stays in scope; escalates to the `grill` skill when acceptance
   criteria, approach, or technical detail are ambiguous.
3. **Validate** — `./vendor/bin/pint`, `./vendor/bin/phpstan analyse`, and
   `./vendor/bin/sail artisan test` must be clean.
4. **Review pass** — spawns an Opus agent that chains into the `/code-review`
   skill via the `Skill` tool (rather than inlining its instructions), fixes
   every Critical/Important finding, then re-runs validation.
5. **Stop** — leaves everything uncommitted.

## Tests

None currently — the hermetic Herdr-delegate suite and the agent-diff-reviewer
recall eval were both removed along with the code they tested. `/code-review` is
Anthropic's shipped skill, not something this repo evaluates.

## Assumptions

The validation and services commands are Laravel-specific (Sail, Pint, PHPStan,
Vite). Point steps 1 and 3 at your own toolchain to use these skills elsewhere.
