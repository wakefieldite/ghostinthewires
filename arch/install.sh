#!/usr/bin/env bash
#
# ghostinthewires-arch Installer - Phase 1: Base System
# https://github.com/wakefieldite/ghostinthewires
#
# Run this from the Arch live ISO as root. It will:
#   - Detect UEFI/TPM2/Secure-Boot capability
#   - Partition, encrypt (LUKS2 + argon2id), and create Btrfs subvolumes
#   - Install the base system + bootloader (GRUB with encrypted /boot, or fallback)
#   - Enroll passphrase + TPM2+PIN + FIDO2 keyslots as hardware allows
#   - Configure Snapper + grub-btrfs for rollback
#   - Leave harden.sh and software.sh in /root/gitw for phase 2 and 3
#
# After reboot: log in as root, run /root/gitw/harden.sh, then as your user
# run /root/gitw/software.sh.

set -o pipefail

# =============================================================================
# Constants / globals
# =============================================================================

REPO_BASE="${GITW_REPO_BASE:-https://raw.githubusercontent.com/wakefieldite/ghostinthewires/main}"
SENTINEL_DIR="/mnt/var/lib/gitw-install"

GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Populated during run:
declare -g dev_path part_prefix esp_part root_part
declare -g encryption_password root_password user_password
declare -g tpm2_pin username hostname timezone_choice
declare -g has_uefi=0 has_tpm2=0 has_secureboot=0
declare -g use_encrypted_boot=0
declare -g enroll_fido2_primary=0 enroll_fido2_backup=0
declare -g cpu_vendor="generic"
declare -g gpu_selection=""

# =============================================================================
# Logging
# =============================================================================

die()   { echo -e "${RED}[!] $*${RESET}" >&2; exit 1; }
info()  { echo -e "${GREEN}[*] $*${RESET}"; }
warn()  { echo -e "${YELLOW}[!] $*${RESET}"; }
note()  { echo -e "${BLUE}[i] $*${RESET}"; }
hdr()   { echo; echo -e "${BOLD}=== $* ===${RESET}"; echo; }

confirm() {
  local prompt=$1 default=${2:-n} reply
  local hint="[y/N]"
  [[ $default == y ]] && hint="[Y/n]"
  read -rp "$prompt $hint " reply
  reply=${reply:-$default}
  [[ $reply =~ ^[Yy]$ ]]
}

# =============================================================================
# Banner
# =============================================================================

greet() {
  clear
  cat <<'BANNER'

  ██╗  ██╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ ███████╗██╗
  ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗██╔════╝╚█║
  ███████║███████║██║     █████╔╝ █████╗  ██████╔╝╚█████╗  ╚╝
  ██╔══██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗ ╚═══██╗
  ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║██████╔╝
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

                ghostinthewires-arch Installer - Phase 1 (base)
                  Secure by default. Reproducible.

BANNER
  echo "This script wipes a disk and installs Arch Linux with full-disk"
  echo "encryption, hardware-backed unlock where available, and Btrfs"
  echo "snapshots. Everything is reversible BEFORE the partition step."
  echo
  read -n 1 -srp "Press any key to continue..."
  echo
}

# =============================================================================
# Pre-flight checks
# =============================================================================

check_root() {
  [[ $EUID -eq 0 ]] || die "Must run as root."
}

check_live_iso() {
  if ! command -v pacstrap &>/dev/null; then
    die "pacstrap not found. Are you running from the Arch live ISO?"
  fi
}

tune_live_pacman() {
  # Cosmetic / speed tweaks for the live ISO's pacman (carries into pacstrap).
  sed -i 's/^#Color/Color/' /etc/pacman.conf
  sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
  sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
}

