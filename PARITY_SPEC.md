# ghostinthewires Parity Specification

**Version:** 0.3
**Status:** Working draft. Locked decisions are marked `[LOCKED]`. Proposed decisions are marked `[PROPOSED]`. Superseded content is marked `[SUPERSEDED]` with a date. Removed content is marked `[REMOVED]` with a date.
**Source of truth:** This document. Any behavior change that would affect the user-visible CLI, config semantics, or security posture must be reflected here before landing in either edition.

---

## 1. Project identity

- `[LOCKED]` **Project framing:** a security-focused, reproducible Linux workstation, available in Arch and Gentoo editions with cross-edition user-facing parity. Not "an install script" and not yet formally a "spec project" — the parity discipline is real but unproven against third-party implementers.
- `[LOCKED]` **Name:** `ghostinthewires` (plural — networks have many wires).
- `[LOCKED]` **No Mitnick homage.** The name is descriptive-of-networking, not reference-dropping.
- `[LOCKED]` **Monorepo** at `github.com/wakefieldite/ghostinthewires`, public, GPLv3.
- `[LOCKED]` **Editions:** `ghostinthewires-arch` (formerly hArch) and `ghostinthewires-gentoo` (new), in the `arch/` and `gentoo/` subdirectories.
- `[LOCKED]` **Helper prefix:** `gitw-*` on both editions, everywhere.

## 2. Repository layout

```
ghostinthewires/
├── README.md                   # Landing page
├── PARITY_SPEC.md              # This document
├── CIS_CONTROLS.md             # Per-control impact and recommendations
├── CHANGELOG.md                # Unified timeline across both editions
├── LICENSE                     # GPLv3
├── arch/                       # Arch edition
│   ├── install.sh
│   ├── harden.sh
│   ├── software.sh
│   ├── helpers/                # Arch-specific helpers
│   └── README.md
├── gentoo/                     # Gentoo edition (WIP)
│   ├── install.sh
│   ├── harden.sh
│   ├── software.sh
│   ├── helpers/                # Gentoo-specific helpers
│   └── README.md
├── shared/
│   ├── helpers/                # Distro-neutral helpers (gitw-*)
│   ├── cis/                    # CIS control bundles
│   ├── lib/                    # Shared shell libraries (logging, validation)
│   ├── config-templates/       # features.conf, nftables.conf, etc.
│   └── skel/                   # Hyprland starter configs
├── docs/
│   ├── install-arch.md
│   ├── install-gentoo.md
│   ├── comparison.md           # Side-by-side threat capability matrix
│   ├── threat-modeling/        # Worksheet + guidance (out-of-scope for installer)
│   └── dev/                    # Testing, contributing
└── tests/                      # Static and runtime test harness
    ├── static/                 # shellcheck, schema, CLI-contract
    ├── cis/                    # control round-trip tests
    └── README.md
```

Each edition's `install.sh` fetches its distro-specific helpers from `<edition>/helpers/` and the shared helpers from `shared/helpers/` into `/usr/local/bin/`.

## 3. Invariants (identical across both editions)

These do NOT vary by distro. If a change would violate an invariant, it requires an explicit decision update in this document before implementation.

