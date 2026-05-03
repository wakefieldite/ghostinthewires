#!/usr/bin/env bash
#
# gitw-log.sh - Runtime validation logging for ghostinthewires phase scripts.
#
# Sourced by install.sh, harden.sh, software.sh. Provides:
#   - gitw_log_init <phase>          : open the log, write a phase header
#   - gitw_log_step <step> <message> : record the start of a step
#   - gitw_log_action <message>      : record a settings-applying action
#   - gitw_verify_*                  : check the system state and emit a log entry
#   - gitw_log_phase_summary         : print + log the phase summary
#
# Verifiers return:
#   0 = ok    (state matches expected)
#   1 = warn  (state unexpected but not broken; e.g. already-applied)
#   2 = fail  (state inconsistent with the action having taken effect)
#
# Verifiers log automatically. Callers can ignore the return code or use it
# to decide whether to abort, retry, or continue.
#
# Log format: tab-separated fields, one entry per line:
#   <ISO timestamp>\t<phase>\t<step>\t<action>\t<expected>\t<actual>\t<status>
#
# Log location:
#   - Phase 1 (install.sh runs from live ISO): /tmp/gitw-install.log
#     (copied to /mnt/var/log/gitw-install.log at end of Phase 1)
#   - Phase 2/3 (harden.sh, software.sh on installed system):
#     /var/log/gitw-install.log
#
# Phase 1 sets GITW_LOG=/tmp/gitw-install.log explicitly.
# Phase 2/3 default to /var/log/gitw-install.log.
#
# This library is intentionally distro-neutral. Anything that branches on
# pacman vs portage belongs in a phase script, not here.

# Prevent double-sourcing
[[ -n "${_GITW_LOG_LOADED:-}" ]] && return
_GITW_LOG_LOADED=1

# =============================================================================
# State
# =============================================================================

# Log file path. Phase scripts may override before sourcing.
: "${GITW_LOG:=/var/log/gitw-install.log}"

# Current phase ("install" / "harden" / "software"). Set by gitw_log_init.
GITW_LOG_PHASE=""

# Current step. Set by gitw_log_step. Used as a default for actions.
GITW_LOG_STEP="setup"

# Counters. Incremented by verifiers; reported by gitw_log_phase_summary.
GITW_LOG_OK=0
GITW_LOG_WARN=0
GITW_LOG_FAIL=0

# =============================================================================
# Internal write
# =============================================================================

