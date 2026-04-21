#!/usr/bin/env bash
#
# ghostinthewires-arch Installer - Phase 3: Software
# https://github.com/wakefieldite/ghostinthewires
#
# Run this as your regular user (not root) after harden.sh has completed
# and you've rebooted. Installs:
#   - Hyprland Wayland compositor + ecosystem
#   - Librewolf with RFP defaults (no extra tweaking - see README)
#   - Tor Browser
#   - KeePassXC, media apps, terminal, fish shell
#   - Paru (Rust AUR helper)
#   - Librewolf + Tor Browser (via paru from AUR)
#
# Idempotent - safe to re-run.

set -o pipefail

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

die()  { echo -e "${RED}[!] $*${RESET}" >&2; exit 1; }
info() { echo -e "${GREEN}[*] $*${RESET}"; }
warn() { echo -e "${YELLOW}[!] $*${RESET}"; }
note() { echo -e "${BLUE}[i] $*${RESET}"; }
hdr()  { echo; echo -e "${BOLD}=== $* ===${RESET}"; echo; }

SENTINEL_DIR=/var/lib/gitw-install

[[ $EUID -ne 0 ]] || die "Run as your regular user, not root. (Uses sudo internally.)"
command -v sudo &>/dev/null || die "sudo required."
[[ -f $SENTINEL_DIR/phase-2-harden.done ]] || die "Phase 2 sentinel missing - run harden.sh first."

# =============================================================================
# GPU detection (can be overridden by /etc/gitw/features.conf GPU_VENDOR)
# =============================================================================

detect_gpu() {
  hdr "Detecting GPU"
  local override=""
  if [[ -f /etc/gitw/features.conf ]]; then
    # shellcheck disable=SC1091
    override=$(grep '^GPU_VENDOR=' /etc/gitw/features.conf | cut -d= -f2)
  fi

  if [[ -n $override ]]; then
    info "GPU vendor overridden in features.conf: $override"
    echo "$override"
    return
  fi

  local product
  product=$(sudo dmidecode -s system-product-name 2>/dev/null || echo unknown)
  if [[ $product == *VirtualBox* ]]; then echo "virtualbox"; return; fi
  if [[ $product == *VMware*    ]]; then echo "vmware";     return; fi

  local gpu_info
  gpu_info=$(lspci | grep -iE 'vga|3d|display' || true)
  echo "Detected GPU:" >&2
  echo "$gpu_info" >&2
  echo >&2

  local result=""
  [[ $gpu_info =~ [Ii]ntel ]]           && result+="intel+"
  [[ $gpu_info =~ AMD|ATI|Radeon ]]     && result+="amd+"
  if [[ $gpu_info =~ [Nn]vidia ]]; then
    # Blackwell (RTX 50xx) requires the open-source 'nvidia-open' driver.
    # Older cards can use proprietary 'nvidia'. Since we can't easily
    # identify Blackwell from lspci without a current card DB, ask the user.
    note "NVIDIA GPU detected. Choose driver:" >&2
    note "  1) nvidia-open     (required for RTX 50xx / Blackwell, works for 20xx+)" >&2
    note "  2) nvidia          (proprietary, for older cards; incompatible with lockdown=confidentiality)" >&2
    read -rp "Choice [1]: " choice >&2
    case "${choice:-1}" in
      2) result+="nvidia+" ;;
      *) result+="nvidia-open+" ;;
    esac
  fi
  result=${result%+}
  [[ -z $result ]] && result="generic"
  echo "$result"
}

# =============================================================================
# Core install
# =============================================================================

install_core() {
  hdr "Installing Hyprland and core Wayland ecosystem"
  local pkgs=(
    # Compositor
    hyprland xdg-desktop-portal-hyprland
    # Session essentials
    polkit polkit-gnome
    # Bar, launcher, notifications
    waybar wofi mako
    # Screenshots, clipboard, idle
    grim slurp wl-clipboard swayidle swaylock
    # Wallpaper
    hyprpaper
    # Terminal + shell
    alacritty fish starship
    # File manager (TUI + GUI option)
    ranger thunar
    # Fonts
    ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts noto-fonts-cjk noto-fonts-emoji
    # Audio (pipewire is the standard now)
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
    pavucontrol qpwgraph
    # Bluetooth
    bluez bluez-utils blueman
    # Editors
    neovim vim
    # Search / dev
    fd ripgrep fzf bat eza git tmux
    # System monitor
    btop htop lm_sensors
    # Screenshot tools
    flameshot  # X11-only but works under XWayland for quick use
    # Media players
    mpv imv
    # Password manager
    keepassxc
    # Privacy browser (from Arch extra? librewolf is in chaotic-aur and from flathub)
    # Librewolf and Tor Browser are installed via paru in a later step.
    # Common utilities
    jq unzip p7zip
  )
  sudo pacman -S --needed --noconfirm "${pkgs[@]}" || die "Core package install failed"
}