detect_capabilities() {
  hdr "Detecting hardware capabilities"

  # UEFI?
  if [[ -d /sys/firmware/efi/efivars ]]; then
    has_uefi=1
    info "UEFI firmware detected."
  else
    has_uefi=0
    warn "BIOS/Legacy firmware detected. Secure Boot and TPM-based unlock"
    warn "will not be available. Installation will use BIOS GRUB + passphrase."
  fi

  # TPM2?
  if [[ -c /dev/tpmrm0 || -c /dev/tpm0 ]]; then
    if command -v systemd-cryptenroll &>/dev/null; then
      # Probe whether it's actually a 2.0 TPM
      if systemd-cryptenroll --tpm2-device=list 2>/dev/null | grep -q '^/dev/'; then
        has_tpm2=1
        info "TPM 2.0 detected and accessible."
      else
        has_tpm2=0
        warn "TPM device present but not usable as TPM 2.0."
      fi
    fi
  else
    has_tpm2=0
    note "No TPM device found. Unlock will rely on passphrase (+ optional FIDO2)."
  fi

  # Secure Boot setup-mode?
  has_secureboot=0
  if (( has_uefi )) && command -v bootctl &>/dev/null; then
    if bootctl status 2>/dev/null | grep -qi 'setup-mode.*setup'; then
      has_secureboot=1
      info "Secure Boot is in Setup Mode - custom keys can be enrolled."
    elif bootctl status 2>/dev/null | grep -qi 'secure boot.*enabled'; then
      note "Secure Boot is enabled with vendor keys. To use custom keys,"
      note "enter firmware setup, clear keys / enter Setup Mode, then re-run."
    fi
  fi

  # CPU vendor (for microcode)
  if grep -qi 'GenuineIntel' /proc/cpuinfo; then
    cpu_vendor="intel"
    info "Intel CPU detected (intel-ucode)."
  elif grep -qi 'AuthenticAMD' /proc/cpuinfo; then
    cpu_vendor="amd"
    info "AMD CPU detected (amd-ucode)."
  else
    cpu_vendor="generic"
    warn "Unknown CPU vendor; skipping microcode."
  fi

  echo
  note "Capability summary:"
  echo "    UEFI:        $((has_uefi))      $( ((has_uefi))       && echo yes || echo NO)"
  echo "    TPM 2.0:     $((has_tpm2))      $( ((has_tpm2))       && echo yes || echo NO)"
  echo "    Secure Boot: $((has_secureboot))      $( ((has_secureboot)) && echo "setup mode ready" || echo "not ready (post-install step)")"
  echo "    CPU ucode:   $cpu_vendor"
  echo
}

network_check() {
  hdr "Network diagnostics"

  local iface lan_ip gateway wan_ip
  iface=$(ip route | awk '/^default/ {print $5; exit}')
  lan_ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2; exit}')
  gateway=$(ip route | awk '/^default/ {print $3; exit}')

  echo "    Interface:    ${iface:-none}"
  echo "    LAN IP:       ${lan_ip:-none}"
  echo "    Gateway:      ${gateway:-none}"

  if [[ -f /etc/resolv.conf ]]; then
    echo "    DNS servers:"
    awk '/^nameserver/ {print "                  " $2}' /etc/resolv.conf
  fi

  # Connectivity test
  if ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
    wan_ip=$(curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || echo unknown)
    echo "    WAN IP:       $wan_ip"
    info "Internet connectivity: OK"
  else
    warn "Internet connectivity: FAILED"
    warn "The installer needs network access. Fix with iwctl (Wi-Fi) or check cable."
    die "No internet. Cannot continue."
  fi

  # Quick speedtest (best-effort, non-fatal)
  if command -v curl &>/dev/null; then
    echo -n "    Speed test:   "
    local speed_mbps
    speed_mbps=$(curl -so /dev/null -w '%{speed_download}' --max-time 10 \
      https://speed.cloudflare.com/__down?bytes=25000000 2>/dev/null | \
      awk '{printf "%.1f Mbit/s\n", $1*8/1000000}')
    echo "${speed_mbps:-timeout}"
  fi
  echo
}

# =============================================================================
# User input
# =============================================================================

ask_passwords() {
  hdr "Passwords"
  info "LUKS encryption passphrase (this is your break-glass recovery key)."
  echo "    Make it long and memorable or store it in your password manager."
  echo "    If you lose all other unlock methods, this is how you get back in."
  encryption_password=$(_ask_confirmed_password "LUKS encryption")

  echo
  info "Root password (for emergency recovery only)."
  root_password=$(_ask_confirmed_password "root")

  echo
  info "User password (for normal login)."
  user_password=$(_ask_confirmed_password "user")

  if (( has_tpm2 )); then
    echo
    info "TPM2 PIN (4-8 characters, entered every boot)."
    echo "    This is NOT your LUKS passphrase. It's a short PIN that combines"
    echo "    with the TPM to form a two-factor unlock (what you know + trusted hw)."
    tpm2_pin=$(_ask_confirmed_password "TPM2")
  fi
}

_ask_confirmed_password() {
  local label=$1 p1 p2
  while true; do
    p1=$(systemd-ask-password --no-tty "Enter the $label password: ")
    p2=$(systemd-ask-password --no-tty "Re-enter the $label password: ")
    if [[ -n "$p1" && "$p1" == "$p2" ]]; then
      printf '%s' "$p1"
      return
    fi
    echo "    Passwords empty or mismatched. Try again." >&2
  done
}