_gitw_log_write() {
  # Args: <step> <action> <expected> <actual> <status>
  # Tabs are used as field separators, so we strip any tabs from values.
  local step=$1 action=$2 expected=$3 actual=$4 status=$5
  local ts
  ts=$(date -u +%FT%TZ)

  # Sanitize: replace tabs and newlines with spaces in any value
  step=${step//	/ }
  action=${action//	/ }
  expected=${expected//	/ }
  actual=${actual//	/ }
  step=${step//$'\n'/ }
  action=${action//$'\n'/ }
  expected=${expected//$'\n'/ }
  actual=${actual//$'\n'/ }

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "${GITW_LOG_PHASE:-?}" "$step" "$action" "$expected" "$actual" "$status" \
    >> "$GITW_LOG" 2>/dev/null || true

  # Update counters
  case "$status" in
    ok)   GITW_LOG_OK=$((GITW_LOG_OK + 1)) ;;
    warn) GITW_LOG_WARN=$((GITW_LOG_WARN + 1)) ;;
    fail) GITW_LOG_FAIL=$((GITW_LOG_FAIL + 1)) ;;
  esac
}

# Echo to stderr in a structured form so the operator can also see it live.
_gitw_log_console() {
  local status=$1 action=$2 actual=$3
  local color reset='\033[0m'
  case "$status" in
    ok)   color='\033[0;32m' ;;  # green
    warn) color='\033[1;33m' ;;  # yellow
    fail) color='\033[0;31m' ;;  # red
    *)    color='' ;;
  esac
  if [[ -n $actual && $status != "ok" ]]; then
    printf '%b[%s]%b %s -- actual: %s\n' "$color" "$status" "$reset" "$action" "$actual" >&2
  else
    printf '%b[%s]%b %s\n' "$color" "$status" "$reset" "$action" >&2
  fi
}

# =============================================================================
# Public API: setup, step markers, freeform messages
# =============================================================================

gitw_log_init() {
  # Args: <phase>
  # Initializes the log for a phase. Creates the file if needed.
  GITW_LOG_PHASE=$1
  GITW_LOG_OK=0
  GITW_LOG_WARN=0
  GITW_LOG_FAIL=0

  # Create log file with restrictive permissions if it doesn't exist
  if [[ ! -f "$GITW_LOG" ]]; then
    install -m 0600 /dev/null "$GITW_LOG" 2>/dev/null || {
      mkdir -p "$(dirname "$GITW_LOG")" 2>/dev/null
      touch "$GITW_LOG" 2>/dev/null
      chmod 0600 "$GITW_LOG" 2>/dev/null
    }
  fi

  # Header for this phase invocation
  {
    printf '\n# =============================================================\n'
    printf '# gitw phase=%s started=%s\n' "$GITW_LOG_PHASE" "$(date -u +%FT%TZ)"
    printf '# =============================================================\n'
  } >> "$GITW_LOG" 2>/dev/null || true
}

gitw_log_step() {
  # Args: <step_id> [message]
  # Marks the start of a logical step. Subsequent verifiers default to this step.
  GITW_LOG_STEP=$1
  local message=${2:-}
  if [[ -n $message ]]; then
    _gitw_log_write "$GITW_LOG_STEP" "$message" "" "" "info"
  fi
}

gitw_log_info() {
  # Args: <message>
  # Records a non-verification informational entry.
  local message=$1
  _gitw_log_write "$GITW_LOG_STEP" "$message" "" "" "info"
}

gitw_log_warn() {
  # Args: <message> [actual]
  # Records a warning that doesn't fit a verifier (e.g. a non-fatal command failure).
  local message=$1 actual=${2:-}
  _gitw_log_write "$GITW_LOG_STEP" "$message" "" "$actual" "warn"
  _gitw_log_console "warn" "$message" "$actual"
}

gitw_log_fail() {
  # Args: <message> [actual]
  local message=$1 actual=${2:-}
  _gitw_log_write "$GITW_LOG_STEP" "$message" "" "$actual" "fail"
  _gitw_log_console "fail" "$message" "$actual"
}

gitw_log_phase_summary() {
  local total=$((GITW_LOG_OK + GITW_LOG_WARN + GITW_LOG_FAIL))
  printf '\n'
  printf '=============================================\n'
  printf '  Phase %s summary\n' "${GITW_LOG_PHASE:-?}"
  printf '=============================================\n'
  printf '  Total verified actions: %d\n' "$total"
  printf '  ok:   %d\n' "$GITW_LOG_OK"
  printf '  warn: %d\n' "$GITW_LOG_WARN"
  printf '  fail: %d\n' "$GITW_LOG_FAIL"
  printf '\n'
  printf '  Full log: %s\n' "$GITW_LOG"
  if (( GITW_LOG_WARN > 0 || GITW_LOG_FAIL > 0 )); then
    printf '\n'
    printf '  Review the log for entries with status warn or fail:\n'
    printf '    awk -F"\\t" '\''$7 != "ok" && $7 != "info"'\'' %s\n' "$GITW_LOG"
  fi
  printf '\n'

  # Also append the summary to the log itself
  {
    printf '# phase=%s ended=%s ok=%d warn=%d fail=%d\n' \
      "$GITW_LOG_PHASE" "$(date -u +%FT%TZ)" \
      "$GITW_LOG_OK" "$GITW_LOG_WARN" "$GITW_LOG_FAIL"
  } >> "$GITW_LOG" 2>/dev/null || true
}

# =============================================================================
# Verifiers
# =============================================================================
# Each verifier logs an entry and returns 0 (ok), 1 (warn), or 2 (fail).
# They take an action description first so log entries can be tied back to
# the operation that was just performed.
# =============================================================================

# Verify a file exists and contains a pattern.
# Args: <action_description> <file_path> <regex>
gitw_verify_file_contains() {
  local action=$1 file=$2 pattern=$3
  local actual status

  if [[ ! -f $file ]]; then
    actual="file not found"
    status="fail"
  elif grep -qE "$pattern" "$file" 2>/dev/null; then
    actual="match found"
    status="ok"
  else
    actual="no match"
    status="fail"
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "file=$file pattern=$pattern" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a file exists and does NOT contain a pattern.
# Args: <action_description> <file_path> <regex>
gitw_verify_file_lacks() {
  local action=$1 file=$2 pattern=$3
  local actual status

  if [[ ! -f $file ]]; then
    actual="file not found"
    status="fail"
  elif grep -qE "$pattern" "$file" 2>/dev/null; then
    actual="pattern still present"
    status="fail"
  else
    actual="pattern absent"
    status="ok"
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "file=$file lacks=$pattern" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a file exists with given mode. Mode given as octal string (e.g. "0600").
# Args: <action_description> <file_path> <expected_mode>
gitw_verify_file_mode() {
  local action=$1 file=$2 expected=$3
  local actual status

  if [[ ! -e $file ]]; then
    actual="file not found"
    status="fail"
  else
    actual=$(stat -c "%04a" "$file" 2>/dev/null)
    if [[ $actual == "$expected" ]]; then
      status="ok"
    else
      status="fail"
    fi
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "$expected" "$actual" "$status"
  _gitw_log_console "$status" "$action" "expected $expected got $actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a symlink points where we expect.
# Args: <action_description> <symlink_path> <expected_target>
gitw_verify_symlink_target() {
  local action=$1 link=$2 expected=$3
  local actual status

  if [[ ! -L $link ]]; then
    if [[ -e $link ]]; then
      actual="exists but not a symlink"
    else
      actual="not present"
    fi
    status="fail"
  else
    actual=$(readlink "$link" 2>/dev/null)
    if [[ $actual == "$expected" ]]; then
      status="ok"
    else
      status="fail"
    fi
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "$expected" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a systemd unit is enabled. Uses systemctl is-enabled.
# Args: <action_description> <unit_name> [chroot_path]
# If chroot_path is given, the check runs inside it via systemctl --root=.
gitw_verify_service_enabled() {
  local action=$1 unit=$2 root=${3:-}
  local actual status cmd

  if [[ -n $root ]]; then
    actual=$(systemctl --root="$root" is-enabled "$unit" 2>&1 | head -1)
  else
    actual=$(systemctl is-enabled "$unit" 2>&1 | head -1)
  fi

  case "$actual" in
    enabled|enabled-runtime|alias|static)  status="ok" ;;
    masked)                                 status="fail" ;;
    *)                                       status="fail" ;;
  esac

  _gitw_log_write "$GITW_LOG_STEP" "$action" "enabled" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a kernel command-line parameter is present in /proc/cmdline.
# Args: <action_description> <param> [target_proc_cmdline_path]
# target_proc_cmdline_path defaults to /proc/cmdline. For checking what the
# next boot will see, callers should grep GRUB_CMDLINE_LINUX in /etc/default/grub
# instead via gitw_verify_file_contains.
gitw_verify_kernel_param() {
  local action=$1 param=$2 src=${3:-/proc/cmdline}
  local actual status

  if [[ ! -r $src ]]; then
    actual="cannot read $src"
    status="fail"
  elif grep -qE "(^| )${param}(=| |$)" "$src"; then
    actual="present"
    status="ok"
  else
    actual="absent"
    status="fail"
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "$param in $src" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a pacman package is installed (target system).
# Args: <action_description> <package> [chroot_path]
gitw_verify_pacman_pkg() {
  local action=$1 pkg=$2 root=${3:-}
  local actual status

  if [[ -n $root ]]; then
    if arch-chroot "$root" pacman -Q "$pkg" &>/dev/null; then
      actual="installed"
      status="ok"
    else
      actual="not installed"
      status="fail"
    fi
  else
    if pacman -Q "$pkg" &>/dev/null; then
      actual="installed"
      status="ok"
    else
      actual="not installed"
      status="fail"
    fi
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "package $pkg installed" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a sysctl value matches expected.
# Args: <action_description> <key> <expected>
# Only useful for currently-loaded sysctls. To check a written file, use
# gitw_verify_file_contains against /etc/sysctl.d/*.conf.
gitw_verify_sysctl() {
  local action=$1 key=$2 expected=$3
  local actual status

  if ! actual=$(sysctl -n "$key" 2>/dev/null); then
    actual="not loaded"
    status="fail"
  elif [[ "$actual" == "$expected" ]]; then
    status="ok"
  else
    status="fail"
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "$key=$expected" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a LUKS keyslot of a given type exists on a device.
# Args: <action_description> <device> <slot_type>
# slot_type matches against luksDump output - one of:
#   luks2-passphrase | luks2-tpm2 | luks2-fido2 | luks2-pkcs11 | systemd-tpm2 | systemd-fido2
gitw_verify_luks_keyslot() {
  local action=$1 device=$2 slot_type=$3
  local actual status

  if ! [[ -b $device ]]; then
    actual="device not found"
    status="fail"
  else
    # systemd-cryptenroll labels its tokens "systemd-tpm2", "systemd-fido2", etc.
    # in the LUKS2 token area. cryptsetup luksDump shows them in the Tokens section.
    if cryptsetup luksDump "$device" 2>/dev/null | grep -qE "^[[:space:]]+Keyslot:.*\$|type:[[:space:]]+${slot_type}"; then
      actual="found"
      status="ok"
    else
      actual="absent"
      status="fail"
    fi
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "$slot_type on $device" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a Btrfs subvolume exists at the given path.
# Args: <action_description> <subvol_path>
gitw_verify_btrfs_subvolume() {
  local action=$1 path=$2
  local actual status

  if btrfs subvolume show "$path" &>/dev/null; then
    actual="present"
    status="ok"
  else
    actual="absent"
    status="fail"
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "subvolume at $path" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a path is currently mounted with a given filesystem type.
# Args: <action_description> <mountpoint> <fstype>
gitw_verify_mount() {
  local action=$1 mp=$2 fstype=$3
  local actual_fstype status

  actual_fstype=$(findmnt -no FSTYPE "$mp" 2>/dev/null)

  if [[ -z $actual_fstype ]]; then
    actual_fstype="not mounted"
    status="fail"
  elif [[ "$actual_fstype" == "$fstype" ]]; then
    status="ok"
  else
    status="fail"
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "$fstype at $mp" "$actual_fstype" "$status"
  _gitw_log_console "$status" "$action" "$actual_fstype"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Verify a user exists with given groups (target system, via chroot).
# Args: <action_description> <username> <expected_groups_csv> <chroot_path>
gitw_verify_user_groups() {
  local action=$1 user=$2 expected=$3 root=${4:-}
  local actual status

  if [[ -n $root ]]; then
    actual=$(arch-chroot "$root" id -Gn "$user" 2>/dev/null | tr ' ' ',')
  else
    actual=$(id -Gn "$user" 2>/dev/null | tr ' ' ',')
  fi

  if [[ -z $actual ]]; then
    actual="user not found"
    status="fail"
  else
    # Check every expected group is in the actual list
    status="ok"
    local g
    IFS=',' read -ra _expected_groups <<< "$expected"
    for g in "${_expected_groups[@]}"; do
      if [[ ",$actual," != *",$g,"* ]]; then
        status="fail"
        break
      fi
    done
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "groups: $expected" "$actual" "$status"
  _gitw_log_console "$status" "$action" "$actual"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# Generic: run a command and check its exit code.
# Args: <action_description> <expected_exit_code> <command...>
gitw_verify_command() {
  local action=$1 expected_rc=$2
  shift 2
  local actual_rc status

  "$@"
  actual_rc=$?

  if [[ $actual_rc -eq $expected_rc ]]; then
    status="ok"
  else
    status="fail"
  fi

  _gitw_log_write "$GITW_LOG_STEP" "$action" "exit=$expected_rc" "exit=$actual_rc" "$status"
  _gitw_log_console "$status" "$action" "exit=$actual_rc"
  case $status in ok) return 0 ;; warn) return 1 ;; *) return 2 ;; esac
}

# =============================================================================
# Convenience: log an action then run it (used heavily in install scripts)
# =============================================================================

# Records that we're about to do something. No verification - the verifier
# call that should follow does that.
gitw_log_action() {
  local action=$1
  _gitw_log_write "$GITW_LOG_STEP" "$action" "" "" "info"
}
