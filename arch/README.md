# ghostinthewires-arch

The Arch Linux edition of ghostinthewires. For philosophy, feature list, and parity goals, see the [top-level README](../README.md).

## What lives here

- `install.sh` — Phase 1: partition, encrypt, pacstrap, bootloader, TPM2/FIDO2 enrollment
- `harden.sh` — Phase 2: kernel hardening, firewall, DNS, NetworkManager, AppArmor install
- `software.sh` — Phase 3: Hyprland stack, GPU drivers, paru + Librewolf + Tor Browser
- `helpers/` — Arch-specific helpers:
  - `gitw-enable-blackarch` — add BlackArch repo as a source (no tool mass-install)
  - `gitw-enable-chaotic-aur` — add Chaotic-AUR repo for pre-built AUR packages

Distro-neutral helpers (same on Arch and Gentoo) are in [`../shared/helpers/`](../shared/helpers/).

## Arch-specific notes

### AUR helper: paru

Paru is installed automatically during Phase 3. It's bootstrapped from `paru-bin` (the pre-compiled AUR package) to avoid pulling the full Rust toolchain just for the bootstrap. If you want to rebuild from source later:

```bash
paru -S paru
```

Paru is configured for review mode by default — PKGBUILDs are displayed before building. You can dismiss with Enter after a quick look, or actually read the file first.

### Trust ordering

The Arch edition sources software in this order:
1. Official Arch repos (`pacman`). Signed by Arch TUs.
2. AUR via paru, with PKGBUILD review enforced. `gitw-aur-review` (coming) adds signing-key-change detection and warns on unsigned packages.
3. Nothing else in the default path. Flatpak and snap are not installed. Users who want them can add them manually.

### Kernel

Stock Arch `linux` kernel. Microcode auto-detected (intel-ucode or amd-ucode based on `/proc/cpuinfo`).

### Build mode

Default is binary-preferred (`-bin` AUR variants where available). Toggle with:

```bash
# Coming in v0.1:
gitw-build-mode source-preferred  # compile from source, with some exceptions (chromium, etc.)
gitw-build-mode source-only       # no exceptions; be prepared to wait
gitw-build-mode binary-preferred  # default
```

## Bootstrap flow

From the Arch live ISO:

```bash
iwctl                       # connect Wi-Fi if needed
# station wlan0 connect "MyNetwork"
# exit

ping -c 2 archlinux.org     # verify connectivity

curl -fsSL https://raw.githubusercontent.com/wakefieldite/ghostinthewires/main/arch/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

After install reboot and log in as root:

```bash
cd /root/gitw
./harden.sh
```

After harden reboot and log in as your regular user:

```bash
cd /root/gitw
./software.sh
```

See `~/gitw-first-run.txt` after software.sh completes for your personal checklist.

## Troubleshooting

See the top-level `docs/troubleshooting.md` (coming).

Common issues:
- **TPM unlock failed after firmware update:** use passphrase to boot, then `sudo gitw-tpm-reenroll`
- **AppArmor blocking an app:** `sudo journalctl -k | grep apparmor="DENIED"`, either tune the profile or `sudo gitw-apparmor disable`
- **Network broken after DNS profile change:** `sudo gitw-dns-profile home` as a fallback, then `sudo gitw-network-check`
