# ghostinthewires

A reproducible, opinionated, hardened Linux workstation installer — with or without a local AI stack — available on **Arch** and **Gentoo**. Identical in behavior and philosophy, differing only in package manager and base distro mechanics.

**Current status:** v0.1 in development. Arch edition is code-complete pending VM testing. Gentoo edition is being ported to parity.

## Editions

- **[ghostinthewires-arch](./arch/)** — Arch Linux edition. Three-phase installer; `pacman` + paru (AUR).
- **[ghostinthewires-gentoo](./gentoo/)** — Gentoo edition (in progress). Three-phase installer; `portage` + systemd profile.

Both editions share the helper scripts in [`shared/helpers/`](./shared/helpers/) — same CLI, same config format, same behavior. A decision made in one edition applies to the other unless distro mechanics force otherwise.

## What you get

- **Full-disk encryption:** LUKS2 + argon2id + aes-xts-plain64, encrypted `/boot` via GRUB.
- **Hardware-backed unlock:** TPM2+PIN + FIDO2 (primary and backup keys), break-glass passphrase. `gitw-unlock-mode` manages it all.
- **Btrfs + Snapper + grub-btrfs:** rollback from the boot menu if an update breaks something.
- **Kernel hardening:** `lockdown`, `init_on_alloc/free`, `slab_nomerge`, stateful MAC randomization, coredumps off. All toggleable via `/etc/gitw/features.conf`.
- **nftables firewall:** INPUT drop default, stateful responses allowed, SSH off by default. `gitw-firewall` for per-machine exceptions.
- **Private DNS:** dnscrypt-proxy with Anonymized DNSCrypt routes + blocklists. Three profiles: `home` (DHCP), `travel` (dnscrypt), `offline` (`/etc/hosts` only).
- **Hyprland + Wayland:** greetd login, NVIDIA early KMS including Blackwell (nvidia-open), no X11 dependency.
- **Browsers:** Librewolf + Tor Browser from AUR (Arch) or the official overlays (Gentoo). No Flatpak in the default path.
- **Optional AI stack:** Ollama + Open WebUI + PyTorch/TensorFlow venvs. Off by default, prompted if NVIDIA+CUDA detected. Managed via `gitw-ai`.
- **Optional CIS hardening:** selectable, revertible per-control. See [`CIS_CONTROLS.md`](./CIS_CONTROLS.md).

## Quick start (Arch edition)

From the Arch live ISO:

```bash
# 1. Connect to the network
iwctl  # for Wi-Fi
# (or let Ethernet do its thing)

# 2. Verify internet
ping -c 2 archlinux.org

# 3. Run the installer
curl -fsSL https://raw.githubusercontent.com/wakefieldite/ghostinthewires/main/arch/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

Follow the prompts. Target disk is only wiped after you type the device path twice to confirm.

When done, reboot. Log in as root, run `/root/gitw/harden.sh`. Reboot again. Log in as your user, run `/root/gitw/software.sh`.

## Philosophy

- **Secure by default, overridable in practice.** Every choice is explained and can be turned off.
- **Educate, don't mystify.** Configs have comments. Helpers explain what they'd change before they change it. `CIS_CONTROLS.md` documents impact for every control.
- **Fallbacks at every layer.** TPM fails → FIDO2. FIDO2 fails → passphrase. Update breaks boot → snapshot rollback. You should always have a path back.
- **Trust ranking for software:**
  1. Official distro repos (signed, with reproducible-build verification where available)
  2. AUR (Arch) or overlays (Gentoo) with upstream signature verification via `validpgpkeys`
  3. AUR/overlays with hash-only verification
  4. Nothing else in the default path

## Documentation

- **[PARITY_SPEC.md](./PARITY_SPEC.md)** — the canonical spec that keeps both editions aligned. Source of truth for decisions.
- **[CIS_CONTROLS.md](./CIS_CONTROLS.md)** — per-control rationale, impact, recommendation. Read before running `gitw-cis apply`.
- **[THREAT_MODEL.md](./THREAT_MODEL.md)** — what this system defends against and what it doesn't. *(In progress — interview pending.)*
- **[arch/README.md](./arch/README.md)** — Arch-edition-specific notes.
- **[gentoo/README.md](./gentoo/README.md)** — Gentoo-edition-specific notes.

## License

GPLv3. See [LICENSE](./LICENSE).

## Contributing

This is a single-maintainer project in active early development. Feedback, bug reports, and reproduction traces from VM testing are welcome as issues. PRs should reference a specific `PARITY_SPEC.md` decision or propose an amendment to it.

## Status of v0.1 release gate

- [x] Arch edition: three phases implemented, helpers renamed to `gitw-*`, monorepo layout
- [ ] Arch edition: VM-tested end-to-end (QEMU + OVMF + swtpm)
- [ ] Arch edition: `gitw-ai` helper
- [ ] Arch edition: `gitw-cis` helper + first 5 L1 controls
- [ ] Arch edition: `gitw-threat-profile` questionnaire
- [ ] Arch edition: `gitw-aur-review` signature verification wrapper
- [ ] Gentoo edition: ported to parity
- [ ] Gentoo edition: VM-tested end-to-end
- [ ] `THREAT_MODEL.md` drafted via user interview
- [ ] Both editions pass the parity checklist in `PARITY_SPEC.md` §10