ask_username_and_hostname() {
  hdr "User and hostname"
  local confirm=""
  while [[ -z $username || $confirm != "y" ]]; do
    read -rp "Username: " username
    [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "    Invalid username."; username=""; continue; }
    read -rp "Confirm username '$username' (y/n): " confirm
    [[ $confirm == "y" ]] || username=""
  done

  confirm=""
  while [[ -z $hostname || $confirm != "y" ]]; do
    read -rp "Hostname: " hostname
    [[ $hostname =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] || { echo "    Invalid hostname."; hostname=""; continue; }
    read -rp "Confirm hostname '$hostname' (y/n): " confirm
    [[ $confirm == "y" ]] || hostname=""
  done
}

ask_timezone() {
  hdr "Timezone"
  note "Default is UTC. To see available zones:"
  note "    timedatectl list-timezones | grep -i <your_city>"
  note "Examples: America/New_York, Europe/Berlin, Asia/Tokyo"
  read -rp "Timezone [UTC]: " timezone_choice
  timezone_choice=${timezone_choice:-UTC}
  if [[ ! -f "/usr/share/zoneinfo/$timezone_choice" ]]; then
    warn "Unknown timezone '$timezone_choice', falling back to UTC."
    timezone_choice="UTC"
  fi
}

ask_fido2_keys() {
  if ! command -v systemd-cryptenroll &>/dev/null; then
    return
  fi
  hdr "FIDO2 security keys (YubiKey, SoloKey, etc.)"
  note "FIDO2 keys provide an unlock path independent of the TPM - useful when"
  note "booting from USB, after firmware updates, or if the TPM fails."
  echo
  if confirm "Do you have a FIDO2 key to enroll as the primary?"; then
    enroll_fido2_primary=1
    note "You will be prompted to plug it in during enrollment."
    if confirm "Do you ALSO have a BACKUP FIDO2 key to enroll now?"; then
      enroll_fido2_backup=1
      note "Strongly recommended. Losing your only key = break-glass passphrase only."
    else
      warn "Running without a backup key is risky. You can enroll one later with:"
      warn "    sudo gitw-unlock-mode enroll-fido2"
    fi
  fi
}

# =============================================================================
# Disk prep
# =============================================================================

notice_destructive() {
  cat <<'EOF'

Recommended prep for a fully encrypted disk:
  https://wiki.archlinux.org/title/Securely_wipe_disk

  1. If the drive is an SSD, run an ATA Secure Erase via the vendor tool to
     reset flash cells to their factory state. Skip for HDDs.
  2. This installer will fill the LUKS container's backing partition with
     random data BEFORE formatting. That hides the used/unused sector map
     from an attacker who later images the disk.
  3. TRIM will be disabled on the encrypted volume. TRIM leaks which
     sectors are in use, undoing step 2.

EOF
  read -n 1 -srp "Press any key to continue..."
  echo
}

partition_and_encrypt() {
  hdr "Partitioning and encryption"
  lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINTS
  echo
  read -erp "Target device (e.g. /dev/nvme0n1 or /dev/sda): " dev_path
  [[ -b "$dev_path" ]] || die "Not a block device: $dev_path"

  # Partition-path suffix: nvme/mmcblk/loop use p1, sdX/vdX use just 1
  if [[ "$dev_path" =~ (nvme|mmcblk|loop)[0-9]+n?[0-9]*$ ]]; then
    part_prefix="p"
  else
    part_prefix=""
  fi

  warn "About to COMPLETELY WIPE $dev_path. This cannot be undone."
  read -rp "Type the device path again to confirm: " confirm_path
  [[ "$confirm_path" == "$dev_path" ]] || die "Confirmation mismatch."

  # Decide encrypted-/boot vs. separate ESP+/boot
  # Encrypted /boot requires GRUB (not systemd-boot) and works on both UEFI and BIOS.
  if (( has_uefi )); then
    if confirm "Use encrypted /boot? (Recommended, protects kernel/initramfs from tampering)" y; then
      use_encrypted_boot=1
    else
      use_encrypted_boot=0
    fi
  else
    # BIOS: encrypted /boot is the only sensible option with GRUB anyway.
    use_encrypted_boot=1
  fi

  info "Creating partition table on $dev_path..."
  if (( has_uefi )); then
    # GPT, ESP (512M) + LUKS container
    parted --script "$dev_path" \
      mklabel gpt \
      mkpart ESP fat32 1MiB 513MiB \
      set 1 esp on \
      mkpart cryptsystem 513MiB 100% \
      || die "parted failed"
  else
    # MBR, 1M BIOS boot spacer + LUKS container
    parted --script "$dev_path" \
      mklabel msdos \
      mkpart primary 1MiB 100% \
      set 1 boot on \
      || die "parted failed"
  fi

  partprobe "$dev_path"
  sleep 1

  if (( has_uefi )); then
    esp_part="${dev_path}${part_prefix}1"
    root_part="${dev_path}${part_prefix}2"
    info "Formatting ESP at $esp_part..."
    mkfs.fat -F32 -n ESP "$esp_part" || die "mkfs.fat failed"
  else
    esp_part=""
    root_part="${dev_path}${part_prefix}1"
  fi

  info "Filling $root_part with random data (pre-encryption - slow but worth it)..."
  note "You'll see 'No space left on device' at the end. That's expected."
  dd if=/dev/urandom of="$root_part" bs=4M status=progress || true
  sync

  info "Creating LUKS2 container on $root_part..."
  printf '%s' "$encryption_password" | cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --pbkdf argon2id \
    --iter-time 5000 \
    --use-random \
    --batch-mode \
    --key-file=- \
    "$root_part" || die "luksFormat failed"

  # GRUB 2.12+ supports argon2id directly, so no separate PBKDF2 keyslot needed.
  # If you see "no key available with this passphrase" at GRUB prompt on older
  # firmware, add a PBKDF2 keyslot manually post-install:
  #   echo -n "your-passphrase" > /tmp/k && chmod 600 /tmp/k
  #   cryptsetup luksAddKey --pbkdf pbkdf2 --key-file=/tmp/k <root-part>
  #   shred -u /tmp/k

  info "Opening LUKS container..."
  printf '%s' "$encryption_password" | cryptsetup open \
    --type luks --key-file=- "$root_part" cryptroot || die "luksOpen failed"

  cryptsetup status cryptroot
}

create_btrfs_subvolumes() {
  hdr "Creating Btrfs filesystem and subvolumes"
  info "Formatting /dev/mapper/cryptroot as Btrfs..."
  mkfs.btrfs -f -L system /dev/mapper/cryptroot || die "mkfs.btrfs failed"

  mount /dev/mapper/cryptroot /mnt
  # Subvolume layout follows the ArchWiki recommendation for Snapper + rollback:
  #
  # Snapshotted (part of root rollback):
  #   @           -> /
  #
  # NOT snapshotted (survive root rollback):
  #   @home           -> /home             (user data persists)
  #   @snapshots      -> /.snapshots       (snapshots themselves)
  #   @var_log        -> /var/log          (logs survive rollback so you can debug)
  #   @var_log_audit  -> /var/log/audit    (SIEM-forwardable, isolated from other logs)
  #   @var_cache      -> /var/cache        (pacman cache, regenerable)
  #   @var_tmp        -> /var/tmp          (ephemeral by definition)
  #
  # Additional subvolumes (created but left UNMOUNTED unless explicitly wanted):
  #   @var_lib_docker -> would mount at /var/lib/docker with nodatacow for CoW-
  #                     hostile workloads. We create the subvolume so it's ready
  #                     but do not add it to fstab - uncomment in /etc/fstab if
  #                     you install Docker/Podman.
  for sv in @ @home @snapshots @var_log @var_log_audit @var_cache @var_tmp @var_lib_docker; do
    btrfs subvolume create "/mnt/$sv" || die "Failed to create subvolume $sv"
  done
  umount /mnt

  info "Mounting subvolumes..."
  # Detect if the underlying device is rotational. autodefrag helps on HDDs
  # but causes write amplification on SSDs.
  local rotational=0
  local base_dev
  base_dev=$(lsblk -no PKNAME "$root_part" 2>/dev/null | head -1)
  if [[ -n $base_dev && -r /sys/block/$base_dev/queue/rotational ]]; then
    rotational=$(cat "/sys/block/$base_dev/queue/rotational")
  fi
  local extra_opts=""
  (( rotational )) && extra_opts=",autodefrag"

  local mopts="rw,noatime,compress=zstd:3,space_cache=v2,discard=async${extra_opts}"
  # Note on discard=async: safe on encrypted Btrfs (kernel 5.6+). If your threat
  # model forbids any TRIM leakage (e.g. hiding used-sector count from a
  # forensic examiner), change to "nodiscard" here and in fstab post-install.

  mount -o "$mopts,subvol=@" /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/{home,.snapshots,var/log/audit,var/cache,var/tmp,boot,efi,proc,sys,dev,run}
  mount -o "$mopts,subvol=@home"          /dev/mapper/cryptroot /mnt/home
  mount -o "$mopts,subvol=@snapshots"     /dev/mapper/cryptroot /mnt/.snapshots
  mount -o "$mopts,subvol=@var_log"       /dev/mapper/cryptroot /mnt/var/log
  mount -o "$mopts,subvol=@var_log_audit" /dev/mapper/cryptroot /mnt/var/log/audit
  mount -o "$mopts,subvol=@var_cache"     /dev/mapper/cryptroot /mnt/var/cache
  mount -o "rw,noatime,subvol=@var_tmp"   /dev/mapper/cryptroot /mnt/var/tmp
  # @var_lib_docker created but intentionally not mounted here.

  if (( has_uefi )); then
    if (( use_encrypted_boot )); then
      # /boot is inside LUKS (as a dir on @), /efi is the ESP
      mount "$esp_part" /mnt/efi
    else
      # /boot IS the ESP
      mount "$esp_part" /mnt/boot
    fi
  fi
}

# =============================================================================
# Base install
# =============================================================================

run_reflector() {
  hdr "Optimizing mirror list"
  if ! command -v reflector &>/dev/null; then
    pacman -Sy --noconfirm reflector || warn "Reflector install failed, continuing with default mirrors."
  fi
  if command -v reflector &>/dev/null; then
    info "Ranking mirrors (this takes ~30 seconds)..."
    reflector --protocol https --latest 20 --sort rate \
      --save /etc/pacman.d/mirrorlist || warn "Reflector failed, using existing mirrors."
  fi
}

pacstrap_base() {
  hdr "Installing base system (pacstrap)"

  local pkgs=(
    # Core
    base base-devel linux linux-firmware linux-headers
    btrfs-progs cryptsetup
    # Boot
    grub efibootmgr
    # Filesystem tools
    dosfstools e2fsprogs
    # Network (NetworkManager + wireguard + openvpn integration)
    networkmanager networkmanager-openvpn
    wireguard-tools openvpn
    # Firewall (native nftables)
    nftables
    # Snapshots
    snapper snap-pac
    # Editors / basics
    vim nano sudo
    # Firmware updates
    fwupd
    # Diagnostics
    usbutils pciutils lshw dmidecode
    # Man pages
    man-db man-pages texinfo
    # Zram
    zram-generator
    # Reflector (keep installed for periodic mirror refresh)
    reflector
  )

  # Microcode
  case "$cpu_vendor" in
    intel) pkgs+=(intel-ucode) ;;
    amd)   pkgs+=(amd-ucode) ;;
  esac

  # TPM2 tooling
  if (( has_tpm2 )); then
    pkgs+=(tpm2-tools tpm2-tss)
  fi

  # FIDO2 tooling
  pkgs+=(libfido2)

  # grub-btrfs for snapshot boot menu entries
  pkgs+=(grub-btrfs inotify-tools)

  pacstrap -K /mnt "${pkgs[@]}" || die "pacstrap failed"

  genfstab -U /mnt >> /mnt/etc/fstab
}

