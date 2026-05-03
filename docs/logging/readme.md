# Runtime validation logging

ghostinthewires phase scripts log every settings-applying action and verify the result. The log is the integration test: a clean run produces all `ok` entries; any `warn` or `fail` reveals a bug worth investigating.

## Why this exists

Shell scripts have a particular failure mode where commands "succeed" without doing anything useful. A `sed -i 's/foo/bar/' file` exits 0 even when no `foo` exists in the file. A `systemctl enable service` exits 0 even when the unit is already enabled. A `cryptsetup luksAddKey` can succeed at adding a keyslot that the firmware then can't read.

ChatGPT and Copilot caught several such failures in this project's earlier scripts where commands targeting outdated config-file structures ran without error but applied nothing. We can't catch all of them by reading the code; we have to actually run the install and check the system state afterward.

The logging library (`shared/lib/gitw-log.sh`) provides:

- A structured log file at `/var/log/gitw-install.log` (or `/tmp/gitw-install.log` during Phase 1 before the target system has its log directory mounted).
- A set of verifier functions that check actual system state — does the symlink point where we expect, is the kernel param in `/proc/cmdline`, does the file contain the regex we wrote, does the package report installed.
- An end-of-phase summary that tells the operator how many actions were verified and how many failed.

## Log format

One entry per line, tab-separated:

```
<ISO timestamp>\t<phase>\t<step>\t<action>\t<expected>\t<actual>\t<status>
```

`<status>` is one of:

- `ok` — verifier confirmed expected state
- `warn` — unexpected but not broken (e.g. service was already enabled when we expected to enable it for the first time)
- `fail` — state inconsistent with the action having taken effect
- `info` — non-verification entry (step header, freeform message)

Comment lines start with `#` and contain phase boundary markers and end-of-phase summaries.

## Reading the log

After an install, look at fail and warn entries:

```
sudo awk -F'\t' '$7 == "fail" || $7 == "warn"' /var/log/gitw-install.log
```

To see everything for a given step:

```
sudo awk -F'\t' '$3 == "configure_mkinitcpio"' /var/log/gitw-install.log
```

To see how many entries each phase produced:

```
sudo awk -F'\t' '$2 == "install" || $2 == "harden" || $2 == "software" {print $2, $7}' \
  /var/log/gitw-install.log | sort | uniq -c
```

## Using the library in scripts

Scripts source the library and call `gitw_log_init` once per phase. Then they wrap settings-applying actions with calls to verifiers.

```bash
source /usr/local/lib/gitw/gitw-log.sh
# (or via REPO_BASE during phase 1 when the lib hasn't been installed yet)

gitw_log_init "harden"

gitw_log_step "kernel_cmdline" "Applying kernel hardening parameters"
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"|" /etc/default/grub
gitw_verify_file_contains "kernel cmdline updated" /etc/default/grub "lockdown=confidentiality"

gitw_log_step "firewall" "Configuring nftables"
systemctl enable --now nftables.service
gitw_verify_service_enabled "nftables enabled" nftables.service

# At end of phase
gitw_log_phase_summary
```

## Verifier reference

| Verifier | Checks |
|---|---|
| `gitw_verify_file_contains <action> <file> <regex>` | File exists and matches regex |
| `gitw_verify_file_lacks <action> <file> <regex>` | File exists and does not match regex |
| `gitw_verify_file_mode <action> <file> <0nnn>` | File exists with given octal mode |
| `gitw_verify_symlink_target <action> <link> <target>` | Symlink resolves to target |
| `gitw_verify_kernel_param <action> <param> [src]` | Param appears in /proc/cmdline (or alt source) |
| `gitw_verify_service_enabled <action> <unit> [chroot]` | systemd unit is enabled |
| `gitw_verify_pacman_pkg <action> <pkg> [chroot]` | Package installed (Arch) |
| `gitw_verify_sysctl <action> <key> <value>` | Live sysctl matches |
| `gitw_verify_luks_keyslot <action> <device> <type>` | LUKS2 keyslot of given type exists |
| `gitw_verify_btrfs_subvolume <action> <path>` | Btrfs subvolume present |
| `gitw_verify_mount <action> <mp> <fstype>` | Path is mounted with given filesystem type |
| `gitw_verify_user_groups <action> <user> <groups> [chroot]` | User exists with given groups |
| `gitw_verify_command <action> <expected_rc> <cmd...>` | Generic: run command, check exit code |

## Intentional design choices

- **Verifiers check live state, not script intent.** A verifier that checks "did the command succeed" doesn't catch the case we care about. A verifier that re-reads the file or re-runs the system query does.

- **Verifiers do not abort.** They log and return 0/1/2. The calling script decides whether to continue, retry, or fail. Most settings-applying actions are non-fatal even if they don't take effect (the install can still complete; we just need to know about the gap).

- **The log persists across phases.** Phase 2 appends to Phase 1's log. The full record of an install lives in one file.

- **Console output is colored and condensed.** The full structured entry goes to the log; the operator sees a one-line summary in the terminal. This keeps the install screen readable while preserving forensic detail.

- **Tabs are stripped from values.** The log format uses tab as a field separator, so any incoming tab in a value would corrupt parsing. The library replaces tabs and newlines with spaces in all values.

## Reviewing a failed install

When `gitw_log_phase_summary` reports failures, the workflow is:

1. Read the failed entries: `awk -F'\t' '$7 == "fail"' /var/log/gitw-install.log`
2. For each failure, the entry tells you:
   - Which step it was in
   - What action was being attempted
   - What the verifier expected
   - What the verifier actually saw
3. Diagnose: is the script's command targeting outdated config? Has the package's defaults changed? Is the system in a state we didn't anticipate?
4. Fix the script (or open an issue) and re-run.

The expected outcome over time is that VM-test runs produce zero failures and warns get reviewed for whether they represent real issues or are expected (e.g. "service already enabled" after a re-run of harden.sh).
