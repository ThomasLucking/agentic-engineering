# agent-workflow

Claude Code skills for handing a single GitHub issue to an agent, implementing it
in an isolated worktree, and getting it back review-ready — uncommitted, with a
trace log and a second-pass diff review.

The human owns the commit and the PR. The agents never do.

## Layout

```
agent-implementer/
  SKILL.md              # v1 — plain `git worktree` provisioning
  SKILLV2.md            # v2 — Herdr workspace provisioning (experimental)
  tools/
    herdr-delegate.sh   # worktree + Herdr workspace/tabs + agent launch
agent-diff-reviewer/
  SKILL.md              # read-only Haiku reviewer of the agent's diff
tests/
  delegate/             # hermetic shell tests for herdr-delegate.sh
  reviewer/             # planted-defect recall eval for agent-diff-reviewer
```

## Skills

### `fix-simple-issues-implementer`

Takes one well-scoped issue and runs it end to end:

1. **Provision** — isolated worktree at `worktrees/<project>-issue-<N>` on branch
   `fix/issue-<N>`, with services (`sail up -d`, `npm run dev`) running.
2. **Implement** — stays in scope; escalates to the `grill` skill when acceptance
   criteria, approach, or technical detail are ambiguous.
3. **Validate** — `./vendor/bin/pint` and `./vendor/bin/phpstan analyse` must be
   clean.
4. **Log** — writes `docs/logs/issue-<N>-agent-trace.md`: what broke, what
   changed and why, how the pieces connect. Bullets, no change without a `why`.
5. **Review pass** — spawns `agent-diff-reviewer` on Haiku, fixes correctness
   bugs it flags, re-runs validation, records rejected findings in the log.
6. **Stop** — leaves everything uncommitted.

Two variants exist. `SKILL.md` provisions with `git worktree` directly.
`SKILLV2.md` delegates provisioning to `tools/herdr-delegate.sh` so every issue
becomes a live [Herdr](https://github.com/) workspace you can watch — a
**services** tab and an **agent** tab — instead of a background process. Steps 2–6
are identical between them.

### `agent-diff-reviewer`

Read-only second pair of eyes, spawned as a Haiku subagent. Reads the issue, the
trace log, and the diff — plus surrounding file context and other call sites of
anything whose signature moved. Checks correctness, scope creep, breakage,
convention, and whether the log matches the diff. Skips style nits Pint already
enforces.

Reports one line per finding, most severe first:

```
[<file>:<line>][<Bug|Scope|Breakage|Convention|Log>][<problem → impact>]
```

Never edits, never commits.

## `tools/herdr-delegate.sh`

```bash
./tools/herdr-delegate.sh <issue-number> [--agent <name>] [--no-agent] [--no-focus]
```

Provisions the worktree, the Herdr workspace and its two tabs, and launches the
coding agent into the agent tab. Prints one JSON line on success:

```json
{"issue":42,"branch":"fix/issue-42","worktree":"...","workspace_id":"w7",
 "agent_tab_id":"w7:t2","services_tab_id":"w7:t1","agent_pane_id":"w7:p3"}
```

| Flag | Effect |
| --- | --- |
| `--agent <name>` | Agent binary to launch (default `claude`) |
| `--no-agent` | Provision workspace and tabs, start nothing |
| `--no-focus` | Provision in the background instead of surfacing the workspace |

**Requires:** `git`, `herdr`, `jq`. Uses `gh` for the real issue title when
available, falling back to a generic label so the workflow still works offline.

**Guard rails:** refuses to run if the branch or worktree dir already exists, and
rolls back the workspace, worktree, and branch when a herdr call fails mid-run.

One gap, caught by `tests/delegate`: if a herdr response *parses* wrong rather
than failing outright, `jq_field`'s `die` runs inside a command substitution and
kills the subshell instead of the script. `set -e` then exits with `WORKSPACE_ID`
still empty, so the rollback's `[ -n "$WORKSPACE_ID" ]` guard skips it and the
worktree and branch herdr already created are orphaned. Key the rollback on the
worktree path existing instead.

**Verified against** herdr 0.7.0 (protocol 14). Responses are JSON-RPC shaped, so
ids live under `.result.*`, never at the top level.

### Seeing the agents

- Run `herdr` to attach to the persistent session — the script talks to the Herdr
  server from any terminal, but from a plain shell the workspace is created where
  you can't see it.
- Keep `herdr integration status` showing `claude: current`. That hook reports
  each agent's working / idle / blocked state to the workspace switcher; without
  it, panes still run but every agent shows as `unknown`. Reinstall with
  `herdr integration install claude`.
- `herdr agent list` shows every running issue agent by name and pane, across all
  workspaces.

## Tests

```bash
bash tests/run-all.sh                  # hermetic, free, ~5s
bash tests/run-all.sh --with-reviewer  # adds the reviewer eval (API calls)
```

`tests/delegate` covers `herdr-delegate.sh` end to end with `herdr`, `gh` and the
agent binary stubbed on `PATH` and every case in a throwaway git repo — argument
parsing, missing binaries, both guard rails, agent launch, focus behaviour, title
slugging, and rollback at three failure points. The stub records every herdr call
and really runs `git worktree add`, so worktree and branch state is genuine.

`tests/reviewer` measures the review pass rather than passing or failing it. Seven
fixtures — five with one planted defect each (off-by-one, scope creep, unupdated
call site, raw SQL, log/diff mismatch) and two clean ones — get built into a repo
where `before/` is the committed baseline and `after/` is the agent's uncommitted
work, then scored on whether the reviewer located the defect and whether it used
the category the skill declares. Haiku currently locates 5/5 with no false
positives, but labels them inconsistently: the skill's "What to check" headings
say **Correctness** and **Log accuracy** while its report format says `Bug` and
`Log`, so findings come back under categories nothing downstream will match.

`RUNS=5` before drawing conclusions — one run is a sample, not a measurement.
Details and knobs in [tests/README.md](tests/README.md).

## Assumptions

The validation and services commands are Laravel-specific (Sail, Pint, PHPStan,
Vite). Point steps 1 and 3 at your own toolchain to use these skills elsewhere.