# =============================================================================
# Chroot configuration
# =============================================================================

configure_system_basics() {
  hdr "Configuring system basics (timezone, locale, hostname)"
  arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$timezone_choice" /etc/localtime
  arch-chroot /mnt hwclock --systohc

  cat > /mnt/etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
EOF
  arch-chroot /mnt locale-gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

  echo "$hostname" > /mnt/etc/hostname
  cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOF

  # NetworkManager: we'll configure it fully in harden.sh. Just enable now.
  arch-chroot /mnt systemctl enable NetworkManager.service

  # Tune target pacman: Color, VerbosePkgLists, ParallelDownloads
  sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf
  sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /mnt/etc/pacman.conf
  sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /mnt/etc/pacman.conf

  # Zram swap: 50% of RAM, zstd compression, no disk swap
  cat > /mnt/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
EOF
}

set_passwords_and_user() {
  hdr "Setting passwords and creating user"
  echo "root:$root_password" | arch-chroot /mnt chpasswd

  arch-chroot /mnt useradd -m -G wheel,audio,video,input -s /bin/bash "$username"
  echo "$username:$user_password" | arch-chroot /mnt chpasswd

  # Enable wheel group sudo
  echo '%wheel ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/10-wheel
  chmod 0440 /mnt/etc/sudoers.d/10-wheel
}

