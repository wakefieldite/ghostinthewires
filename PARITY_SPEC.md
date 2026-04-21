# ghostinthewires Parity Specification

**Version:** 0.2
**Status:** Working draft. Locked decisions are marked `[LOCKED]`. Proposed decisions are marked `[PROPOSED]`. Superseded content is marked `[SUPERSEDED]` with a date.
**Source of truth:** This document. Any behavior change that would affect the user-visible CLI, config semantics, or security posture must be reflected here before landing in either edition.

---

## 1. Project identity

- `[LOCKED]` **Name:** `ghostinthewires` (plural — networks have many wires).
- `[LOCKED]` **No Mitnick homage.** Even though "Ghost in the Wires" is the title of his memoir, the name is descriptive-of-networking, not reference-dropping. The project earns its identity through its work.
- `[LOCKED]` **Monorepo** at `github.com/wakefieldite/ghostinthewires`, public, GPLv3.
- `[LOCKED]` **Editions:** `ghostinthewires-arch` (formerly hArch) and `ghostinthewires-gentoo` (new), in the `arch/` and `gentoo/` subdirectories of the monorepo.
- `[LOCKED]` **Helper prefix:** `gitw-*` on both editions, everywhere.

## 2. Repository layout

```
ghostinthewires/
├── README.md                   # Landing page
├── PARITY_SPEC.md              # This document
├── THREAT_MODEL.md             # Shared; interview pending
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
│   ├── config-templates/       # features.conf, nftables.conf, etc.
│   └── skel/                   # Hyprland starter configs
├── docs/
│   ├── install-arch.md
│   ├── install-gentoo.md
│   ├── comparison.md           # Side-by-side threat capability matrix
│   └── dev/                    # Testing, contributing
└── tests/                      # VM test harness per edition
```

Each edition's `install.sh` fetches its distro-specific helpers from `<edition>/helpers/` and the shared helpers from `shared/helpers/` into `/usr/local/bin/`.

## 3. Invariants (identical across both editions)

These do NOT vary by distro. If a change would violate an invariant, it requires an explicit decision update in this document before implementation.

1. **Three-phase install model** with sentinel files at `/var/lib/gitw-install/phase-N-<name>.done`.
2. **Init system:** systemd on both editions. Gentoo uses the `default/linux/amd64/<ver>/desktop/systemd` profile (multilib, desktop, systemd).
3. **Encryption:** LUKS2 + argon2id + aes-xts-plain64, pre-encryption random fill, encrypted `/boot` via GRUB.
4. **Unlock modes:** `simple` / `tpm-pin` (default) / `combined` (stubbed). Break-glass passphrase always in slot 0.
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
20. **Browsers:** `[UPDATED 2026-04-21 from v0.1]` Librewolf + Tor Browser from AUR on Arch (via paru), from official overlays on Gentoo. Flatpak removed from the default path. Rationale: preference for source builds + reducing attack surface. Flatpak remains a user-optional alternative documented but not automated.
21. **Login manager:** greetd + tuigreet.
22. **Compositor:** Hyprland. Ecosystem: waybar, alacritty, mako, fuzzel/wofi, hyprlock, hypridle, hyprpaper, xdg-desktop-portal-hyprland.
23. **GPU detection:** Intel / NVIDIA / AMD / VM. NVIDIA path supports Blackwell via `nvidia-open`. Early KMS configured for Hyprland.
24. **Firmware:** `fwupd` installed, LVFS documented.
25. **Features.conf:** `/etc/gitw/features.conf`, single shell-variable file, same schema across editions. `gitw-reconfigure` applies changes.
26. **Helper script contract:** same name, CLI, output format across editions. Implementation may differ; interface does not.
27. **Optional AI stack:** off by default. Auto-detect NVIDIA+CUDA during Phase 3, prompt, delegate to `gitw-ai install` if accepted. See §6.
28. **CIS hardening:** `[UPDATED 2026-04-21]` optional, selectable, revertible. NOT integrated into `features.conf` — standalone helper with its own state file. User consults `CIS_CONTROLS.md` for rationale and impact before applying. See §7.
29. **Threat model:** `THREAT_MODEL.md` generated from an interactive questionnaire (`gitw-threat-profile`). Both editions ship the same questionnaire. Output suggests (not applies) changes to `features.conf` and CIS controls. See §10.
30. **License:** GPLv3.
31. `[NEW 2026-04-21]` **AUR signature verification on Arch:** `gitw-aur-review` wraps paru to enforce PKGBUILD review, detect signing-key changes, and warn on unsigned packages. Config: `AUR_REQUIRE_SIGNED` in features.conf (`0`=warn, `1`=refuse, `never`=silent).

