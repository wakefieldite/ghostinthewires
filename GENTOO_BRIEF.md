# Brief for the ghostinthewires-gentoo conversation

**Purpose:** bring the Gentoo edition to parity with the Arch edition. Read this document, then fetch `PARITY_SPEC.md` and `README.md` from the repo for canonical details.

**Repo:** `github.com/wakefieldite/ghostinthewires` (public). Fetch via `raw.githubusercontent.com/wakefieldite/ghostinthewires/main/...` at the start of each session.

## What's been done (Arch side)

The Arch edition is code-complete modulo VM testing. All three phase scripts (`install.sh`, `harden.sh`, `software.sh`) and 11 helpers (`shared/helpers/gitw-*` + `arch/helpers/gitw-enable-*`) pass `bash -n`. The user has not yet committed the code to the repo — they'll do that after this session ends. When the Gentoo conversation starts, it can fetch the current state from `main`.

Key Arch-side changes that affect parity:

1. **Renamed from `hArch` to `ghostinthewires-arch`.** All `harch-*` helpers are now `gitw-*`. `/etc/harch` → `/etc/gitw`. `/var/lib/harch-install` → `/var/lib/gitw-install`.
2. **Monorepo layout.** The old separate-repo plan is dead. Both editions live under one repo with `arch/`, `gentoo/`, `shared/` subdirs.
3. **Flatpak removed from default path.** Librewolf and Tor Browser come from AUR via paru on Arch. On Gentoo they should come from the official overlays as previously specified in the parity spec (§3, §4).
4. **Paru is the default AUR helper on Arch.** Bootstrapped via `paru-bin` in Phase 3 with PKGBUILD review prompted. No Gentoo equivalent needed (portage is the native path).
5. **Binary-default for package installs.** Users opt into source builds via `gitw-build-mode` on Arch (defers to USE flags on Gentoo, which are already source-oriented; the equivalent may be a helper that sets common binary-preferred flags or just documentation pointing at `*-bin` atoms).
6. **CIS not integrated into features.conf.** It's a standalone helper with its own state tracking. See parity spec §7.
7. **Threat presets renamed.** BASELINE / HARDENED / PARANOID / CUSTOM replaces the archetype-named presets. See §8.
8. **Threat model via interview.** A `gitw-threat-profile` helper produces a personalized document. User hasn't been interviewed yet — that's a future session.

## What the Gentoo edition needs

Minimum viable parity:

1. **`gentoo/install.sh`** — stage3 + systemd profile, LUKS2 + argon2id + encrypted /boot, GRUB, Btrfs with the same subvolume layout as Arch, TPM2+PIN + FIDO2 enrollment, Snapper. Use the Arch `install.sh` as the reference for behavior.
2. **`gentoo/harden.sh`** — identical output to Arch's harden.sh. Same `features.conf` schema. Same kernel cmdline params, same sysctl, same nftables config, same dnscrypt-proxy config, same NetworkManager config. The *implementation* differs (portage commands instead of pacman, custom bashrc hook instead of snap-pac) but every user-visible artifact under `/etc/gitw/` must match.
3. **`gentoo/software.sh`** — Hyprland + ecosystem via portage, GPU drivers (NVIDIA path with `nvidia-open` for Blackwell), Librewolf from the official overlay (`gitw-enable-librewolf-overlay`), Tor Browser from the torbrowser overlay (`gitw-enable-torbrowser-overlay`), greetd + tuigreet, same `~/gitw-first-run.txt` as Arch.
4. **`gentoo/helpers/gitw-enable-guru`** — add GURU overlay.
5. **`gentoo/helpers/gitw-enable-librewolf-overlay`** — add Librewolf overlay at codeberg.org/librewolf/gentoo. Auto-invoked during Phase 3 when Librewolf is selected.
6. **`gentoo/helpers/gitw-enable-torbrowser-overlay`** — add torbrowser overlay, sync, accept `~amd64` keyword. Auto-invoked during Phase 3 when Tor Browser is selected.
7. **`gentoo/helpers/gitw-selinux`** — enable/disable SELinux (Gentoo-only; hidden on Arch).

The 9 shared helpers in `shared/helpers/` work as-is on Gentoo because they use distro-neutral tooling (systemd-cryptenroll, nftables, NetworkManager, dnscrypt-proxy, sbctl). Copy them into `/usr/local/bin/` at install time.

