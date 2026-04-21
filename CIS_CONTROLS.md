# CIS Controls Reference

This document describes each CIS-inspired hardening control available via `gitw-cis`. Controls are opt-in, individually selectable, and fully revertible.

## How to use

```bash
gitw-cis list                    # see available controls and their status
gitw-cis apply <control_id>      # apply one or more controls
gitw-cis revert <control_id>     # revert back to recorded pre-apply state
gitw-cis status                  # summary of what's applied
gitw-cis diff <control_id>       # show what a control would change (before applying)
```

Every control saves its pre-apply state before making changes. `revert` restores the exact configuration that existed before apply, not a generic default. This means you can safely experiment.

## Reading the tables

- **Impact**: what may break or change user-visible behavior.
- **Recommendation**:
  - ★ *Recommended* — low risk, high value, applies cleanly for almost any user.
  - ☆ *Situational* — valuable in some contexts, neutral in others. Read the rationale.
  - ⚠ *Advanced* — requires understanding; may conflict with other tools.
  - ✗ *Hostile to desktop use* — ships for completeness, not recommended for workstations.

---

## Level 1 controls (v0.1)

These five are shipped in v0.1 as a proof-of-concept for the `gitw-cis` framework. Level 2 controls are targeted for v0.2.

### `l1-fs-cramfs-disable` ★ Recommended

**What it does:** Blacklists the `cramfs` kernel module. Cramfs is a compressed read-only filesystem that predates squashfs. No modern distribution uses it. Loading it expands kernel attack surface for no benefit.

**How it applies:**
- Writes `install cramfs /bin/true` to `/etc/modprobe.d/gitw-cis-cramfs.conf`
- Saves any existing cramfs modprobe configuration to `/var/lib/gitw/cis/backups/l1-fs-cramfs-disable/`

**Impact:** None for typical desktop use. You cannot mount cramfs filesystems (which you almost certainly don't have).

**Reboot required:** No (but module won't unload if currently in use — highly unlikely).

**CIS reference:** CIS Distribution Independent Linux Benchmark 1.1.1.1

---

### `l1-core-dump-restrict` ★ Recommended

**What it does:** Ensures coredumps cannot be created by suid binaries and are not stored. Core dumps can contain passwords, keys, or other secrets from process memory.

**How it applies:**
- Sets `fs.suid_dumpable=0` in `/etc/sysctl.d/gitw-cis-coredump.conf`
- Adds `* hard core 0` to `/etc/security/limits.d/gitw-cis-coredump.conf`
- Runs `sysctl --system` to apply
- ghostinthewires already disables coredumps via systemd coredump.conf in Phase 2; this control augments that with the traditional sysctl + limits.conf belt.

**Impact:** Debugging crashes in suid binaries becomes impossible without reverting this control. Normal user-space crash debugging (non-suid programs) is unaffected by `suid_dumpable`; the `limits.conf` change does suppress all user coredumps too.

**Reboot required:** No.

**CIS reference:** CIS 1.5.1, 1.5.3

---

### `l1-sshd-root-login` ☆ Situational

**What it does:** Disables direct root login over SSH by setting `PermitRootLogin no` in `/etc/ssh/sshd_config.d/gitw-cis-root-login.conf`.

**How it applies:**
- If OpenSSH is not installed, the control logs a skip and exits 0 (nothing to do)
- Otherwise writes the drop-in config and reloads sshd
- Saves any prior PermitRootLogin setting

**Impact:** You cannot `ssh root@your-machine`. You must SSH as your user and use `sudo`. This is already best practice — root login over SSH is a long-standing security no-no — but some users rely on it for automated backup scripts or similar. If you do, either:
- Use sudo with SSH keys instead (`ssh user@host sudo command`)
- Or revert this control and use SSH keys for root with `PermitRootLogin prohibit-password`

**Reboot required:** No.

**CIS reference:** CIS 5.2.8

---

### `l1-login-defs-umask` ⚠ Advanced

**What it does:** Sets `UMASK 027` in `/etc/login.defs`. Default Arch/Gentoo is UMASK 022, meaning newly-created files are world-readable (`644`). With 027, newly-created files are owner/group-readable only (`640`), and directories are owner-listable only (`750`).

**How it applies:**
- Changes the `UMASK` line in `/etc/login.defs`
- Saves the original value

**Impact:** Newly-created files will not be world-readable by default. Implications:
- If you share files by symlinking into `/srv/http` or similar, the webserver may not be able to read your files unless you explicitly chmod them.
- Some scripts that assume world-readable temp files in `/tmp` or `~` may break.
- Home directory contents become less visible to other users on the same machine (most workstations are single-user, so this is neutral).

This is the single most "gotcha" of the first 5 controls. Read the impact carefully before applying.

**Reboot required:** No, but only affects files created *after* application.

**CIS reference:** CIS 5.4.4

---

### `l1-inactive-password-lock` ☆ Situational

**What it does:** Sets account inactivity lockout in `/etc/default/useradd` and password max age in `/etc/login.defs`.

**How it applies:**
- `INACTIVE=30` in `/etc/default/useradd` — accounts with passwords unused for 30+ days get locked
- `PASS_MAX_DAYS 365` in `/etc/login.defs` — forces password change after a year
- `PASS_WARN_AGE 7` — warns for 7 days before forced change

**Impact:** You will eventually be prompted to change your login password. For single-user workstations this is mostly annoyance theater — if your disk is encrypted and your login password is long, rotating it yearly doesn't meaningfully improve security. For shared or multi-user machines it's more useful.

Default values are conservative. You can tune the numbers in `/etc/login.defs` after applying.

**Reboot required:** No.

**CIS reference:** CIS 5.5.1.1, 5.5.1.3

---

## Recommendation summary for v0.1

If you're not sure which to apply, start with:

- **`l1-fs-cramfs-disable`** — no downside, zero interaction cost
- **`l1-core-dump-restrict`** — already partly done by ghostinthewires defaults; makes the coverage more complete
- **`l1-sshd-root-login`** — if you've ever considered running sshd, apply this preemptively

Think carefully before applying:

- **`l1-login-defs-umask`** — can break file-sharing workflows; useful on multi-user machines, often annoying on single-user ones
- **`l1-inactive-password-lock`** — useful if you share the machine; low value on a personal laptop with FDE

You can apply and revert freely. Every control saves its before-state. Try them, see what breaks, revert what doesn't fit.

## Contributing new controls

Controls live in `shared/cis/<control_id>/` with four files:
- `apply.sh` — must be idempotent; must save pre-apply state to `/var/lib/gitw/cis/backups/<control_id>/`
- `revert.sh` — must restore from the saved state
- `status.sh` — exits 0 (applied), 1 (not applied), 2 (indeterminate); no stdout required
- `meta` — `id=...`, `level=1|2`, `title=...`, `rationale=...`, `reboot_required=0|1`, `impact=...`, `recommendation=recommended|situational|advanced|hostile`

Submit as a PR with:
- The bundle in `shared/cis/`
- A section in this document following the same format as the five above
- A test case in `tests/shared/cis/` that verifies `apply` → `status` → `revert` → `status` round-trips correctly

## Level 2 scope (v0.2)

Targeted for v0.2:
- AppArmor/SELinux enforce-mode enablement controls
- Audit framework baseline rules
- Sudo logging + `NOPASSWD` restrictions
- Kernel module signature enforcement (requires Secure Boot)
- `/tmp` and `/home` as separate mounts with noexec/nosuid
- systemd service hardening (sandbox directives on common services)

Do not attempt to apply any Level 2 control on a production system without reading its full impact documentation first. L2 controls routinely break things.
