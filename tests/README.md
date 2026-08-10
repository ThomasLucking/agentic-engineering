# tests

Two suites, split by what they can actually prove.

```bash
bash tests/run-all.sh                  # hermetic, free, ~5s
bash tests/run-all.sh --with-reviewer  # adds the reviewer eval (API calls)
```

## `delegate/` — herdr-delegate.sh

Deterministic shell tests. `herdr`, `gh` and the agent binary are stubs on `PATH`
(`delegate/stubs/`), and every case runs in a throwaway git repo, so nothing
touches a real Herdr server, GitHub, or this repo's worktrees.

The `herdr` stub records every call to `calls.log` — that is what the assertions
read — and really does run `git worktree add`, so worktree and branch state is
genuine. Fault injection is by env var:

| Var | Effect |
| --- | --- |
| `HERDR_STUB_FAIL="tab create"` | that command fails, exercising rollback |
| `HERDR_STUB_DEAD_PANE=1` | the agent pane is gone at `pane get` — agent died at startup |
| `HERDR_STUB_TOPLEVEL_IDS=1` | ids come back at the top level instead of under `.result` |
| `HERDR_STUB_REMOVE_REAL=1` | `worktree remove` really removes (default: no-op, so the git fallbacks are tested) |
| `GH_STUB_TITLE` / `GH_STUB_FAIL` | issue title lookup succeeds with that title / fails |

Covered: argument parsing, missing binaries, running outside a repo, the guard
rails, the happy path with and without an agent, focus behaviour, title slugging,
stdout/stderr separation, and rollback on three different failure points.

### Known failure

`regression: ids at the top level instead of .result` fails, and it is a real bug,
not a broken test. `jq_field`'s `die` runs inside a command substitution, so it
kills the subshell rather than the script; `set -e` then exits with `WORKSPACE_ID`
still empty, and `cleanup_on_error`'s `[ -n "$WORKSPACE_ID" ]` guard skips the
rollback. herdr has already created the worktree and branch by then, so both are
orphaned — exactly the state the guard rails refuse to run against next time.

Fix is to key the rollback on the worktree existing rather than on `WORKSPACE_ID`
being set, and to capture the parse failure outside the substitution.

## `reviewer/` — agent-diff-reviewer eval

Not a pass/fail unit test — a recall measurement. Each fixture plants one defect
of a known category (plus two clean fixtures to measure false positives), the
harness builds a git repo where `before/` is the committed baseline and `after/`
is the agent's uncommitted work, drops the trace log at
`docs/logs/issue-<N>-agent-trace.md`, and runs the reviewer against it.

```bash
bash tests/reviewer/run.sh                # all fixtures, one run each
bash tests/reviewer/run.sh bug-off-by-one # one fixture
RUNS=5 bash tests/reviewer/run.sh         # hit rate across runs — output varies
MODEL=sonnet bash tests/reviewer/run.sh   # is Haiku enough for step 5?
KEEP=1 bash tests/reviewer/run.sh         # keep the built worktrees to poke at
```

Raw reviewer output for every run lands in `reviewer/results/<timestamp>/`.

| Fixture | Planted |
| --- | --- |
| `bug-off-by-one` | `intdiv()` drops the remainder, so the last partial export page is never written |
| `scope-creep` | correct feature, plus an unrelated `config/mail.php` default flipped to `log` |
| `breakage-signature` | `build()` gains a required arg; the console command still calls it with one — only findable by grepping call sites |
| `convention-raw-sql` | interpolated `DB::select` where the codebase uses Eloquent |
| `log-mismatch` | the trace claims a unique-index migration the diff does not contain |
| `clean-archived-at` | nothing — correct, in-scope, accurate log |
| `clean-extract-method` | nothing — behaviour-preserving refactor, all call sites updated |

The eval prints two separate numbers because they fail for different reasons:

- **recall** — was the defect *located* (right file, right line ±`TOL`, and the
  text mentions what matters)? Gates the exit code.
- **labelling** — did it carry the category the skill declares? Reported only.

It also counts findings whose category falls outside the declared
`Bug|Scope|Breakage|Convention|Log` set. That is currently non-zero: the skill's
"What to check" headings say **Correctness** and **Log accuracy** while its report
format says `Bug` and `Log`, and the reviewer picks up the headings. Anything
parsing findings by category will silently drop them. Worth making the skill name
its categories once.

`RUNS=1` is a sample, not a measurement — labels in particular move between runs.
Use `RUNS=5` before concluding anything about a change to the skill.

### Caveats

- The reviewer runs through the real `claude` CLI, so `~/.claude/CLAUDE.md` loads
  and shapes its output. That is also true in production, so the eval matches the
  real thing rather than a clean room.
- The skill body is read from `agent-diff-reviewer/SKILL.md` in this repo and
  inlined into the prompt, so the eval tests the working tree, not whatever copy
  is installed under `~/.claude/skills/`.
- Fixtures add new files, so the harness runs `git add -A -N` — without it,
  `git diff` hides files the agent created, and the reviewer would be scored on a
  diff it could not see. Real worktrees have the same blind spot.