1. **Three-phase install model** with sentinel files at `/var/lib/gitw-install/phase-N-<name>.done`.
2. **Init system:** systemd on both editions. Gentoo uses `default/linux/amd64/<ver>/desktop/systemd` profile (multilib, desktop, systemd).
3. **Encryption:** LUKS2 + argon2id + aes-xts-plain64, pre-encryption random fill, encrypted `/boot` via GRUB.
4. **Unlock modes:** `simple` / `tpm-pin` (default) / `combined` (stubbed for v0.1). Break-glass passphrase always in slot 0.
5. **TPM2 binding:** PCRs 0+7 via `systemd-cryptenroll`.
6. **FIDO2:** primary + backup enrollment prompted in Phase 1.
7. **Filesystem:** Btrfs with subvolumes `@`, `@home`, `@snapshots`, `@var_log`, `@var_log_audit`, `@var_cache`, `@var_tmp`, `@var_lib_docker` (created unmounted). Mount options: `rw,noatime,compress=zstd:3,space_cache=v2,discard=async` + `autodefrag` conditional on rotational media.
8. **Snapshots:** Snapper + pre/post package-manager hooks + grub-btrfs. Arch: `snap-pac`. Gentoo: custom portage bashrc hook (see §5).
9. **Bootloader:** GRUB 2.12+ with `cryptodisk`/`luks2` modules.
10. **Microcode:** auto-detect Intel/AMD.
11. **Kernel hardening cmdline:** driven by `/etc/gitw/features.conf`. Params: `lockdown`, `init_on_alloc`, `init_on_free`, `slab_nomerge`, `randomize_kstack_offset`, `vsyscall`, `mitigations`, `page_alloc.shuffle`, `oops=panic`.
12. **Sysctl hardening:** ~30 params shipped in `/etc/sysctl.d/99-gitw.conf`.
13. **Firewall:** nftables, INPUT drop default, stateful, `/etc/nftables.d/` include for per-machine rules. ICMP echo rate-limited. SSH off by default, togglable via `gitw-firewall`.
14. **DNS:** dnscrypt-proxy with Anonymized DNSCrypt (mullvad-doh, quad9, cloudflare). Profiles: `home` / `travel` / `offline`. Steven Black blocklist. Switched via `gitw-dns-profile`.
15. **Network manager:** NetworkManager. MAC randomization on, MDNS/LLMNR off, DHCP hostname suppression on.
16. **Coredumps:** disabled (systemd coredump.conf + limits.conf).
17. **Thumbnail cache:** `tumblerd` masked in user skel.
18. **Swap:** zram via `zram-generator`. No disk swap, no hibernate.
19. **MAC layer default:** AppArmor on both editions. SELinux opt-in on Gentoo only. `gitw-apparmor` / `gitw-selinux` helpers control state.
20. **Browsers:** Librewolf + Tor Browser. Arch: AUR via paru with PKGBUILD review enforced. Gentoo: official overlays. Flatpak removed from the default path.
21. **Login manager:** greetd + tuigreet.
22. **Compositor:** Hyprland. Ecosystem: waybar, alacritty, mako, fuzzel/wofi, hyprlock, hypridle, hyprpaper, xdg-desktop-portal-hyprland.
23. **GPU detection:** Intel / NVIDIA / AMD / VM. NVIDIA path supports Blackwell via `nvidia-open`. Early KMS configured for Hyprland (modules in initramfs + modprobe + cmdline).
24. **Firmware:** `fwupd` installed, LVFS documented.
25. **Features.conf:** `/etc/gitw/features.conf`, single shell-variable file, same schema across editions. `gitw-reconfigure` applies changes.
26. **Helper script contract:** same name, CLI, output format across editions. Implementation may differ; interface does not. Every helper supports `--help` and exits 0; every helper exits non-zero with informative message on bad args; every destructive helper requires confirmation.
27. **Optional AI stack:** off by default. Auto-detect NVIDIA+CUDA during Phase 3, prompt, delegate to `gitw-ai install` if accepted. See §6.
28. **CIS hardening:** `[UPDATED 2026-04-29]` optional, selectable, revertible. Standalone helper with its own state file. Not integrated into `features.conf`. v0.1 ships a minimal framework + 5 starter controls. **Full benchmark adaptation deferred to v0.2.** RHEL benchmark will be the primary baseline (most mature, most thoroughly tested), Ubuntu benchmark for AppArmor specifics. CIS Distribution Independent Linux Benchmark is too stale (last updated 2018) to use as primary. See §7.
29. `[REMOVED 2026-04-29]` ~~Threat model via interactive questionnaire (`gitw-threat-profile`).~~ Removed. Threat modeling is fundamentally about user circumstances that cannot be captured by a multiple-choice script (legal situation, relationships, employer dynamics, geographic moves, financial position). Trying to derive an installer config from a quiz creates false confidence in the wrong place. See §8 for replacement approach.
30. **License:** GPLv3.
31. **AUR signature verification on Arch:** `gitw-aur-review` wraps paru to enforce PKGBUILD review, detect signing-key changes, and warn on unsigned packages. Config: `AUR_REQUIRE_SIGNED` in features.conf (`0`=warn, `1`=refuse, `never`=silent).
32. `[NEW 2026-04-29]` **Runtime validation logging.** Every install/harden/software phase emits structured log entries to `/var/log/gitw-install.log` covering each settings-applying action, the verification of that action, and the result (`ok`, `warn`, `fail`). Log format: timestamp + phase + step + action + expected + actual + status. Log persists across phases. End-of-phase summary reports counts. Failed verifications do not necessarily abort — they get flagged for review. See §9.

