#!/usr/bin/env bash
#
#   bash tests/run-all.sh                  # hermetic suites only (free, seconds)
#   bash tests/run-all.sh --with-reviewer  # also run the reviewer eval (API calls)

HERE="$(cd "$(dirname "$0")" && pwd)"
status=0

bash "$HERE/delegate/run.sh" || status=1

case " $* " in
  *" --with-reviewer "*)
    bash "$HERE/reviewer/run.sh" || status=1
    ;;
  *)
    printf '\nreviewer eval skipped — run `bash tests/run-all.sh --with-reviewer` (costs API calls)\n'
    ;;
esac

exit "$status"