install_gpu_packages() {
  local gpu=$1
  hdr "Installing GPU packages for: $gpu"
  local pkgs=()
  local needs_nvidia_early_kms=0
  IFS='+' read -ra parts <<< "$gpu"
  for p in "${parts[@]}"; do
    case "$p" in
      intel)
        # xf86-video-intel is DEPRECATED. The modesetting driver in mesa is
        # the right choice for any Intel GPU from Gen 4 (2010) onward.
        pkgs+=(mesa vulkan-intel intel-media-driver libva-utils)
        ;;
      amd)
        pkgs+=(mesa vulkan-radeon libva-mesa-driver mesa-vdpau)
        ;;
      nvidia)
        pkgs+=(nvidia nvidia-utils nvidia-settings libva-nvidia-driver)
        needs_nvidia_early_kms=1
        warn "Proprietary nvidia driver is incompatible with lockdown=confidentiality."
        warn "Edit /etc/gitw/features.conf and set LOCKDOWN= (empty), then:"
        warn "    sudo gitw-reconfigure && reboot"
        ;;
      nvidia-open)
        pkgs+=(nvidia-open nvidia-utils nvidia-settings libva-nvidia-driver)
        needs_nvidia_early_kms=1
        ;;
      virtualbox)
        pkgs+=(virtualbox-guest-utils)
        ;;
      vmware)
        pkgs+=(xf86-video-vmware mesa open-vm-tools)
        ;;
      generic)
        pkgs+=(mesa)
        ;;
    esac
  done
  (( ${#pkgs[@]} > 0 )) && sudo pacman -S --needed --noconfirm "${pkgs[@]}"

  if (( needs_nvidia_early_kms )); then
    configure_nvidia_early_kms
  fi
}

configure_nvidia_early_kms() {
  hdr "Configuring NVIDIA early KMS"
  # Required for Hyprland/Wayland + NVIDIA to work correctly.

  # 1. Add modules to mkinitcpio so they load in early userspace.
  #    (Your old install script had these in HOOKS= which is wrong - they're
  #    modules, not hooks. HOOKS= only accepts things in /usr/lib/initcpio/hooks.)
  sudo sed -i \
    's/^MODULES=.*/MODULES=(btrfs nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
    /etc/mkinitcpio.conf

  # 2. Enable nvidia-drm KMS via modprobe config.
  sudo tee /etc/modprobe.d/nvidia.conf > /dev/null <<'EOF'
# ghostinthewires-arch: enable NVIDIA DRM kernel modesetting for Wayland (Hyprland, etc.)
options nvidia_drm modeset=1 fbdev=1
EOF

  # 3. Add nvidia-drm.modeset=1 to kernel cmdline as a belt-and-suspenders
  #    measure (modprobe.d covers the normal case; kernel cmdline covers
  #    early-boot edge cases).
  local current
  current=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | cut -d'"' -f2)
  if [[ ! $current =~ nvidia-drm\.modeset=1 ]]; then
    sudo sed -i \
      "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$current nvidia-drm.modeset=1\"|" \
      /etc/default/grub
  fi

  # 4. Regenerate initramfs and GRUB config.
  sudo mkinitcpio -P
  sudo grub-mkconfig -o /boot/grub/grub.cfg

  info "NVIDIA early KMS configured. Reboot required before Hyprland will work."
}

# =============================================================================
# Paru bootstrap + AUR-based browsers
# =============================================================================

bootstrap_paru() {
  hdr "Bootstrapping paru (Rust-based AUR helper)"
  if command -v paru &>/dev/null; then
    info "paru already installed, skipping bootstrap."
    return
  fi

  # Paru isn't in official repos - must build from AUR source once.
  # We build the -bin package (pre-compiled) to avoid pulling the full Rust
  # toolchain just for the bootstrap. Users wanting source-compile can later
  # `paru -S paru` to replace with source build.
  sudo pacman -S --needed --noconfirm base-devel git

  local build_dir
  build_dir=$(mktemp -d)
  git clone https://aur.archlinux.org/paru-bin.git "$build_dir/paru-bin" \
    || die "Failed to clone paru-bin AUR repo"

  note "Review paru-bin PKGBUILD before building?"
  note "The contents are at: $build_dir/paru-bin/PKGBUILD"
  read -rp "View PKGBUILD now? [Y/n] " yn
  yn=${yn:-y}
  if [[ $yn =~ ^[Yy]$ ]]; then
    "${PAGER:-less}" "$build_dir/paru-bin/PKGBUILD"
    read -rp "Proceed with build? [y/N] " yn2
    [[ $yn2 =~ ^[Yy]$ ]] || die "paru bootstrap aborted. You can re-run software.sh."
  fi

  ( cd "$build_dir/paru-bin" && makepkg -si --noconfirm ) \
    || die "paru-bin build failed"

  rm -rf "$build_dir"
  info "paru installed. Review AUR packages with: paru -Sa --review"
}

configure_paru() {
  # Enable review mode by default so users see PKGBUILDs before building.
  mkdir -p "$HOME/.config/paru"
  if [[ ! -f $HOME/.config/paru/paru.conf ]]; then
    cat > "$HOME/.config/paru/paru.conf" <<'EOF'
# ghostinthewires default paru config - opt for auditability.
# Edit to taste; see `man paru.conf`.
[options]
BottomUp
SudoLoop
CleanAfter
NewsOnUpgrade
# Show PKGBUILD diffs before building on updates
Review
# Use diff viewer of your choice
UpgradeMenu
CombinedUpgrade
EOF
    info "Wrote ~/.config/paru/paru.conf with review mode on."
  fi
}

install_browsers() {
  hdr "Installing browsers (Librewolf + Tor Browser, from AUR)"
  note "Librewolf and Tor Browser are AUR packages. paru will show you the"
  note "PKGBUILD before building. Read it. Accept with 'y' when satisfied."
  note ""
  note "IMPORTANT for Librewolf: the source-build PKGBUILD compiles Firefox from"
  note "source, which takes 1-3 hours. The -bin variant pulls a pre-built binary"
  note "from the upstream Librewolf CI. Default choice: librewolf-bin for speed."
  note "Swap to librewolf (source) later if you want to verify the build yourself."
  echo
  read -rp "Install librewolf-bin (faster) or librewolf (source, hours to build)? [bin/src] " choice
  choice=${choice:-bin}

  case "$choice" in
    src|source)
      paru -S --needed librewolf || warn "Librewolf source build failed"
      ;;
    *)
      paru -S --needed librewolf-bin || warn "Librewolf install failed"
      ;;
  esac

  # Tor Browser - always use the launcher since the browser itself auto-updates
  paru -S --needed torbrowser-launcher || \
    warn "Tor Browser install failed - you can install manually from torproject.org"

  note "Librewolf ships with privacy.resistFingerprinting=true by default."
  note "DO NOT add extra anti-fingerprinting tweaks without testing on"
  note "    https://coveryourtracks.eff.org first - most tweaks make you MORE unique."
  note "For anything where anti-fingerprinting actually matters, use Tor Browser."
  note ""
  note "Never modify Tor Browser. Never add extensions. That's what makes it safe."
}

