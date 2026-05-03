# ghostinthewires

A security-focused, reproducible Linux workstation, available in **Arch** and **Gentoo** editions. The two editions maintain user-facing parity — same helper CLIs, same configuration schema, same behavior — and differ only where the underlying distribution forces them to.

**Current status:** v0.1 in development. Arch edition is code-complete pending tooling additions and VM testing. Gentoo edition is being ported to parity in a parallel effort.

## Editions

- **[ghostinthewires-arch](./arch/)** — Arch Linux edition. `pacman` + paru (AUR).
- **[ghostinthewires-gentoo](./gentoo/)** — Gentoo edition (in progress). `portage` + systemd profile.

Both editions share the helpers in [`shared/helpers/`](./shared/helpers/) — same CLI, same config format, same behavior. Decisions made in one edition apply to the other unless distro mechanics force a documented divergence.

## What you get

- **Full-disk encryption:** LUKS2 + argon2id + aes-xts-plain64, encrypted `/boot` via GRUB.
- **Hardware-backed unlock:** TPM2+PIN + FIDO2 (primary and backup keys), break-glass passphrase. `gitw-unlock-mode` manages it all.
- **Btrfs + Snapper + grub-btrfs:** rollback from the boot menu if an update breaks something.
- **Kernel hardening:** `lockdown`, `init_on_alloc/free`, `slab_nomerge`, MAC randomization, coredumps off. Toggleable via `/etc/gitw/features.conf`.
- **nftables firewall:** INPUT drop default, stateful responses allowed, SSH off by default. `gitw-firewall` for per-machine exceptions.
- **Private DNS:** dnscrypt-proxy with Anonymized DNSCrypt routes + blocklists. Three profiles: `home` (DHCP), `travel` (dnscrypt), `offline` (`/etc/hosts` only).
- **Hyprland on Wayland:** greetd login, NVIDIA early KMS including Blackwell (`nvidia-open`), no X11 dependency.
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
- **Educate, don't mystify.** Configs have comments. Helpers explain what they'd change before they change it.
- **Fallbacks at every layer.** TPM fails → FIDO2. FIDO2 fails → passphrase. Update breaks boot → snapshot rollback. You should always have a path back.
- **Threat modeling is upstream of installation.** This project hardens a workstation. It does not — and cannot — replace a lawyer, an address program, or the conversations you need to have with the people in your life. See [`docs/threat-modeling/`](./docs/threat-modeling/).
- **Trust ranking for software:**
  1. Official distro repos (signed, with reproducible-build verification where available)
  2. AUR (Arch) or overlays (Gentoo) with upstream signature verification via `validpgpkeys`
  3. AUR/overlays with hash-only verification
  4. Nothing else in the default path

## Documentation

- **[PARITY_SPEC.md](./PARITY_SPEC.md)** — the canonical specification for cross-edition parity. Source of truth for shared decisions.
- **[CIS_CONTROLS.md](./CIS_CONTROLS.md)** — per-control rationale, impact, recommendation. Read before running `gitw-cis apply`.
- **[docs/threat-modeling/](./docs/threat-modeling/)** — worksheet and guidance for thinking through your actual situation. Out of scope for the installer; the action plan that comes out of this is what determines what you turn on.
- **[arch/README.md](./arch/README.md)** — Arch-edition-specific notes.
- **[gentoo/README.md](./gentoo/README.md)** — Gentoo-edition-specific notes (when present).

## License

GPLv3. See [LICENSE](./LICENSE).

## Contributing

This is a single-maintainer project in active early development. Feedback, bug reports, and reproduction traces from VM testing are welcome as issues. PRs should reference a specific `PARITY_SPEC.md` decision or propose an amendment to it.

## Status of v0.1 release gate

- [x] Arch edition: three phases implemented, helpers renamed to `gitw-*`, monorepo layout
- [ ] Arch edition: `gitw-aur-review` (paru wrapper with PKGBUILD review and signing-key verification)
- [ ] Arch edition: `gitw-build-mode` (binary/source/source-only AUR build preference)
- [ ] Arch edition: `gitw-ai` helper
- [ ] Arch edition: `gitw-cis` framework + 5 starter L1 controls (full benchmark adaptation deferred to v0.2)
- [ ] Both editions: structured runtime validation logging during install/harden/software phases
- [ ] Both editions: static test harness (shellcheck, schema validators, helper CLI contract tests)
- [ ] Arch edition: VM-tested end-to-end (QEMU + OVMF + swtpm)
- [ ] Gentoo edition: ported to parity
- [ ] Gentoo edition: VM-tested end-to-end
- [ ] Both editions pass the parity checklist in `PARITY_SPEC.md` §11

## v0.2 candidates

- Combined unlock mode (TPM AND FIDO2 via custom initramfs hook)
- Full CIS benchmark adaptation (RHEL primary, Ubuntu for AppArmor)
- Local reverse proxy for AI stack
- Wintermute desktop build (Ryzen 9950X3D + RTX 5090)
- Pentoo overlay integration
- VPN-aware DNS profile auto-switching (NetworkManager dispatcher scripts)