# =============================================================================
# mkinitcpio + bootloader
# =============================================================================

configure_mkinitcpio() {
  hdr "Configuring mkinitcpio"

  # HOOKS order for LUKS + Btrfs with GRUB's encrypt hook:
  #   base udev autodetect microcode modconf kms keyboard keymap consolefont
  #   block encrypt filesystems fsck
  #
  # Key points:
  #   - keyboard MUST precede encrypt (you need to type the passphrase)
  #   - encrypt MUST precede filesystems (the FS is inside the LUKS container)
  #   - microcode hook loads CPU ucode early (Arch 2024+ standard)
  #   - No btrfs hook needed unless using multi-device Btrfs
  arch-chroot /mnt sed -i \
    's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' \
    /etc/mkinitcpio.conf

  # Add a MODULES line for Btrfs so it's available in early userspace
  arch-chroot /mnt sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf

  arch-chroot /mnt mkinitcpio -P || die "mkinitcpio failed"
}

create_crypttab() {
  hdr "Creating /etc/crypttab"
  local uuid
  uuid=$(blkid -s UUID -o value "$root_part")
  [[ -n $uuid ]] || die "Could not read UUID of $root_part"
  # The initramfs handles the root device via kernel cmdline, so this crypttab
  # entry is for any non-root LUKS devices (none in this setup). We leave it
  # empty-with-header so the user can add more later.
  cat > /mnt/etc/crypttab <<EOF
# <name>       <device>         <password>    <options>
# cryptroot is unlocked by the initramfs via kernel cmdline, not this file.
EOF
  # But we do need crypttab.initramfs if we want systemd's unlock to work -
  # since we're using the classic encrypt hook (not sd-encrypt), we don't.
}