install_first_run_guide() {
  hdr "Writing first-run guide"
  cat > "$HOME/gitw-first-run.txt" <<'EOF'
ghostinthewires-arch first-run checklist (user session):

1. Launch Librewolf. Visit https://addons.mozilla.org and install uBlock Origin.
2. Visit https://coveryourtracks.eff.org - note your uniqueness score. This is
   your baseline. Do NOT tweak prefs to try to "improve" it; you'll make
   yourself more identifiable, not less.
3. Launch Tor Browser (separate). Never modify its config. Never install addons.
4. Set up KeePassXC: create a new database, generate a long passphrase, store it.
5. Configure your VPN of choice:
     - WireGuard: nmcli connection import type wireguard file /path/to/config.conf
     - Or use the NetworkManager applet UI.
6. (Optional) Enroll a backup FIDO2 key: sudo gitw-unlock-mode enroll-fido2
7. (Optional, recommended) Enroll custom Secure Boot keys:
     sudo gitw-setup-secureboot
   This is what actually defeats evil-maid ESP tampering.
8. Review /etc/gitw/features.conf and run `sudo gitw-reconfigure` if changed.
9. Consider running the threat-profile questionnaire:
     gitw-threat-profile
   It will recommend additional hardening based on your situation.

For ongoing package management:
   paru -Syu            # update everything (repo + AUR)
   paru -Sa --review    # install an AUR package with PKGBUILD review

Troubleshooting common first-boot issues: see /root/gitw/README.md
EOF
  info "Wrote ~/gitw-first-run.txt"
}

