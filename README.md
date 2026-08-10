# benchmark-ai

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
rolls back the workspace, worktree, and branch on any provisioning failure — a
failed run leaves nothing orphaned.

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

## Assumptions

The validation and services commands are Laravel-specific (Sail, Pint, PHPStan,
Vite). Point steps 1 and 3 at your own toolchain to use these skills elsewhere.