## 4. Variants (allowed to differ — documented divergences)

| Area | Arch edition | Gentoo edition |
|---|---|---|
| Package manager | `pacman` + `paru` (AUR) | `portage` (`emerge`) |
| Base bootstrap | `pacstrap` from live ISO | stage3 + `default/linux/amd64/<ver>/desktop/systemd` profile, multilib enabled |
| Repo enablement helpers | `gitw-enable-blackarch`, `gitw-enable-chaotic-aur` | `gitw-enable-guru`, `gitw-enable-librewolf-overlay`, `gitw-enable-torbrowser-overlay` |
| AUR helper | `paru` (Rust) bootstrapped from `paru-bin` in Phase 3 | N/A |
| AUR review wrapper | `gitw-aur-review` | N/A |
| Kernel | stock Arch `linux` | `sys-kernel/gentoo-kernel-bin` (dist-kernel) |
| Snapshots hook | `snap-pac` (pacman hook) | custom portage `/etc/portage/bashrc` hook (see §5) |
| Microcode | `intel-ucode` / `amd-ucode` | `sys-firmware/intel-microcode` / `sys-kernel/linux-firmware` |
| Librewolf | AUR via paru, `librewolf-bin` default (source build `librewolf` offered) | `www-client/librewolf` or `-bin` from the official Librewolf overlay at codeberg.org/librewolf/gentoo |
| Tor Browser | AUR via paru (`torbrowser-launcher`) | `www-client/torbrowser` from the `torbrowser` overlay |
| AppArmor | Arch package | Gentoo AppArmor; SELinux also available as user choice in Phase 2 |
| Compilation flags | N/A | `make.conf` auto-generated with `cpuid2cpuflags`, `COMMON_FLAGS`, `MAKEOPTS` from nproc |
| Installation time | ~30–60 min | ~2–3 hours (stage3 + world); Phase 3 adds 1–2 hours if Librewolf source build selected |
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

### Installation on Arch
1. `sudo pacman -S --needed python` + `paru -S ollama-cuda open-webui` (as user, paru handles sudo for install step)
2. User-scope venv creation + pip install of pytorch/tensorflow
3. `sudo systemctl enable --now ollama open-webui`

### Installation on Gentoo
1. `gitw-enable-guru` if not enabled
2. `sudo emerge --ask=n <atoms>` (portage first)
3. Fallback to pip with warning if portage build fails

### `gitw-ai` CLI
```
gitw-ai install [--force]
gitw-ai remove [--purge]
gitw-ai status
gitw-ai models {list|pull <name>|rm <name>}
```

`[LOCKED]` **Runs as regular user.** Uses `sudo` internally for system-scope operations (package install, systemd services). Refuses to run as root.

## 7. CIS hardening (`gitw-cis`)

### CLI
```
gitw-cis list [--level 1|2] [--applied|--not-applied]
gitw-cis apply [--level 1|2] [control_id ...]
gitw-cis revert [control_id ...]
gitw-cis status
gitw-cis diff <control_id>
```

### Contract
Every control ships as a bundle under `shared/cis/<control_id>/`:
- `apply.sh` — idempotent; records previous state before changing
- `revert.sh` — restores recorded state
- `status.sh` — exits 0 (applied), 1 (not applied), 2 (indeterminate)
- `meta` — key=value: `id`, `level`, `title`, `rationale`, `reboot_required`, `impact`, `recommendation`

State: `/var/lib/gitw/cis/applied.json` tracks what's applied when.
Backups: `/var/lib/gitw/cis/backups/<control_id>/` holds original file copies for revert.

### Initial v0.1 scope (5 L1 controls)
`[PROPOSED]` — subject to revision once CIS_CONTROLS.md is drafted:
1. `l1-fs-cramfs-disable` — blacklist cramfs kernel module
2. `l1-core-dump-restrict` — sysctl + limits.conf (augments Phase 2 defaults)
3. `l1-sshd-root-login` — `PermitRootLogin no`, no-op if sshd absent
4. `l1-login-defs-umask` — UMASK 027 in login.defs
5. `l1-inactive-password-lock` — PASS_MAX_DAYS + inactivity lockout

### Not features.conf-integrated
`[LOCKED 2026-04-21]` — CIS controls are discrete actions with snapshotted "before" states, not declarative toggles. Keeping them out of features.conf preserves the "one config, one command" model there. Users consult `CIS_CONTROLS.md` for per-control recommendations and impact.

## 8. Threat model & presets

### Presets
`[UPDATED 2026-04-21]` — replaces the v0.1 archetype-named presets. New structure names by **posture + skill**, not user archetype.

