#!/usr/bin/env bash
#
# tests/static/run-all.sh - Run all static tests and shellcheck.
# Run from anywhere; locates repo root from script path.

set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)

GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

ok()   { echo -e "${GREEN}[PASS]${RESET} $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}[FAIL]${RESET} $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }

echo "=== ghostinthewires static test suite ==="
echo "Repo: $REPO_ROOT"
echo

# ---- bash -n on every script ----
echo "--- Syntax check (bash -n) ---"
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then
    ok "syntax: ${f#$REPO_ROOT/}"
  else
    fail "syntax: ${f#$REPO_ROOT/}"
    bash -n "$f"
  fi
done < <(find "$REPO_ROOT/arch" "$REPO_ROOT/shared" "$REPO_ROOT/tests" -type f \
  \( -name '*.sh' -o -path '*/helpers/gitw-*' \) 2>/dev/null)

# ---- shellcheck if available ----
echo
echo "--- shellcheck ---"
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r f; do
    # Allow common shellcheck exclusions for shell-script complexity in this codebase
    if shellcheck -e SC1090,SC1091,SC2034 "$f" >/dev/null 2>&1; then
      ok "shellcheck: ${f#$REPO_ROOT/}"
    else
      fail "shellcheck: ${f#$REPO_ROOT/}"
      shellcheck -e SC1090,SC1091,SC2034 "$f" || true
    fi
  done < <(find "$REPO_ROOT/arch" "$REPO_ROOT/shared" -type f \
    \( -name '*.sh' -o -path '*/helpers/gitw-*' \) 2>/dev/null)
else
  warn "shellcheck not installed; skipping (install with: sudo pacman -S shellcheck)"
fi

# ---- gitw-log library tests ----
echo
echo "--- gitw-log.sh test suite ---"
if bash "$REPO_ROOT/tests/static/test-gitw-log.sh" >/tmp/gitw-log-test-output 2>&1; then
  ok "gitw-log.sh: all tests pass"
else
  fail "gitw-log.sh: tests failed"
  cat /tmp/gitw-log-test-output
fi
rm -f /tmp/gitw-log-test-output

# ---- summary ----
echo
echo "============================================="
printf '  Passed: %d\n' "$PASS_COUNT"
printf '  Failed: %d\n' "$FAIL_COUNT"
echo "============================================="

[[ $FAIL_COUNT -eq 0 ]]