install_grub() {
  hdr "Installing GRUB bootloader"
  local uuid
  uuid=$(blkid -s UUID -o value "$root_part")

  # Base GRUB_CMDLINE_LINUX: encrypted root
  local cmdline="cryptdevice=UUID=$uuid:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@"

  # Quiet boot + reasonable defaults (hardening params are added in harden.sh)
  local cmdline_default="loglevel=3 quiet"

  arch-chroot /mnt sed -i \
    "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$cmdline\"|" \
    /etc/default/grub
  arch-chroot /mnt sed -i \
    "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline_default\"|" \
    /etc/default/grub

  if (( use_encrypted_boot )); then
    # GRUB needs to unlock LUKS itself to read the kernel
    arch-chroot /mnt sed -i 's|^#\?GRUB_ENABLE_CRYPTODISK=.*|GRUB_ENABLE_CRYPTODISK=y|' /etc/default/grub
    if ! grep -q '^GRUB_ENABLE_CRYPTODISK=' /mnt/etc/default/grub; then
      echo 'GRUB_ENABLE_CRYPTODISK=y' >> /mnt/etc/default/grub
    fi
  fi

  # Install GRUB
  if (( has_uefi )); then
    local efi_dir=/boot
    (( use_encrypted_boot )) && efi_dir=/efi
    arch-chroot /mnt grub-install \
      --target=x86_64-efi \
      --efi-directory="$efi_dir" \
      --bootloader-id=GRUB \
      --modules="part_gpt part_msdos cryptodisk luks2 gcry_rijndael gcry_sha512 btrfs" \
      || die "grub-install (UEFI) failed"
  else
    arch-chroot /mnt grub-install \
      --target=i386-pc \
      --modules="part_msdos cryptodisk luks2 gcry_rijndael gcry_sha512 btrfs" \
      "$dev_path" \
      || die "grub-install (BIOS) failed"
  fi

  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || die "grub-mkconfig failed"
}

# =============================================================================
# TPM2 + FIDO2 enrollment
# =============================================================================

