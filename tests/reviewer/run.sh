#!/usr/bin/env bash
#
# Eval harness for the agent-diff-reviewer skill.
#
# Each fixture is a planted defect of one declared category (or a clean change).
# The harness builds a throwaway git repo where before/ is the committed baseline
# and after/ is the agent's uncommitted work, drops the trace log in place, runs
# the reviewer against it, and scores the report against expect.json.
#
#   bash tests/reviewer/run.sh                # every fixture, one run each
#   bash tests/reviewer/run.sh bug-off-by-one # one fixture
#   RUNS=3 bash tests/reviewer/run.sh         # 3 runs each, for a hit rate
#   MODEL=sonnet bash tests/reviewer/run.sh   # compare models
#   KEEP=1 bash tests/reviewer/run.sh         # keep the built worktrees
#
# Costs API calls — it is not part of `tests/run-all.sh` by default.

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SKILL="$ROOT/agent-diff-reviewer/SKILL.md"
STUBS="$HERE/stubs"
FIXTURES="$HERE/fixtures"

MODEL="${MODEL:-haiku}"
RUNS="${RUNS:-1}"
TOL="${TOL:-5}"          # how far off a reported line number may be
ONLY="${1:-}"

command -v claude >/dev/null 2>&1 || { echo "claude CLI not found on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found on PATH" >&2; exit 2; }
chmod +x "$STUBS"/* 2>/dev/null

OUTDIR="$HERE/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTDIR"

# Skill body without its YAML frontmatter — the eval must test this repo's file,
# not whatever copy happens to be installed in ~/.claude/skills.
SKILL_BODY="$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$SKILL")"

TOTAL_EXPECTED=0
TOTAL_MATCHED=0
TOTAL_LOCATED=0
TOTAL_FALSE_POS=0
TOTAL_FORMAT_BAD=0
TOTAL_VOCAB_BAD=0
SUMMARY=""

# The categories the skill's report format promises. Anything else means a caller
# grepping for a category silently drops the finding, so it is tracked separately
# from recall.
VOCAB='^(Bug|Scope|Breakage|Convention|Log|Clean)$'

# report_lines <raw output file> — the skill's `[a][b][c]` lines, fences stripped
report_lines() {
  grep -E '^[[:space:]]*\[[^]]*\]\[[^]]*\]\[' "$1" 2>/dev/null
}

# non_report_lines <raw output file> — anything else non-empty, i.e. preamble
non_report_lines() {
  grep -vE '^[[:space:]]*(\[[^]]*\]\[[^]]*\]\[|```|$)' "$1" 2>/dev/null
}

build_worktree() { # <fixture dir> <issue number> → prints work dir
  fx="$1"; issue="$2"
  work="$(mktemp -d "${TMPDIR:-/tmp}/reviewfx.XXXXXX")"
  cp -R "$fx/before/." "$work/" 2>/dev/null
  git -C "$work" init -q -b main
  git -C "$work" add -A
  git -C "$work" -c user.email=t@example.com -c user.name=test commit -qm "baseline" >/dev/null
  cp -R "$fx/after/." "$work/" 2>/dev/null
  mkdir -p "$work/docs/logs"
  cp "$fx/trace.md" "$work/docs/logs/issue-${issue}-agent-trace.md"
  # intent-to-add so files the agent *created* show up in `git diff`, which is
  # what the skill tells the reviewer to read
  git -C "$work" add -A -N >/dev/null 2>&1
  printf '%s' "$work"
}

run_reviewer() { # <work dir> <fixture dir> <issue> <output file>
  work="$1"; fx="$2"; issue="$3"; out="$4"
  prompt="You are running as the agent-diff-reviewer subagent. Follow this skill exactly:

<skill>
${SKILL_BODY}
</skill>

Inputs:
- worktree path: ${work}
- issue number: ${issue}
- log path: docs/logs/issue-${issue}-agent-trace.md

You are already inside the worktree. Output only the report lines."

  ( cd "$work" && PATH="$STUBS:$PATH" GH_ISSUE_FILE="$fx/issue.md" \
      claude -p "$prompt" \
        --model "$MODEL" \
        --allowedTools "Read Grep Glob Bash" \
      > "$out" 2> "${out%.txt}.stderr" )
}

# find_match <output file> <file regex> <category regex or "-"> <mentions regex> <expected line>
# → 0 if some reported line points at the planted defect. Passing "-" for the
# category tests whether the defect was *located* regardless of how it was labelled.
find_match() {
  _out="$1"; _file="$2"; _cat="$3"; _mentions="$4"; _want="$5"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    b1="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*\[([^]]*)\].*/\1/')"
    b2="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*\[[^]]*\]\[([^]]*)\].*/\1/')"

    printf '%s' "$b1" | grep -qE "$_file" || continue
    if [ "$_cat" != "-" ]; then
      printf '%s' "$b2" | grep -qiE "$_cat" || continue
    fi
    if [ -n "$_mentions" ]; then
      printf '%s' "$line" | grep -qiE "$_mentions" || continue
    fi
    if [ -n "$_want" ]; then
      got_line="$(printf '%s' "$b1" | sed -nE 's/.*:([0-9]+).*/\1/p')"
      if [ -n "$got_line" ]; then
        delta=$((got_line - _want))
        [ "$delta" -lt 0 ] && delta=$((-delta))
        [ "$delta" -le "$TOL" ] || continue
      fi
    fi
    return 0
  done <<EOF