## 4. Variants (allowed to differ)

| Area | Arch edition | Gentoo edition |
|---|---|---|
| Package manager | `pacman` + `paru` (AUR) | `portage` (`emerge`) |
| Base bootstrap | `pacstrap` from live ISO | stage3 + `default/linux/amd64/<ver>/desktop/systemd` profile, multilib enabled |
| Repo enablement helpers | `gitw-enable-blackarch`, `gitw-enable-chaotic-aur` | `gitw-enable-guru`, `gitw-enable-librewolf-overlay`, `gitw-enable-torbrowser-overlay` |
| AUR helper | `paru` (Rust) bootstrapped from `paru-bin` in Phase 3 | N/A |
| AUR review wrapper | `gitw-aur-review` | N/A |
| Build-mode toggle | `gitw-build-mode` (binary/source-preferred/source-only) | USE flags + documentation |
| Kernel | stock Arch `linux` | `sys-kernel/gentoo-kernel-bin` (dist-kernel) |
| Snapshots hook | `snap-pac` (pacman hook) | custom portage `/etc/portage/bashrc` hook (see §5) |
| Microcode | `intel-ucode` / `amd-ucode` | `sys-firmware/intel-microcode` / `sys-kernel/linux-firmware` |
| Librewolf | AUR via paru, `librewolf-bin` default (source build offered) | `www-client/librewolf` or `-bin` from official Librewolf overlay at codeberg.org/librewolf/gentoo |
| Tor Browser | AUR via paru (`torbrowser-launcher`) | `www-client/torbrowser` from torbrowser overlay |
| AppArmor | Arch package | Gentoo AppArmor; SELinux available as user choice in Phase 2 |
| Compilation flags | N/A | `make.conf` auto-generated with `cpuid2cpuflags`, `COMMON_FLAGS`, `MAKEOPTS` from nproc |
| Installation time | ~30–60 min | ~2–3 hours (stage3 + world); +1–2 hours if Librewolf source build |
| AI Python wheels | pip into venv (PyPI + PyTorch CUDA index) | portage first, pip fallback with warning |

## 5. Snapshot hook on Gentoo

`[LOCKED]` Option A: `/etc/portage/bashrc` hook. Gates on `EBUILD_PHASE` = `preinst`/`postinst` and `ROOT=/`. Calls `snapper -c root create --pre/--post`. Known limitation: per-package, not per-transaction. Document it.

## 6. AI stack (`gitw-ai`)

### Gating
`[LOCKED]` During Phase 3, detect NVIDIA GPU + CUDA. If present, prompt. If absent, skip silently. Can install later via `gitw-ai install --force`.

### Layout (identical on both editions)
- `/ai/pytorch-env/` — Python venv, PyTorch + CUDA wheels
- `/ai/tensorflow-env/` — separate venv (CUDA runtime conflicts prevent sharing)
- Ollama: `ollama.service`, `127.0.0.1:11434`
- Open WebUI: `open-webui.service`, `127.0.0.1:8080`
- Reverse proxy: **not bundled**. External reverse proxy documented as user exercise.

### `gitw-ai` CLI
```
gitw-ai install [--force]
gitw-ai remove [--purge]
gitw-ai status
gitw-ai models {list|pull <name>|rm <name>}
```

`[LOCKED]` **Runs as regular user.** Uses `sudo` internally for system-scope operations (package install, systemd services). Refuses to run as root.

## 7. CIS hardening (`gitw-cis`)

### v0.1 scope (minimal)
`[UPDATED 2026-04-29]` Ship the framework + 5 starter L1 controls as proof-of-concept. **Not** the full RHEL/Ubuntu benchmark adaptation — that's v0.2 work, sequenced after both editions reach feature parity and pass VM testing.

### Framework
Every control ships as a bundle under `shared/cis/<control_id>/`:
- `apply.sh` — idempotent; records previous state before changing
- `revert.sh` — restores recorded state
- `status.sh` — exits 0 (applied), 1 (not applied), 2 (indeterminate)
- `meta` — key=value: `id`, `level`, `title`, `rationale`, `reboot_required`, `impact`, `recommendation`