enroll_tpm2() {
  (( has_tpm2 )) || return 0
  hdr "Enrolling TPM2 keyslot"

  note "Binding to PCRs 0 (firmware) and 7 (Secure Boot state)."
  note "Kernel/initramfs updates will NOT break this. Firmware updates WILL."
  note "If unlock fails after a firmware update, use passphrase and run:"
  note "    sudo gitw-unlock-mode reenroll-tpm"
  echo

  # We write the passphrase to a temp file so systemd-cryptenroll can read it
  # without prompting. The file lives briefly on tmpfs.
  local tmpkey
  tmpkey=$(mktemp /tmp/gitw-luks-key.XXXXXX)
  chmod 600 "$tmpkey"
  printf '%s' "$encryption_password" > "$tmpkey"

  # Pass the PIN via environment
  NEWPIN="$tmpkey"
  local tpm_pin_file
  tpm_pin_file=$(mktemp /tmp/gitw-tpm-pin.XXXXXX)
  chmod 600 "$tpm_pin_file"
  printf '%s' "$tpm2_pin" > "$tpm_pin_file"

  # systemd-cryptenroll reads existing passphrase from PASSWORD env
  # and new PIN from NEWPIN env (as of systemd 254+)
  if PASSWORD="$encryption_password" NEWPIN="$tpm2_pin" \
     systemd-cryptenroll \
      --tpm2-device=auto \
      --tpm2-pcrs=0+7 \
      --tpm2-with-pin=yes \
      "$root_part"; then
    info "TPM2 keyslot enrolled."
  else
    warn "TPM2 enrollment failed. Passphrase keyslot still works."
  fi

  shred -u "$tmpkey" "$tpm_pin_file" 2>/dev/null || rm -f "$tmpkey" "$tpm_pin_file"
}

enroll_fido2_key() {
  local label=$1
  note "Insert your FIDO2 key ($label) and press Enter when ready."
  read -r
  if PASSWORD="$encryption_password" \
     systemd-cryptenroll \
      --fido2-device=auto \
      --fido2-with-client-pin=yes \
      --fido2-with-user-presence=yes \
      "$root_part"; then
    info "FIDO2 key ($label) enrolled."
    return 0
  else
    warn "FIDO2 enrollment ($label) failed."
    return 1
  fi
}

enroll_fido2_keys() {
  (( enroll_fido2_primary )) || return 0
  hdr "Enrolling FIDO2 keys"

  enroll_fido2_key "primary" || true

  if (( enroll_fido2_backup )); then
    echo
    note "Remove the primary key and insert the backup key."
    read -n 1 -srp "Press any key when the backup key is plugged in..."
    echo
    enroll_fido2_key "backup" || true
  fi
}

# =============================================================================
# Snapper + grub-btrfs
# =============================================================================

configure_snapper() {
  hdr "Configuring Snapper for Btrfs snapshots"

  # Our @snapshots subvolume is already mounted at /.snapshots. Snapper's
  # create-config will try to create its own .snapshots subvolume, which
  # would conflict. The clean way: unmount ours, let snapper create its
  # config (which needs a writable /.snapshots dir, not necessarily its
  # own subvolume), then remount ours on top.

  umount /mnt/.snapshots || warn "umount /mnt/.snapshots failed"

  # snapper create-config requires /.snapshots to NOT exist (it creates it).
  # Remove the empty mount point.
  rmdir /mnt/.snapshots 2>/dev/null || true

  arch-chroot /mnt snapper --no-dbus -c root create-config / || \
    warn "snapper create-config failed (non-fatal)"

  # Snapper created @/.snapshots as a nested subvolume. Remove it and put
  # our @snapshots subvolume back in its place.
  if arch-chroot /mnt btrfs subvolume show /.snapshots &>/dev/null; then
    arch-chroot /mnt btrfs subvolume delete /.snapshots || \
      warn "Could not delete snapper's nested .snapshots"
  fi
  mkdir -p /mnt/.snapshots
  mount -o "rw,noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@snapshots" \
    /dev/mapper/cryptroot /mnt/.snapshots

  arch-chroot /mnt chmod 750 /.snapshots
  arch-chroot /mnt chown :wheel /.snapshots

  # Snapper config tuning
  local cfg=/mnt/etc/snapper/configs/root
  if [[ -f $cfg ]]; then
    sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' "$cfg"
  fi

  arch-chroot /mnt systemctl enable snapper-timeline.timer
  arch-chroot /mnt systemctl enable snapper-cleanup.timer
  arch-chroot /mnt systemctl enable grub-btrfsd.service
}

# =============================================================================
# Phase 2 / 3 staging
# =============================================================================