## Specific things to resolve for Gentoo

These were either deferred or need the Gentoo perspective:

### Kernel + dist-kernel vs source
Spec says `sys-kernel/gentoo-kernel-bin` for v0.1. Confirm this actually produces a kernel with:
- CONFIG_DM_CRYPT, CONFIG_CRYPTO_AES, CONFIG_CRYPTO_XTS (LUKS)
- CONFIG_BTRFS_FS with CONFIG_BTRFS_FS_POSIX_ACL
- CONFIG_TCG_TPM2, CONFIG_TCG_CRB (TPM2)
- CONFIG_SECURITY_APPARMOR (AppArmor)
- CONFIG_NFT_* (nftables)
- CONFIG_ZRAM
- All the kernel hardening options that match Arch's default enabled

If `gentoo-kernel-bin` config is missing any of these, either switch to `gentoo-sources` + custom config (slow install, user-hostile) or document the gap.

### USE flags for a parity stack
The systemd profile covers most of it. Additional USE flags likely needed for:
- `btrfs` on util-linux and friends
- `cryptsetup` on systemd (for cryptenroll)
- `tpm` on relevant packages
- `apparmor` if building a kernel that needs it
- `hyprland`-related flags on ecosystem packages
- `vaapi`, `vulkan` for GPU accel
- `pipewire`, `wayland` for audio/display

The Gentoo conversation should produce a `make.conf` template and a `package.use` template that gets written during Phase 1.

### Portage bashrc snapshot hook
`[LOCKED]` Option A from the parity spec: `/etc/portage/bashrc` that calls `snapper create --pre`/`--post` gated on `EBUILD_PHASE` = `preinst`/`postinst` and `ROOT=/`. The user accepts per-package rather than per-transaction.

### Python AI wheels — portage-first with pip fallback
Portage has `sci-libs/pytorch` but it's often behind. The spec says: try portage first, fall back to pip with a loud warning about weakening the trust model. Implementation: `gitw-ai` on Gentoo does `emerge --ask=n` first, checks exit status, and if non-zero drops to pip with `[gitw] WARNING: <pkg> installed via pip, bypassing portage. See THREAT_MODEL.md.`

### Compilation time warnings
Gentoo stage3 + world build is ~2-3 hours. Phase 3 with source Librewolf is another 1-2 hours. `gentoo/install.sh` should warn up front about this and offer coffee-break checkpoints.

## What you don't need to redo

The following are done, shared, and don't need a Gentoo-specific version:
- `gitw-reconfigure`, `gitw-unlock-mode`, `gitw-dns-profile`, `gitw-firewall`, `gitw-apparmor`, `gitw-setup-secureboot`, `gitw-network-check`, `gitw-tpm-reenroll`, `gitw-verify-fingerprint` — all in `shared/helpers/`, all work on Gentoo with systemd.
- `features.conf` schema — identical, just read `shared/config-templates/features.conf` and ship it.
- nftables ruleset — identical, in `shared/config-templates/nftables.conf`.
- dnscrypt-proxy config — identical.

## Things that remain open

- `gitw-ai` is not yet implemented on either edition. Whoever builds it first (probably Arch) sets the pattern; Gentoo ports it.
- `gitw-cis` is not yet implemented on either edition. Same deal.
- `gitw-threat-profile` is not yet implemented; an interview is pending.
- Combined unlock mode is stubbed on both editions. Documented as experimental. Don't implement in v0.1.

## Protocol for keeping in sync

1. At the start of each session, fetch `PARITY_SPEC.md` from the repo. Treat it as canonical.
2. If you're about to make a decision that would diverge from Arch without a documented distro-forced reason, stop. Propose an amendment to the parity spec instead.
3. Produce changes as patch files or file contents for the user to commit. You don't have direct write access.
4. When a decision gets locked, update `PARITY_SPEC.md` with `[LOCKED]` and a date stamp.
5. The user is the arbiter for any cross-edition conflict.

## One honest flag

The Arch conversation (me) has not VM-tested any of the code. Every "this works" claim in the Arch edition is a `bash -n` syntax-passes claim, not a "runs end-to-end in QEMU" claim. The Gentoo edition starts with the same caveat. The first edition to actually boot in QEMU sets the empirical baseline.