# =============================================================================
# User shell setup
# =============================================================================

configure_fish() {
  hdr "Configuring fish shell (optional)"
  if confirm_yn "Set fish as your default shell?"; then
    chsh -s /usr/bin/fish || warn "chsh failed"
  fi
}

confirm_yn() {
  local prompt=$1 reply
  read -rp "$prompt [y/N] " reply
  [[ $reply =~ ^[Yy]$ ]]
}

# =============================================================================
# Minimal Hyprland starter config
# =============================================================================

write_hyprland_config() {
  hdr "Writing minimal Hyprland starter config"
  mkdir -p "$HOME/.config/hypr"
  if [[ -f $HOME/.config/hypr/hyprland.conf ]]; then
    note "~/.config/hypr/hyprland.conf already exists - not overwriting."
    return
  fi
  cat > "$HOME/.config/hypr/hyprland.conf" <<'EOF'
# Minimal ghostinthewires-arch Hyprland starter config.
# Customize to taste: https://wiki.hyprland.org/

monitor=,preferred,auto,1

$mainMod = SUPER
$terminal = alacritty
$menu = wofi --show drun

exec-once = waybar & mako & /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = hyprpaper

input {
  kb_layout = us
  follow_mouse = 1
  touchpad {
    natural_scroll = yes
  }
  sensitivity = 0
}

general {
  gaps_in = 4
  gaps_out = 8
  border_size = 2
  col.active_border = rgb(88c0d0)
  col.inactive_border = rgb(3b4252)
  layout = dwindle
}

decoration {
  rounding = 6
  blur {
    enabled = true
    size = 3
    passes = 1
  }
}

animations {
  enabled = yes
}

bind = $mainMod, Return, exec, $terminal
bind = $mainMod, Q, killactive
bind = $mainMod SHIFT, E, exit
bind = $mainMod, D, exec, $menu
bind = $mainMod, F, fullscreen
bind = $mainMod, Space, togglefloating

# Screenshot region
bind = $mainMod SHIFT, S, exec, grim -g "$(slurp)" - | wl-copy

# Lock
bind = $mainMod SHIFT, L, exec, swaylock -c 000000

# Workspaces 1-9
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
EOF
  info "Wrote ~/.config/hypr/hyprland.conf"
}

# =============================================================================
# Greeter / display manager
# =============================================================================

install_greetd() {
  hdr "Installing greetd display manager (Wayland-native, minimal)"
  sudo pacman -S --needed --noconfirm greetd greetd-tuigreet
  sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd Hyprland"
user = "greeter"
EOF
  sudo systemctl enable greetd.service
  info "greetd enabled. After reboot you'll see a minimal login prompt."
}

# =============================================================================
# Finalize
# =============================================================================

write_sentinel() {
  sudo mkdir -p /var/lib/gitw-install
  date -u +%FT%TZ | sudo tee /var/lib/gitw-install/phase-3-software.done >/dev/null
}

final_message() {
  cat <<EOF

${GREEN}${BOLD}=============================================${RESET}
${GREEN}${BOLD}  ghostinthewires-arch Phase 3 (software) complete.${RESET}
${GREEN}${BOLD}=============================================${RESET}

Reboot to land in Hyprland:
    systemctl reboot

First-run checklist: ~/gitw-first-run.txt

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
  local gpu
  gpu=$(detect_gpu)
  install_core
  install_gpu_packages "$gpu"
  bootstrap_paru
  configure_paru
  install_browsers
  install_first_run_guide
  write_hyprland_config
  install_greetd
  configure_fish
  write_sentinel
  final_message
}

main "$@"