State: `/var/lib/gitw/cis/applied.json`.
Backups: `/var/lib/gitw/cis/backups/<control_id>/` holds original file copies.

### CLI
```
gitw-cis list [--level 1|2] [--applied|--not-applied]
gitw-cis apply [--level 1|2] [control_id ...]
gitw-cis revert [control_id ...]
gitw-cis status
gitw-cis diff <control_id>
```

### Initial v0.1 controls
1. `l1-fs-cramfs-disable` — blacklist cramfs kernel module
2. `l1-core-dump-restrict` — sysctl + limits.conf (augments Phase 2 defaults)
3. `l1-sshd-root-login` — `PermitRootLogin no`, no-op if sshd absent
4. `l1-login-defs-umask` — UMASK 027 in login.defs
5. `l1-inactive-password-lock` — PASS_MAX_DAYS + inactivity lockout

### v0.2 source materials
- **Primary:** RHEL benchmark (most mature, ~150 controls, well-tested adaptation patterns)
- **AppArmor specifics:** Ubuntu benchmark
- **Skip:** CIS DIL (last updated 2018, predates major systemd/cgroups/nftables/zram adoption)

Adaptation work scope: identify controls that apply to a workstation (skip server-only items), map each to Arch/Gentoo command equivalents, mark each L1 or L2, tag impact/recommendation, write apply/revert/status scripts, document in CIS_CONTROLS.md.

## 8. Threat modeling (out of scope for installer)

`[NEW 2026-04-29]` Replaces the removed `gitw-threat-profile` design.

### Why
Threat modeling is bigger than computer configuration. The choices that actually keep most people safe — where they live, who they talk to, what name appears on what document, what their lawyer is doing for them, how much money they have set aside — are upstream of any setting in `/etc/`. A multiple-choice quiz that produces an installer config creates false confidence in the wrong place.

### What ships instead
A worksheet at `docs/threat-modeling/THREAT_MODEL_WORKSHEET.md` plus a directory README explaining its purpose. Users:
1. Fill out the worksheet in plain language
2. Take the completed worksheet to an AI assistant for discussion
3. End up with an action plan
4. Sort the action items into "ghostinthewires can configure," "needs a lawyer," "needs a different conversation with a person in their life," and so on
5. Apply the configuration items via features.conf and helpers; address the rest separately

### Threat presets remain
`features.conf` keeps `THREAT_PROFILE=BASELINE|HARDENED|PARANOID|CUSTOM` as a hardening intensity dial:
- **BASELINE** — sensible hardening that doesn't break things; no CIS controls auto-applied
- **HARDENED** — adds controls that may require occasional troubleshooting; auto-applies all ★ Recommended CIS controls when v0.2 ships
- **PARANOID** — adds controls that will break some workflows; auto-applies all ★ Recommended + ☆ Situational CIS controls + lockdown=confidentiality
- **CUSTOM** — user tunes everything by hand

The preset is a hardening intensity dial, not a threat archetype selector. It says nothing about the user's life situation.

## 9. Runtime validation logging

`[NEW 2026-04-29]` Every install/harden/software phase emits structured log entries.

