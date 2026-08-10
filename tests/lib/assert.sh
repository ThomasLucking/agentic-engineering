# assert.sh — minimal bash 3.2-compatible test assertions.
# Source it, then: t_start "name" ... t_end

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""
FAILED_THIS=0

t_start() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  FAILED_THIS=0
}

t_end() {
  if [ "$FAILED_THIS" -eq 0 ]; then
    printf '  \033[32mPASS\033[0m  %s\n' "$CURRENT_TEST"
  else
    printf '  \033[31mFAIL\033[0m  %s\n' "$CURRENT_TEST"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

t_fail() {
  FAILED_THIS=1
  printf '          → %s\n' "$1"
}

assert_eq() { # <actual> <expected> <what>
  [ "$1" = "$2" ] || t_fail "$3: expected '$2', got '$1'"
}

assert_exit() { # <actual_status> <expected_status> <what>
  [ "$1" = "$2" ] || t_fail "$3: expected exit $2, got $1"
}

assert_contains() { # <haystack> <needle> <what>
  case "$1" in
    *"$2"*) ;;
    *) t_fail "$3: expected to contain '$2', got: $(printf '%s' "$1" | head -c 400)" ;;
  esac
}

assert_not_contains() { # <haystack> <needle> <what>
  case "$1" in
    *"$2"*) t_fail "$3: expected NOT to contain '$2'" ;;
    *) ;;
  esac
}

assert_file() { # <path> <what>
  [ -e "$1" ] || t_fail "$2: expected path to exist: $1"
}

assert_no_file() { # <path> <what>
  [ ! -e "$1" ] || t_fail "$2: expected path NOT to exist: $1"
}

t_summary() { # <suite name>
  printf '\n%s: %d run, %d failed\n' "$1" "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
