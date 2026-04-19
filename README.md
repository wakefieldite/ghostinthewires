# ghostinthewire

> *You have nothing to hide. You just have nothing you want to freely give them.*

A hardened Gentoo Linux installer built for people who understand that privacy is not a privilege — it's a human right enshrined in the United Nations Universal Declaration of Human Rights. Businesses and governments have demonstrated they will not respect that right voluntarily. This project takes away their ability to violate it.

---

## Philosophy

Your data is a product. Browsing habits, location, communications, associations — bought, sold, and in many cases handed to agencies that were told to stop collecting it warrantlessly and simply started purchasing it instead. The advertising industry is your most pervasive adversary. Intelligence agencies have access to backbone internet infrastructure that makes them a different category of threat entirely.

This is not paranoia. This is an accurate reading of publicly documented programs and business models.

The UN Universal Declaration of Human Rights recognizes privacy as a fundamental right. Most of the entities you interact with online do not. ghostinthewire is one way to take that right back in practice rather than in principle.

**ghostinthewire** exists because:

- **Privacy requires deliberate action.** Default configurations are optimized for the vendor, not for you. Every default you accept is a choice you didn't make.
- **Gentoo over Arch.** Portage packages are maintained by a vetted community. The AUR accepts contributions from anyone. Supply chain attacks are real and the difference in trust model matters.
- **Compilation is control.** Building from source with your own flags means you know what you're running. It also means your binaries are not identical to anyone else's.
- **Encryption is a choice, not a checkbox.** LUKS2 with argon2id is the default here because argon2id's memory-hard design provides meaningful resistance to GPU-accelerated brute force. Other KDFs work. Weak passphrases don't. Choose accordingly.
- **AI is infrastructure now.** Whether you work in security, development, or research, understanding how these systems work — not just how to use them — is increasingly relevant. Running models locally means your data and your queries stay on your hardware.
- **Linux extends hardware life.** Modern Linux runs well on hardware that current Windows versions treat as obsolete. Keeping functional hardware in use is practical, not ideological.

---

## What ghostinthewire installs

### Phase 1 — `install.sh` (base system, ~1-2 hours)

- Disk wipe with `/dev/urandom` fill
- LUKS2 full disk encryption with `argon2id` KDF, AES-XTS-512
- BTRFS filesystem
- Gentoo stage3 extraction
- `make.conf` with auto-detected CPU flags via `cpuid2cpuflags`
- Distribution kernel (no `menuconfig` required, optimizable post-install)
- OpenRC init system
- NetworkManager + iwd
- GRUB with `cryptdevice` kernel parameter
- Base user setup with wheel group

### Phase 2 — `setup.sh` (desktop + tools, run after first boot)

- Hyprland Wayland compositor
- Waybar, fuzzel, mako, alacritty, hyprlock, hypridle
- swaybg with procedurally generated wallpaper
- Firefox (compiled from source with Gentoo hardened flags)
- NVIDIA drivers + CUDA (interactive, requires license acceptance)
- Ollama + Open WebUI (local LLM inference)
- PyTorch + CUDA (via pip into isolated venv)
- TensorFlow + CUDA (via pip into isolated venv)
- QEMU/KVM + virt-manager (for lab environments and HTB)
- CIS hardening (optional — Level 1 and Level 2 available as flags)
  - L1: conservative, unlikely to break things
  - L2: aggressive, may break software, generates significant audit logs — not appropriate for all threat models
- xdg-desktop-portal-hyprland
- starship prompt
- neovim + LazyVim

### Phase 3 — `configs/` (dotfiles)

All configuration files used by the install, versioned and maintained:

- `hyprland.conf` — phosphor green aesthetic, NVIDIA Optimus setup
- `waybar/` — system monitoring bar
- `alacritty.toml` — DejaVu Sans Mono, phosphor green
- `btop/` — braille graphs, matrix theme
- `mako/config` — notification daemon
- `starship.toml` — username-aware prompt
- `fastfetch/` — system info display
- `make.conf` — Gentoo portage configuration
- `kernel.config` — starting point kernel configuration

---

## Target Hardware

ghostinthewire was developed and tested on a **Dell Precision 7740**:

- Intel Core i9-9880H (Coffee Lake, 8c/16t, AVX2, FMA3)
- 128GB DDR4 RAM
- NVIDIA Quadro RTX 3000 (Turing, 6GB VRAM) + Intel UHD 630
- 4x NVMe SSDs
- 4K display

The installer is designed to be hardware-agnostic with auto-detection where possible, but NVIDIA Optimus configurations (discrete GPU + Intel iGPU driving the display) have received the most testing.

---

## Prerequisites

- A bootable Gentoo minimal install ISO
- Internet connection
- Target NVMe drive (installer will ask which device)
- Time — Gentoo is not fast to install. Phase 1 is automated. Phase 2 involves long builds.

---

## Usage

Boot the Gentoo minimal install ISO, connect to the internet, then:

```bash
curl -O https://raw.githubusercontent.com/wakefieldite/ghostinthewire/main/install.sh
chmod +x install.sh
./install.sh
```

After first boot into the installed system:

```bash
curl -O https://raw.githubusercontent.com/wakefieldite/ghostinthewire/main/setup.sh
chmod +x setup.sh
./setup.sh
```

---

## Why not just use an existing installer?

Because none of them make the choices this project makes. Most Gentoo installers optimize for getting you to a desktop as fast as possible. ghostinthewire optimizes for getting you to a desktop that an adversary cannot trivially compromise, surveil, or fingerprint — and that you actually understand because you built it.

---

## Status

🚧 **Active development.** Phase 1 is in progress. Phase 2 and configs are being ported from a working reference installation.

---

## Contributing

PRs welcome. If you understand why this project exists, you probably understand how to contribute to it responsibly.

---

## License

GPLv3. Because software freedom is part of the same fight.