### Log file
`/var/log/gitw-install.log`. Persists across phases (Phase 2 appends to Phase 1's log). Permissions 0600 root:root.

### Entry format
Plain text, one entry per line, fields tab-separated:
```
<ISO-timestamp>\t<phase>\t<step>\t<action>\t<expected>\t<actual>\t<status>
```
Where `<status>` is one of `ok`, `warn`, `fail`. `warn` for verifications that returned unexpected-but-not-broken results; `fail` for verifications that returned values consistent with the action having no effect.

### Logging library
Shared shell library at `shared/lib/gitw-log.sh`, sourced by all phase scripts. Provides:
- `gitw_log_action <step> <action>` — record an action being taken
- `gitw_verify_kernel_param <param>` — assert a param is in /proc/cmdline
- `gitw_verify_service_enabled <service>` — assert a systemd unit is enabled
- `gitw_verify_file_contains <file> <pattern>` — assert file content
- `gitw_verify_luks_keyslot <device> <slot_type>` — assert keyslot exists
- `gitw_verify_pacman_pkg <package>` — assert package installed
- (additional verifiers as needed)

Each verifier emits a log entry. If the verification fails, the script may continue or abort depending on whether the failure is recoverable.

### End-of-phase summary
At the end of each phase, the script prints a summary:
```
Phase 1 complete:
  87 actions logged
  85 verified ok
  2 warnings (review /var/log/gitw-install.log)
  0 failures
```

## 10. Test harness

`[NEW 2026-04-29]` Two layers.

### Static (runs on developer machine, fast)
Lives in `tests/static/`:
- `tests/static/run-shellcheck.sh` — shellcheck on every script, fails on errors
- `tests/static/check-features-conf.sh` — schema validator
- `tests/static/check-helper-contract.sh` — every helper supports `--help`, exits 0, etc.
- `tests/static/check-parity.sh` — when both editions exist, helper CLIs match

### CIS round-trip (runs in container or scratch VM)
Lives in `tests/cis/`. For each control, runs apply → status (expect 0) → revert → status (expect 1). Verifies no residue files left behind.

### Integration (VM)
The runtime validation logging in §9 is the integration test. The expected outcome of a successful install is "all log entries `ok` at end of phase 3." Any `warn` or `fail` is reviewed.

## 11. Decisions locked in v0.3

- `[LOCKED 2026-04-29]` Project framing updated to "security-focused, reproducible Linux workstation, available in Arch and Gentoo editions with cross-edition user-facing parity."
- `[LOCKED 2026-04-29]` `gitw-threat-profile` removed from scope. Threat modeling worksheet ships in `docs/threat-modeling/` instead.
- `[LOCKED 2026-04-29]` CIS full benchmark adaptation deferred to v0.2. v0.1 ships framework + 5 starter controls only.
- `[LOCKED 2026-04-29]` Primary CIS benchmark source for v0.2 adaptation: RHEL (with Ubuntu for AppArmor specifics). DIL skipped due to staleness.
- `[LOCKED 2026-04-29]` Runtime validation logging required in all three phase scripts. Structured log to `/var/log/gitw-install.log`, end-of-phase summary, library at `shared/lib/gitw-log.sh`.
- `[LOCKED 2026-04-29]` Static test harness: shellcheck + schema validators + helper CLI contract tests + parity check.

## 12. Out of scope for v0.1

- BIOS-only support on Gentoo edition (Arch keeps BIOS support)
- Pentoo overlay integration
- `gitw-ai proxy` local reverse proxy
- SIEM log forwarder shipped config (DIY pattern documented only)
- Wintermute desktop build
- Hibernate support
- GUI installer — never in scope
- Combined unlock mode (TPM AND FIDO2 hook)
- Full CIS benchmark adaptation
- Fully autonomous AI-to-GitHub write loop — Claude opens PRs; user reviews and merges

## 13. v0.1 release gate

- [ ] Both editions install end-to-end in a VM (QEMU + OVMF + swtpm)
- [ ] All `gitw-*` helpers present and interface-compatible on both editions
- [ ] `features.conf` schema identical; every toggle honored on both editions
- [ ] AI stack installs cleanly with NVIDIA detected, skips cleanly without
- [ ] `gitw-cis apply` / `revert` round-trips correctly for the 5 starter controls on both editions
- [ ] Runtime validation logging produces clean log on a successful install
- [ ] Static test harness passes
- [ ] `docs/threat-modeling/` documents written
- [ ] `README.md`, `docs/comparison.md`, `arch/README.md`, `gentoo/README.md` written
- [ ] Combined unlock mode remains stubbed (documented, not a blocker)

## 14. v0.2 candidates

- Combined unlock hook (TPM + FIDO2 AND via custom initramfs hook)
- Full CIS benchmark adaptation (RHEL primary, Ubuntu for AppArmor)
- Local reverse proxy for AI stack (Caddy-based `gitw-ai proxy`)
- Wintermute desktop build
- Pentoo integration
- VPN-aware DNS profile auto-switching (NetworkManager dispatcher scripts)

## 15. Version history

- **v0.1** (initial draft) — Gentoo brought to parity with hArch.
- **v0.2** — Helper renames (`harch-*` → `gitw-*`), monorepo structure, Flatpak removed, paru bootstrap, CIS as standalone helper, threat presets renamed posture-based, `gitw-aur-review`.
- **v0.3** (current) — Project framing updated, `gitw-threat-profile` removed (replaced with worksheet), CIS full adaptation deferred to v0.2, runtime validation logging added, test harness scope defined, RHEL/Ubuntu chosen as v0.2 CIS source materials.