```
BASELINE    Core hardening that won't break anything for anyone.
            FDE, TPM unlock, firewall on, dnscrypt, MAC random.
            AppArmor installed but OFF. Kernel hardening at "safe"
            level (init_on_alloc/free on, lockdown OFF for compat).

HARDENED    BASELINE + AppArmor enabled with pre-tuned profiles for
            common apps, lockdown=integrity (weaker than confidentiality
            but compatible with most drivers), stricter firewall,
            stricter browser defaults. For users comfortable
            troubleshooting occasional app breakage.

PARANOID    HARDENED + lockdown=confidentiality (breaks proprietary
            NVIDIA + VirtualBox), encrypted random-key swap, MAC random
            per-boot, DNS forced through Tor if available, aggressive
            auto-lock. Expect things to break. Expect to spend time
            tuning.

CUSTOM      No preset; user tunes every field individually.
```

`features.conf` field: `THREAT_PROFILE=BASELINE|HARDENED|PARANOID|CUSTOM`. Default BASELINE.

### `gitw-threat-profile` questionnaire
`[PROPOSED]` Interactive script, ~15–20 questions across categories: physical security, adversary model, border crossings, activity profile, data sensitivity, recovery tolerance, network posture. Output:
- `~/gitw-threat-profile.md` — personalized threat model for the user
- `/etc/gitw/threat-profile.conf` — machine-readable profile
- Suggested `THREAT_PROFILE=` value (usually BASELINE or HARDENED; PARANOID requires explicit opt-in)
- Suggested CIS controls to consider
- Suggested features.conf tweaks beyond the preset

### Central `THREAT_MODEL.md`
Generic; covers evil-maid, targeted physical attacker, privacy hygiene, supply chain, explicit out-of-scope. Authored via an interactive interview (pending).

## 9. Decisions locked in this round

- `[LOCKED]` Name: `ghostinthewires` plural, no Mitnick homage.
- `[LOCKED]` Monorepo structure; single repo, both editions.
- `[LOCKED]` Helper prefix `gitw-*` on both editions.
- `[LOCKED]` Flatpak out of default path. AUR/overlays with signature verification are the primary trust layer.
- `[LOCKED]` Binary-default for package installs. Source builds opt-in via `gitw-build-mode` (Arch) or USE flags (Gentoo).
- `[LOCKED]` AUR helper is paru (Rust, memory safe). Bootstrapped via `paru-bin` in Phase 3.
- `[LOCKED]` `gitw-aur-review` wrapper enforces PKGBUILD review and detects signing-key changes.
- `[LOCKED]` CIS as a standalone helper, not integrated into features.conf.
- `[LOCKED]` Threat presets renamed to posture-based (BASELINE / HARDENED / PARANOID / CUSTOM).
- `[LOCKED]` AI helper runs as user, sudos for system-scope.
- `[LOCKED]` `gitw-cis` initial scope: 5 L1 controls, names proposed above.
- `[LOCKED]` `THREAT_MODEL.md` authored via interview, with `gitw-threat-profile` as the user-facing questionnaire.
- `[LOCKED]` `REPO_BASE` for install bootstrap points at `main` branch, not `dev`.

## 10. Out of scope for v0.1

- BIOS-only support on Gentoo edition (Arch keeps BIOS support)
- Pentoo overlay integration
- `gitw-ai proxy` local reverse proxy
- SIEM log forwarder shipped config (DIY pattern documented only)
- Wintermute desktop build (Ryzen 9950X3D + RTX 5090)
- Hibernate support
- GUI installer — never in scope
- Fully autonomous AI-to-GitHub write loop — Claude opens PRs; user reviews and merges

## 11. v0.1 release gate

- [ ] Both editions install end-to-end in a VM (QEMU + OVMF + swtpm)
- [ ] All gitw-* helpers present and interface-compatible on both editions
- [ ] `features.conf` schema identical; every toggle honored on both editions
- [ ] AI stack installs cleanly with NVIDIA detected, skips cleanly without
- [ ] `gitw-cis apply` / `revert` reversible for at least 5 L1 controls on both
- [ ] `gitw-threat-profile` questionnaire functional on both
- [ ] `THREAT_MODEL.md`, README, `docs/comparison.md` written
- [ ] Combined unlock mode remains stubbed on both editions (documented, not a blocker)

## 12. v0.2 candidates

- Combined unlock hook (TPM + FIDO2 AND via custom initramfs hook)
- CIS L2 controls
- Local reverse proxy for AI stack (Caddy-based `gitw-ai proxy`)
- Wintermute desktop build
- Pentoo integration
- VPN-aware DNS profile auto-switching (dispatcher scripts)
