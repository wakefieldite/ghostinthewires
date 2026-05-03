#!/usr/bin/env bash
#
# tests/static/test-gitw-log.sh
#
# Exercises every verifier in shared/lib/gitw-log.sh against known inputs,
# both positive (should return ok) and negative (should return fail).
# Run from anywhere; uses /tmp for scratch state.

set -o pipefail

# Resolve repo root from the test file's location
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)
LIB="$REPO_ROOT/shared/lib/gitw-log.sh"

[[ -f $LIB ]] || { echo "Cannot find $LIB"; exit 1; }

# Use a test log so we don't pollute the system one
SCRATCH=$(mktemp -d /tmp/gitw-log-test.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
export GITW_LOG="$SCRATCH/test.log"

# shellcheck source=/dev/null
source "$LIB"

# Counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=()

# Helper: record test result
_run_test() {
  local name=$1 expected_rc=$2
  shift 2
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  local actual_rc=0
  "$@" >/dev/null 2>&1 || actual_rc=$?
  if [[ $actual_rc -eq $expected_rc ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '  PASS  %s (rc=%d)\n' "$name" "$actual_rc"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("$name (expected rc=$expected_rc, got rc=$actual_rc)")
    printf '  FAIL  %s (expected rc=%d, got rc=%d)\n' "$name" "$expected_rc" "$actual_rc"
  fi
}

# Reset counters in the library between test groups
_reset_lib_counters() {
  GITW_LOG_OK=0
  GITW_LOG_WARN=0
  GITW_LOG_FAIL=0
}

echo "=== Testing gitw-log.sh ==="
echo "Library: $LIB"
echo "Scratch: $SCRATCH"
echo "Log:     $GITW_LOG"
echo

gitw_log_init "test"

# -----------------------------------------------------------------------------
echo "--- gitw_verify_file_contains ---"
echo "hello world" > "$SCRATCH/sample.txt"
_run_test "file_contains: matching pattern"     0 gitw_verify_file_contains "test1" "$SCRATCH/sample.txt" "hello"
_run_test "file_contains: non-matching pattern" 2 gitw_verify_file_contains "test2" "$SCRATCH/sample.txt" "goodbye"
_run_test "file_contains: missing file"         2 gitw_verify_file_contains "test3" "$SCRATCH/nope.txt" "anything"

# -----------------------------------------------------------------------------
echo "--- gitw_verify_file_lacks ---"
_run_test "file_lacks: pattern absent"          0 gitw_verify_file_lacks "test4" "$SCRATCH/sample.txt" "goodbye"
_run_test "file_lacks: pattern present"         2 gitw_verify_file_lacks "test5" "$SCRATCH/sample.txt" "hello"

# -----------------------------------------------------------------------------
echo "--- gitw_verify_file_mode ---"
chmod 0640 "$SCRATCH/sample.txt"
_run_test "file_mode: matching"                 0 gitw_verify_file_mode "test6" "$SCRATCH/sample.txt" "0640"
_run_test "file_mode: mismatched"               2 gitw_verify_file_mode "test7" "$SCRATCH/sample.txt" "0600"
_run_test "file_mode: missing file"             2 gitw_verify_file_mode "test8" "$SCRATCH/nope.txt" "0644"

# -----------------------------------------------------------------------------
echo "--- gitw_verify_symlink_target ---"
ln -sf /etc/hostname "$SCRATCH/hostlink"
_run_test "symlink_target: matching"            0 gitw_verify_symlink_target "test9" "$SCRATCH/hostlink" "/etc/hostname"
_run_test "symlink_target: wrong target"        2 gitw_verify_symlink_target "test10" "$SCRATCH/hostlink" "/etc/passwd"
_run_test "symlink_target: not a symlink"       2 gitw_verify_symlink_target "test11" "$SCRATCH/sample.txt" "/etc/hostname"
_run_test "symlink_target: missing"             2 gitw_verify_symlink_target "test12" "$SCRATCH/nolink" "/anything"

# -----------------------------------------------------------------------------
echo "--- gitw_verify_kernel_param ---"
# Create fake /proc/cmdline files
echo "BOOT_IMAGE=/boot/vmlinuz-linux quiet loglevel=3 lockdown=confidentiality" > "$SCRATCH/cmdline-good"
echo "BOOT_IMAGE=/boot/vmlinuz-linux quiet" > "$SCRATCH/cmdline-bad"
_run_test "kernel_param: present"               0 gitw_verify_kernel_param "test13" "lockdown" "$SCRATCH/cmdline-good"
_run_test "kernel_param: absent"                2 gitw_verify_kernel_param "test14" "lockdown" "$SCRATCH/cmdline-bad"
_run_test "kernel_param: bare token present"    0 gitw_verify_kernel_param "test15" "quiet" "$SCRATCH/cmdline-good"
_run_test "kernel_param: unreadable source"     2 gitw_verify_kernel_param "test16" "anything" "$SCRATCH/nope-cmdline"

# -----------------------------------------------------------------------------
echo "--- gitw_verify_command ---"
_run_test "command: matching exit"              0 gitw_verify_command "test17" 0 true
_run_test "command: mismatched exit"            2 gitw_verify_command "test18" 0 false
_run_test "command: explicit nonzero exit"      0 gitw_verify_command "test19" 1 false

# -----------------------------------------------------------------------------
# These verifiers depend on system state we can't reliably control in CI.
# We run them and accept any return code; the goal is verifying they don't
# crash the script and they produce a log entry.
echo "--- Smoke tests (any exit OK; verify the call doesn't crash) ---"
_smoke() {
  local name=$1
  shift
  local rc=0
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  "$@" >/dev/null 2>&1 || rc=$?
  if [[ $rc -le 2 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '  PASS  %s (smoke, rc=%d)\n' "$name" "$rc"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("$name (smoke, unexpected rc=$rc)")
    printf '  FAIL  %s (rc=%d, expected 0/1/2)\n' "$name" "$rc"
  fi
}

_smoke "service_enabled smoke"   gitw_verify_service_enabled "smoke1" "systemd-journald.service"
_smoke "sysctl smoke"            gitw_verify_sysctl "smoke2" "kernel.hostname" "any"
_smoke "btrfs_subvolume smoke"   gitw_verify_btrfs_subvolume "smoke3" /
_smoke "mount smoke"             gitw_verify_mount "smoke4" / "any"

# -----------------------------------------------------------------------------
echo
echo "--- Counter check ---"
# We've exercised many verifiers; counters should reflect that.
total_logged=$((GITW_LOG_OK + GITW_LOG_WARN + GITW_LOG_FAIL))
if (( total_logged > 0 )); then
  printf '  PASS  counters incremented (ok=%d, warn=%d, fail=%d)\n' \
    "$GITW_LOG_OK" "$GITW_LOG_WARN" "$GITW_LOG_FAIL"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  counters never incremented\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("counters never incremented")
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# -----------------------------------------------------------------------------
echo
echo "--- Log format check ---"
# The log should have the right structure: tab-separated 7 fields per data line.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
malformed=0
while IFS= read -r line; do
  # Skip blank lines
  [[ -z $line ]] && continue
  # Skip comment/header lines
  [[ ${line:0:1} == "#" ]] && continue
  # Count tabs: 7 fields = 6 tabs
  tab_count=$(awk -F'\t' '{print NF-1}' <<< "$line")
  if [[ $tab_count -ne 6 ]]; then
    malformed=$((malformed + 1))
  fi
done < "$GITW_LOG"
if (( malformed == 0 )); then
  printf '  PASS  all data lines have 7 tab-separated fields\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  %d lines do not have 7 fields\n' "$malformed"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("$malformed log lines malformed")
fi

# -----------------------------------------------------------------------------
echo
echo "============================================="
printf '  Total:  %d\n' "$TESTS_TOTAL"
printf '  Passed: %d\n' "$TESTS_PASSED"
printf '  Failed: %d\n' "$TESTS_FAILED"
echo "============================================="

if (( TESTS_FAILED > 0 )); then
  echo
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