$(report_lines "$_out")
EOF
  return 1
}

score_fixture() { # <fixture dir> <name> <work dir> <output file> → per-run counts
  fx="$1"; name="$2"; work="$3"; out="$4"
  expected="$(jq -r '.findings | length' "$fx/expect.json")"
  matched=0     # located AND labelled with the expected category
  located=0     # found the defect, whatever it called it

  if [ "$expected" -gt 0 ]; then
    while IFS= read -r finding; do
      [ -n "$finding" ] || continue
      cat_pat="$(printf '%s' "$finding" | jq -r '.category')"
      file_pat="$(printf '%s' "$finding" | jq -r '.file')"
      anchor="$(printf '%s' "$finding" | jq -r '.anchor // empty')"
      anchor_file="$(printf '%s' "$finding" | jq -r '.anchor_file // empty')"
      mentions="$(printf '%s' "$finding" | jq -r '.mentions // empty')"
      note="$(printf '%s' "$finding" | jq -r 'if .note then " — " + .note else "" end')"

      # resolve the expected line number from the anchor text
      want_line=""
      if [ -n "$anchor" ]; then
        [ -n "$anchor_file" ] || anchor_file="after/${file_pat}"
        if [ -f "$fx/$anchor_file" ]; then
          want_line="$(grep -n -F -- "$anchor" "$fx/$anchor_file" | head -1 | cut -d: -f1)"
        fi
      fi

      if find_match "$out" "$file_pat" "$cat_pat" "$mentions" "$want_line"; then
        matched=$((matched + 1))
        located=$((located + 1))
      elif find_match "$out" "$file_pat" "-" "$mentions" "$want_line"; then
        located=$((located + 1))
        printf '      miscategorised: found it, expected [%s]%s\n' "$cat_pat" "$note"
      else
        printf '      miss: [%s][%s]%s\n' "$file_pat" "$cat_pat" "$note"
      fi
    done <<EOF
$(jq -c '.findings[]' "$fx/expect.json")
EOF
  fi

  reported="$(report_lines "$out" | grep -vciE '\]\[[[:space:]]*clean[[:space:]]*\]' 2>/dev/null)"
  [ -n "$reported" ] || reported=0
  bad_format="$(non_report_lines "$out" | grep -c . 2>/dev/null)"
  [ -n "$bad_format" ] || bad_format=0

  vocab_bad=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    cat_used="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*\[[^]]*\]\[([^]]*)\].*/\1/')"
    printf '%s' "$cat_used" | grep -qE "$VOCAB" || {
      vocab_bad=$((vocab_bad + 1))
      printf '      off-vocabulary category: [%s]\n' "$cat_used"
    }
  done <<EOF
$(report_lines "$out")
EOF

  false_pos=0
  if [ "$expected" -eq 0 ]; then
    false_pos="$reported"
  fi

  RUN_EXPECTED="$expected"
  RUN_MATCHED="$matched"
  RUN_LOCATED="$located"
  RUN_FALSE_POS="$false_pos"
  RUN_REPORTED="$reported"
  RUN_FORMAT_BAD="$bad_format"
  RUN_VOCAB_BAD="$vocab_bad"
}