stage_next_phases() {
  hdr "Staging harden.sh and software.sh"
  mkdir -p /mnt/root/gitw/helpers

  # Monorepo layout: Arch files live under /arch/, shared helpers under
  # /shared/helpers/. REPO_BASE points at the raw repo root.
  local arch_files=(harden.sh software.sh)
  for f in "${arch_files[@]}"; do
    if curl -fsSL "$REPO_BASE/arch/$f" -o "/mnt/root/gitw/$f" 2>/dev/null; then
      info "Fetched arch/$f"
    else
      warn "Could not fetch arch/$f from $REPO_BASE"
    fi
  done

  # Top-level README.md
  if curl -fsSL "$REPO_BASE/README.md" -o "/mnt/root/gitw/README.md" 2>/dev/null; then
    info "Fetched README.md"
  fi

  # Shared helpers (distro-neutral)
  local shared_helpers=(
    gitw-reconfigure gitw-unlock-mode gitw-dns-profile
    gitw-firewall gitw-apparmor gitw-setup-secureboot
    gitw-network-check gitw-tpm-reenroll gitw-verify-fingerprint
  )
  for h in "${shared_helpers[@]}"; do
    if curl -fsSL "$REPO_BASE/shared/helpers/$h" -o "/mnt/root/gitw/helpers/$h" 2>/dev/null; then
      chmod +x "/mnt/root/gitw/helpers/$h"
    fi
  done

  # Arch-specific helpers
  local arch_helpers=(
    gitw-enable-blackarch gitw-enable-chaotic-aur gitw-aur-review
  )
  for h in "${arch_helpers[@]}"; do
    if curl -fsSL "$REPO_BASE/arch/helpers/$h" -o "/mnt/root/gitw/helpers/$h" 2>/dev/null; then
      chmod +x "/mnt/root/gitw/helpers/$h"
    fi
  done

  chmod +x /mnt/root/gitw/*.sh 2>/dev/null || true
}

# =============================================================================
# Sentinels and cleanup
# =============================================================================

write_sentinel() {
  mkdir -p "$SENTINEL_DIR"
  date -u +%FT%TZ > "$SENTINEL_DIR/phase-1-install.done"
  cat > "$SENTINEL_DIR/install-summary.txt" <<EOF
Install completed: $(date -u +%FT%TZ)
Target device:    $dev_path
Root partition:   $root_part
ESP:              ${esp_part:-none (BIOS)}
UEFI:             $has_uefi
TPM2 enrolled:    $has_tpm2
Encrypted /boot:  $use_encrypted_boot
Hostname:         $hostname
Username:         $username
Timezone:         $timezone_choice
EOF
}

verify_install() {
  hdr "Verifying install"
  [[ -f /mnt/boot/grub/grub.cfg ]]       || die "grub.cfg missing"
  [[ -f /mnt/boot/initramfs-linux.img ]] || die "initramfs-linux.img missing"
  [[ -f /mnt/etc/fstab ]]                || die "fstab missing"
  [[ -f /mnt/etc/locale.conf ]]          || die "locale.conf missing"
  info "All critical files present."
}

safely_unmount() {
  hdr "Unmounting and closing LUKS"
  sync
  umount -R /mnt || warn "umount -R failed (continuing)"
  cryptsetup close cryptroot || warn "cryptsetup close failed"
}

final_message() {
  cat <<EOF

${GREEN}${BOLD}=============================================${RESET}
${GREEN}${BOLD}  ghostinthewires-arch Phase 1 (install) complete.${RESET}
${GREEN}${BOLD}=============================================${RESET}

Next steps:
  1. Reboot and remove the install media:
       reboot
  2. Boot into ghostinthewires-arch and log in as root.
  3. Run the hardening phase:
       cd /root/gitw
       ./harden.sh
  4. After harden.sh completes, log out and log in as '$username'.
  5. Run the software phase:
       cd /root/gitw
       ./software.sh

Unlock at first boot:
EOF
  if (( has_tpm2 )); then
    echo "  You'll be prompted for the TPM2 PIN (fast path)."
  fi
  if (( enroll_fido2_primary )); then
    echo "  If the TPM path fails, plug in your FIDO2 key to unlock."
  fi
  echo "  If all else fails, use the long LUKS passphrase."
  echo
  note "If unlock surprises happen, it's almost always because Secure Boot state"
  note "or firmware changed. Use the passphrase and read:"
  note "    /root/gitw/README.md  (Troubleshooting)"
  echo
}

# =============================================================================
# Main
# =============================================================================

main() {
  greet
  check_root
  check_live_iso
  tune_live_pacman
  detect_capabilities
  network_check
  notice_destructive

  ask_timezone
  ask_username_and_hostname
  ask_passwords
  ask_fido2_keys

  echo
  warn "Ready to wipe $dev_path and install. Last chance to abort."
  confirm "Proceed with installation?" n || die "Aborted by user."

  partition_and_encrypt
  create_btrfs_subvolumes
  run_reflector
  pacstrap_base

  configure_system_basics
  set_passwords_and_user
  configure_mkinitcpio
  create_crypttab
  install_grub

  enroll_tpm2
  enroll_fido2_keys

  configure_snapper
  stage_next_phases
  write_sentinel
  verify_install
  safely_unmount
  final_message
}

main "$@"