printf '\nagent-diff-reviewer eval — model=%s runs=%s\n' "$MODEL" "$RUNS"
printf 'results: %s\n\n' "$OUTDIR"

for fx in "$FIXTURES"/*/; do
  name="$(basename "$fx")"
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
  issue="$(jq -r '.issue' "$fx/expect.json")"
  expected="$(jq -r '.findings | length' "$fx/expect.json")"

  printf '  %s (issue #%s, %s)\n' "$name" "$issue" \
    "$([ "$expected" -eq 0 ] && echo 'clean' || echo "$expected planted")"

  run_matched=0; run_located=0; run_fp=0; run_fmt=0; run_vocab=0; hits=0
  i=1
  while [ "$i" -le "$RUNS" ]; do
    out="$OUTDIR/${name}.run${i}.txt"
    work="$(build_worktree "$fx" "$issue")"
    run_reviewer "$work" "$fx" "$issue" "$out"
    score_fixture "$fx" "$name" "$work" "$out"

    run_matched=$((run_matched + RUN_MATCHED))
    run_located=$((run_located + RUN_LOCATED))
    run_fp=$((run_fp + RUN_FALSE_POS))
    run_fmt=$((run_fmt + RUN_FORMAT_BAD))
    run_vocab=$((run_vocab + RUN_VOCAB_BAD))
    if [ "$expected" -gt 0 ] && [ "$RUN_LOCATED" -eq "$expected" ]; then
      hits=$((hits + 1))
    elif [ "$expected" -eq 0 ] && [ "$RUN_FALSE_POS" -eq 0 ]; then
      hits=$((hits + 1))
    fi

    printf '    run %d: located %d/%d (categorised %d), reported %d, false-pos %d, off-format %d, off-vocab %d\n' \
      "$i" "$RUN_LOCATED" "$expected" "$RUN_MATCHED" "$RUN_REPORTED" "$RUN_FALSE_POS" "$RUN_FORMAT_BAD" "$RUN_VOCAB_BAD"

    [ -n "${KEEP:-}" ] && printf '      worktree: %s\n' "$work"
    [ -n "${KEEP:-}" ] || rm -rf "$work"
    i=$((i + 1))
  done

  TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected * RUNS))
  TOTAL_MATCHED=$((TOTAL_MATCHED + run_matched))
  TOTAL_LOCATED=$((TOTAL_LOCATED + run_located))
  TOTAL_FALSE_POS=$((TOTAL_FALSE_POS + run_fp))
  TOTAL_FORMAT_BAD=$((TOTAL_FORMAT_BAD + run_fmt))
  TOTAL_VOCAB_BAD=$((TOTAL_VOCAB_BAD + run_vocab))
  SUMMARY="${SUMMARY}$(printf '  %-24s %d/%d runs clean\n' "$name" "$hits" "$RUNS")"$'\n'
done

printf '\n%s' "$SUMMARY"
if [ "$TOTAL_EXPECTED" -gt 0 ]; then
  printf '\nrecall:   %d/%d planted defects located\n' "$TOTAL_LOCATED" "$TOTAL_EXPECTED"
  printf 'labelling: %d/%d of those carried the expected category\n' "$TOTAL_MATCHED" "$TOTAL_EXPECTED"
fi
printf 'false positives on clean fixtures: %d\n' "$TOTAL_FALSE_POS"
printf 'lines outside the skill'"'"'s report format: %d\n' "$TOTAL_FORMAT_BAD"
printf 'findings using a category outside the declared set: %d\n' "$TOTAL_VOCAB_BAD"

# Recall and false positives gate the suite. Categorisation is reported but does
# not fail it — a correct finding under the wrong label is still a caught defect.
[ "$TOTAL_LOCATED" -eq "$TOTAL_EXPECTED" ] && [ "$TOTAL_FALSE_POS" -eq 0 ]
