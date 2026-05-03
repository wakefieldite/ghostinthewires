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
#
# Every settings-applying action emits a verification entry to the log at
# /tmp/gitw-install.log (during this phase; copied to /mnt/var/log/ at end).
# See docs/dev/logging.md for log format and review workflow.

set -o pipefail

# =============================================================================
# Constants / globals
# =============================================================================

REPO_BASE="${GITW_REPO_BASE:-https://raw.githubusercontent.com/wakefieldite/ghostinthewires/main}"
SENTINEL_DIR="/mnt/var/lib/gitw-install"
LOG_LIB_URL="$REPO_BASE/shared/lib/gitw-log.sh"

GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Log lives on the live ISO during Phase 1, copied to target at end.
export GITW_LOG="/tmp/gitw-install.log"

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
# Console messages (separate from structured log)
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
# Bootstrap the logging library
# =============================================================================

bootstrap_log_lib() {
  # During Phase 1 we don't have the lib installed yet; fetch from the repo.
  local lib=/tmp/gitw-log.sh
  if ! curl -fsSL "$LOG_LIB_URL" -o "$lib" 2>/dev/null; then
    warn "Could not fetch logging library from $LOG_LIB_URL."
    warn "Install will proceed without structured verification logging."
    # Provide stubs so calls don't error out.
    gitw_log_init() { :; }
    gitw_log_step() { :; }
    gitw_log_info() { :; }
    gitw_log_action() { :; }
    gitw_log_warn() { :; }
    gitw_log_fail() { :; }
    gitw_log_phase_summary() { echo "(logging library unavailable)"; }
    gitw_verify_file_contains() { :; }
    gitw_verify_file_lacks() { :; }
    gitw_verify_file_mode() { :; }
    gitw_verify_symlink_target() { :; }
    gitw_verify_kernel_param() { :; }
    gitw_verify_service_enabled() { :; }
    gitw_verify_pacman_pkg() { :; }
    gitw_verify_sysctl() { :; }
    gitw_verify_luks_keyslot() { :; }
    gitw_verify_btrfs_subvolume() { :; }
    gitw_verify_mount() { :; }
    gitw_verify_user_groups() { :; }
    gitw_verify_command() { :; }
    return
  fi
  # shellcheck source=/dev/null
  source "$lib"
  gitw_log_init "install"
  info "Logging to $GITW_LOG"
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
  gitw_log_step "live_pacman" "Tuning live ISO pacman config"
  sed -i 's/^#Color/Color/' /etc/pacman.conf
  gitw_verify_file_contains "Color uncommented in live pacman.conf" \
    /etc/pacman.conf '^Color'
  sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
  gitw_verify_file_contains "VerbosePkgLists uncommented in live pacman.conf" \
    /etc/pacman.conf '^VerbosePkgLists'
  sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
  gitw_verify_file_contains "ParallelDownloads uncommented in live pacman.conf" \
    /etc/pacman.conf '^ParallelDownloads = 5'
}

detect_capabilities() {
  hdr "Detecting hardware capabilities"
  gitw_log_step "detect_capabilities" "Detecting UEFI/TPM2/Secure-Boot/CPU"

  # UEFI?
  if [[ -d /sys/firmware/efi/efivars ]]; then
    has_uefi=1
    info "UEFI firmware detected."
    gitw_log_info "UEFI=yes"
  else
    has_uefi=0
    warn "BIOS/Legacy firmware detected. Secure Boot and TPM-based unlock"
    warn "will not be available. Installation will use BIOS GRUB + passphrase."
    gitw_log_info "UEFI=no (BIOS/Legacy)"
  fi

  # TPM2?
  if [[ -c /dev/tpmrm0 || -c /dev/tpm0 ]]; then
    if command -v systemd-cryptenroll &>/dev/null; then
      if systemd-cryptenroll --tpm2-device=list 2>/dev/null | grep -q '^/dev/'; then
        has_tpm2=1
        info "TPM 2.0 detected and accessible."
        gitw_log_info "TPM2=yes"
      else
        has_tpm2=0
        warn "TPM device present but not usable as TPM 2.0."
        gitw_log_warn "TPM device present but not TPM2 capable"
      fi
    fi
  else
    has_tpm2=0
    note "No TPM device found. Unlock will rely on passphrase (+ optional FIDO2)."
    gitw_log_info "TPM2=no"
  fi

  # Secure Boot setup-mode?
  has_secureboot=0
  if (( has_uefi )) && command -v bootctl &>/dev/null; then
    if bootctl status 2>/dev/null | grep -qi 'setup-mode.*setup'; then
      has_secureboot=1
      info "Secure Boot is in Setup Mode - custom keys can be enrolled."
      gitw_log_info "SecureBoot=setup-mode"
    elif bootctl status 2>/dev/null | grep -qi 'secure boot.*enabled'; then
      note "Secure Boot is enabled with vendor keys. To use custom keys,"
      note "enter firmware setup, clear keys / enter Setup Mode, then re-run."
      gitw_log_info "SecureBoot=enabled-vendor"
    fi
  fi

  # CPU vendor (for microcode)
  if grep -qi 'GenuineIntel' /proc/cpuinfo; then
    cpu_vendor="intel"
    info "Intel CPU detected (intel-ucode)."
    gitw_log_info "CPU=intel"
  elif grep -qi 'AuthenticAMD' /proc/cpuinfo; then
    cpu_vendor="amd"
    info "AMD CPU detected (amd-ucode)."
    gitw_log_info "CPU=amd"
  else
    cpu_vendor="generic"
    warn "Unknown CPU vendor; skipping microcode."
    gitw_log_warn "Unknown CPU vendor; skipping microcode"
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
  gitw_log_step "network_check" "Verifying network connectivity"

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

  if ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
    wan_ip=$(curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || echo unknown)
    echo "    WAN IP:       $wan_ip"
    info "Internet connectivity: OK"
    gitw_log_info "Internet OK; iface=$iface lan=$lan_ip gw=$gateway wan=$wan_ip"
  else
    warn "Internet connectivity: FAILED"
    warn "The installer needs network access. Fix with iwctl (Wi-Fi) or check cable."
    gitw_log_fail "Internet connectivity failed"
    die "No internet. Cannot continue."
  fi

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
  gitw_log_step "partition" "Partitioning and creating LUKS container"
  lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINTS
  echo
  read -erp "Target device (e.g. /dev/nvme0n1 or /dev/sda): " dev_path
  [[ -b "$dev_path" ]] || die "Not a block device: $dev_path"

  if [[ "$dev_path" =~ (nvme|mmcblk|loop)[0-9]+n?[0-9]*$ ]]; then
    part_prefix="p"
  else
    part_prefix=""
  fi

  warn "About to COMPLETELY WIPE $dev_path. This cannot be undone."
  read -rp "Type the device path again to confirm: " confirm_path
  [[ "$confirm_path" == "$dev_path" ]] || die "Confirmation mismatch."

  if (( has_uefi )); then
    if confirm "Use encrypted /boot? (Recommended, protects kernel/initramfs from tampering)" y; then
      use_encrypted_boot=1
    else
      use_encrypted_boot=0
    fi
  else
    use_encrypted_boot=1
  fi

  info "Creating partition table on $dev_path..."
  if (( has_uefi )); then
    parted --script "$dev_path" \
      mklabel gpt \
      mkpart ESP fat32 1MiB 513MiB \
      set 1 esp on \
      mkpart cryptsystem 513MiB 100% \
      || die "parted failed"
  else
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
    gitw_verify_command "ESP formatted as vfat" 0 \
      bash -c "blkid -s TYPE -o value '$esp_part' | grep -q vfat"
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

  gitw_verify_command "LUKS2 container detected" 0 \
    bash -c "cryptsetup isLuks '$root_part' && cryptsetup luksDump '$root_part' | grep -q 'Version:.*2'"

  info "Opening LUKS container..."
  printf '%s' "$encryption_password" | cryptsetup open \
    --type luks --key-file=- "$root_part" cryptroot || die "luksOpen failed"

  gitw_verify_command "/dev/mapper/cryptroot exists" 0 test -b /dev/mapper/cryptroot

  cryptsetup status cryptroot
}

create_btrfs_subvolumes() {
  hdr "Creating Btrfs filesystem and subvolumes"
  gitw_log_step "btrfs" "Creating Btrfs and subvolumes"
  info "Formatting /dev/mapper/cryptroot as Btrfs..."
  mkfs.btrfs -f -L system /dev/mapper/cryptroot || die "mkfs.btrfs failed"
  gitw_verify_command "cryptroot formatted as btrfs" 0 \
    bash -c "blkid -s TYPE -o value /dev/mapper/cryptroot | grep -q btrfs"

  mount /dev/mapper/cryptroot /mnt
  for sv in @ @home @snapshots @var_log @var_log_audit @var_cache @var_tmp @var_lib_docker; do
    btrfs subvolume create "/mnt/$sv" || die "Failed to create subvolume $sv"
    gitw_verify_btrfs_subvolume "subvolume $sv created" "/mnt/$sv"
  done
  umount /mnt

  info "Mounting subvolumes..."
  local rotational=0
  local base_dev
  base_dev=$(lsblk -no PKNAME "$root_part" 2>/dev/null | head -1)
  if [[ -n $base_dev && -r /sys/block/$base_dev/queue/rotational ]]; then
    rotational=$(cat "/sys/block/$base_dev/queue/rotational")
  fi
  local extra_opts=""
  (( rotational )) && extra_opts=",autodefrag"
  gitw_log_info "rotational=$rotational extra_mount_opts='$extra_opts'"

  local mopts="rw,noatime,compress=zstd:3,space_cache=v2,discard=async${extra_opts}"

  mount -o "$mopts,subvol=@" /dev/mapper/cryptroot /mnt
  gitw_verify_mount "@ mounted at /mnt" /mnt btrfs
  mkdir -p /mnt/{home,.snapshots,var/log/audit,var/cache,var/tmp,boot,efi,proc,sys,dev,run}
  mount -o "$mopts,subvol=@home"          /dev/mapper/cryptroot /mnt/home
  gitw_verify_mount "@home mounted" /mnt/home btrfs
  mount -o "$mopts,subvol=@snapshots"     /dev/mapper/cryptroot /mnt/.snapshots
  gitw_verify_mount "@snapshots mounted" /mnt/.snapshots btrfs
  mount -o "$mopts,subvol=@var_log"       /dev/mapper/cryptroot /mnt/var/log
  gitw_verify_mount "@var_log mounted" /mnt/var/log btrfs
  mount -o "$mopts,subvol=@var_log_audit" /dev/mapper/cryptroot /mnt/var/log/audit
  gitw_verify_mount "@var_log_audit mounted" /mnt/var/log/audit btrfs
  mount -o "$mopts,subvol=@var_cache"     /dev/mapper/cryptroot /mnt/var/cache
  gitw_verify_mount "@var_cache mounted" /mnt/var/cache btrfs
  mount -o "rw,noatime,subvol=@var_tmp"   /dev/mapper/cryptroot /mnt/var/tmp
  gitw_verify_mount "@var_tmp mounted" /mnt/var/tmp btrfs

  if (( has_uefi )); then
    if (( use_encrypted_boot )); then
      mount "$esp_part" /mnt/efi
      gitw_verify_mount "ESP mounted at /efi (encrypted /boot mode)" /mnt/efi vfat
    else
      mount "$esp_part" /mnt/boot
      gitw_verify_mount "ESP mounted at /boot" /mnt/boot vfat
    fi
  fi
}

# =============================================================================
# Base install
# =============================================================================

run_reflector() {
  hdr "Optimizing mirror list"
  gitw_log_step "reflector" "Refreshing pacman mirror list"
  if ! command -v reflector &>/dev/null; then
    pacman -Sy --noconfirm reflector || warn "Reflector install failed, continuing with default mirrors."
  fi
  if command -v reflector &>/dev/null; then
    info "Ranking mirrors (this takes ~30 seconds)..."
    if reflector --protocol https --latest 20 --sort rate \
        --save /etc/pacman.d/mirrorlist; then
      gitw_verify_file_contains "mirror list refreshed" \
        /etc/pacman.d/mirrorlist '^Server = https'
    else
      gitw_log_warn "Reflector failed; using existing mirrors"
    fi
  fi
}

pacstrap_base() {
  hdr "Installing base system (pacstrap)"
  gitw_log_step "pacstrap" "Installing base packages to /mnt"

  local pkgs=(
    base base-devel linux linux-firmware linux-headers
    btrfs-progs cryptsetup
    grub efibootmgr
    dosfstools e2fsprogs
    networkmanager networkmanager-openvpn
    wireguard-tools openvpn
    nftables
    snapper snap-pac
    vim nano sudo
    fwupd
    usbutils pciutils lshw dmidecode
    man-db man-pages texinfo
    zram-generator
    reflector
  )

  case "$cpu_vendor" in
    intel) pkgs+=(intel-ucode) ;;
    amd)   pkgs+=(amd-ucode) ;;
  esac

  if (( has_tpm2 )); then
    pkgs+=(tpm2-tools tpm2-tss)
  fi

  pkgs+=(libfido2)
  pkgs+=(grub-btrfs inotify-tools)

  pacstrap -K /mnt "${pkgs[@]}" || die "pacstrap failed"

  # Verify a representative sample of packages installed correctly
  for p in base linux cryptsetup btrfs-progs grub networkmanager nftables snapper; do
    gitw_verify_pacman_pkg "package $p installed" "$p" /mnt
  done
  case "$cpu_vendor" in
    intel) gitw_verify_pacman_pkg "intel-ucode installed" intel-ucode /mnt ;;
    amd)   gitw_verify_pacman_pkg "amd-ucode installed"   amd-ucode   /mnt ;;
  esac
  if (( has_tpm2 )); then
    gitw_verify_pacman_pkg "tpm2-tools installed" tpm2-tools /mnt
  fi

  genfstab -U /mnt >> /mnt/etc/fstab
  gitw_verify_file_contains "fstab populated with cryptroot mount" \
    /mnt/etc/fstab 'subvol=/@'
}

# =============================================================================
# Chroot configuration
# =============================================================================

configure_system_basics() {
  hdr "Configuring system basics (timezone, locale, hostname)"
  gitw_log_step "system_basics" "Setting timezone, locale, hostname, NM"

  arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$timezone_choice" /etc/localtime
  gitw_verify_symlink_target "timezone symlink set" \
    "/mnt/etc/localtime" "/usr/share/zoneinfo/$timezone_choice"
  arch-chroot /mnt hwclock --systohc

  cat > /mnt/etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
EOF
  arch-chroot /mnt locale-gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
  gitw_verify_file_contains "locale.conf set to en_US.UTF-8" \
    /mnt/etc/locale.conf 'LANG=en_US\.UTF-8'

  echo "$hostname" > /mnt/etc/hostname
  gitw_verify_file_contains "hostname written" /mnt/etc/hostname "^${hostname}\$"
  cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOF
  gitw_verify_file_contains "hosts contains hostname mapping" \
    /mnt/etc/hosts "127.0.1.1.*${hostname}"

  arch-chroot /mnt systemctl enable NetworkManager.service
  gitw_verify_service_enabled "NetworkManager enabled" NetworkManager.service /mnt

  sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf
  gitw_verify_file_contains "target pacman Color enabled" \
    /mnt/etc/pacman.conf '^Color'
  sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /mnt/etc/pacman.conf
  gitw_verify_file_contains "target pacman VerbosePkgLists enabled" \
    /mnt/etc/pacman.conf '^VerbosePkgLists'
  sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /mnt/etc/pacman.conf
  gitw_verify_file_contains "target pacman ParallelDownloads enabled" \
    /mnt/etc/pacman.conf '^ParallelDownloads = 5'

  cat > /mnt/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
EOF
  gitw_verify_file_contains "zram-generator config written" \
    /mnt/etc/systemd/zram-generator.conf 'zram-size'
}

set_passwords_and_user() {
  hdr "Setting passwords and creating user"
  gitw_log_step "user_setup" "Creating user and setting passwords"

  echo "root:$root_password" | arch-chroot /mnt chpasswd

  arch-chroot /mnt useradd -m -G wheel,audio,video,input -s /bin/bash "$username"
  echo "$username:$user_password" | arch-chroot /mnt chpasswd

  gitw_verify_user_groups "user created with expected groups" \
    "$username" "wheel,audio,video,input" /mnt

  echo '%wheel ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/10-wheel
  chmod 0440 /mnt/etc/sudoers.d/10-wheel
  gitw_verify_file_contains "wheel group sudo enabled" \
    /mnt/etc/sudoers.d/10-wheel '%wheel ALL'
  gitw_verify_file_mode "sudoers fragment mode 0440" \
    /mnt/etc/sudoers.d/10-wheel "0440"
}

# =============================================================================
# mkinitcpio + bootloader
# =============================================================================

configure_mkinitcpio() {
  hdr "Configuring mkinitcpio"
  gitw_log_step "mkinitcpio" "Setting HOOKS and MODULES, generating initramfs"

  arch-chroot /mnt sed -i \
    's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' \
    /etc/mkinitcpio.conf
  gitw_verify_file_contains "HOOKS line includes encrypt before filesystems" \
    /mnt/etc/mkinitcpio.conf 'HOOKS=.*encrypt.*filesystems'
  gitw_verify_file_contains "HOOKS line has keyboard before encrypt" \
    /mnt/etc/mkinitcpio.conf 'HOOKS=.*keyboard.*encrypt'

  arch-chroot /mnt sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
  gitw_verify_file_contains "MODULES line set to btrfs" \
    /mnt/etc/mkinitcpio.conf 'MODULES=\(btrfs\)'

  arch-chroot /mnt mkinitcpio -P || die "mkinitcpio failed"
  gitw_verify_command "initramfs file present" 0 \
    test -f /mnt/boot/initramfs-linux.img
}

create_crypttab() {
  hdr "Creating /etc/crypttab"
  gitw_log_step "crypttab" "Writing /etc/crypttab header"
  local uuid
  uuid=$(blkid -s UUID -o value "$root_part")
  [[ -n $uuid ]] || die "Could not read UUID of $root_part"
  cat > /mnt/etc/crypttab <<EOF
# <name>       <device>         <password>    <options>
# cryptroot is unlocked by the initramfs via kernel cmdline, not this file.
EOF
  gitw_verify_file_contains "crypttab placeholder written" \
    /mnt/etc/crypttab '^# <name>'
}

install_grub() {
  hdr "Installing GRUB bootloader"
  gitw_log_step "grub" "Installing and configuring GRUB"
  local uuid
  uuid=$(blkid -s UUID -o value "$root_part")

  local cmdline="cryptdevice=UUID=$uuid:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@"
  local cmdline_default="loglevel=3 quiet"

  arch-chroot /mnt sed -i \
    "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$cmdline\"|" \
    /etc/default/grub
  gitw_verify_file_contains "GRUB_CMDLINE_LINUX has cryptdevice param" \
    /mnt/etc/default/grub "GRUB_CMDLINE_LINUX=.*cryptdevice=UUID="

  arch-chroot /mnt sed -i \
    "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline_default\"|" \
    /etc/default/grub
  gitw_verify_file_contains "GRUB_CMDLINE_LINUX_DEFAULT set" \
    /mnt/etc/default/grub 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"'

  if (( use_encrypted_boot )); then
    arch-chroot /mnt sed -i 's|^#\?GRUB_ENABLE_CRYPTODISK=.*|GRUB_ENABLE_CRYPTODISK=y|' /etc/default/grub
    if ! grep -q '^GRUB_ENABLE_CRYPTODISK=' /mnt/etc/default/grub; then
      echo 'GRUB_ENABLE_CRYPTODISK=y' >> /mnt/etc/default/grub
    fi
    gitw_verify_file_contains "GRUB_ENABLE_CRYPTODISK=y set" \
      /mnt/etc/default/grub '^GRUB_ENABLE_CRYPTODISK=y'
  fi

  if (( has_uefi )); then
    local efi_dir=/boot
    (( use_encrypted_boot )) && efi_dir=/efi
    arch-chroot /mnt grub-install \
      --target=x86_64-efi \
      --efi-directory="$efi_dir" \
      --bootloader-id=GRUB \
      --modules="part_gpt part_msdos cryptodisk luks2 gcry_rijndael gcry_sha512 btrfs" \
      || die "grub-install (UEFI) failed"
    gitw_verify_command "GRUB EFI binary present" 0 \
      test -f "/mnt${efi_dir}/EFI/GRUB/grubx64.efi"
  else
    arch-chroot /mnt grub-install \
      --target=i386-pc \
      --modules="part_msdos cryptodisk luks2 gcry_rijndael gcry_sha512 btrfs" \
      "$dev_path" \
      || die "grub-install (BIOS) failed"
  fi

  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || die "grub-mkconfig failed"
  gitw_verify_command "grub.cfg generated" 0 test -f /mnt/boot/grub/grub.cfg
  gitw_verify_file_contains "grub.cfg references cryptdevice" \
    /mnt/boot/grub/grub.cfg "cryptdevice=UUID="
}

# =============================================================================
# TPM2 + FIDO2 enrollment
# =============================================================================

enroll_tpm2() {
  (( has_tpm2 )) || return 0
  hdr "Enrolling TPM2 keyslot"
  gitw_log_step "tpm2_enroll" "Enrolling TPM2+PIN keyslot"

  note "Binding to PCRs 0 (firmware) and 7 (Secure Boot state)."
  note "Kernel/initramfs updates will NOT break this. Firmware updates WILL."
  note "If unlock fails after a firmware update, use passphrase and run:"
  note "    sudo gitw-unlock-mode reenroll-tpm"
  echo

  if PASSWORD="$encryption_password" NEWPIN="$tpm2_pin" \
     systemd-cryptenroll \
      --tpm2-device=auto \
      --tpm2-pcrs=0+7 \
      --tpm2-with-pin=yes \
      "$root_part"; then
    info "TPM2 keyslot enrolled."
    gitw_verify_command "TPM2 token present in luksDump" 0 \
      bash -c "cryptsetup luksDump '$root_part' | grep -q 'systemd-tpm2'"
  else
    warn "TPM2 enrollment failed. Passphrase keyslot still works."
    gitw_log_fail "TPM2 enrollment via systemd-cryptenroll returned non-zero"
  fi
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
  gitw_log_step "fido2_enroll" "Enrolling FIDO2 key(s)"

  if enroll_fido2_key "primary"; then
    gitw_verify_command "FIDO2 token present in luksDump (after primary)" 0 \
      bash -c "cryptsetup luksDump '$root_part' | grep -q 'systemd-fido2'"
  fi

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
  gitw_log_step "snapper" "Configuring Snapper + grub-btrfs"

  umount /mnt/.snapshots || warn "umount /mnt/.snapshots failed"
  rmdir /mnt/.snapshots 2>/dev/null || true

  arch-chroot /mnt snapper --no-dbus -c root create-config / || \
    warn "snapper create-config failed (non-fatal)"

  if arch-chroot /mnt btrfs subvolume show /.snapshots &>/dev/null; then
    arch-chroot /mnt btrfs subvolume delete /.snapshots || \
      warn "Could not delete snapper's nested .snapshots"
  fi
  mkdir -p /mnt/.snapshots
  mount -o "rw,noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@snapshots" \
    /dev/mapper/cryptroot /mnt/.snapshots
  gitw_verify_mount "@snapshots remounted at /mnt/.snapshots" /mnt/.snapshots btrfs

  arch-chroot /mnt chmod 750 /.snapshots
  arch-chroot /mnt chown :wheel /.snapshots

  local cfg=/mnt/etc/snapper/configs/root
  if [[ -f $cfg ]]; then
    sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' "$cfg"
    sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' "$cfg"
    gitw_verify_file_contains "snapper TIMELINE_CREATE=yes" \
      "$cfg" '^TIMELINE_CREATE="yes"'
    gitw_verify_file_contains "snapper TIMELINE_LIMIT_HOURLY=5" \
      "$cfg" '^TIMELINE_LIMIT_HOURLY="5"'
  else
    gitw_log_fail "snapper config /etc/snapper/configs/root not created"
  fi

  arch-chroot /mnt systemctl enable snapper-timeline.timer
  gitw_verify_service_enabled "snapper-timeline.timer enabled" \
    snapper-timeline.timer /mnt
  arch-chroot /mnt systemctl enable snapper-cleanup.timer
  gitw_verify_service_enabled "snapper-cleanup.timer enabled" \
    snapper-cleanup.timer /mnt
  arch-chroot /mnt systemctl enable grub-btrfsd.service
  gitw_verify_service_enabled "grub-btrfsd.service enabled" \
    grub-btrfsd.service /mnt
}

# =============================================================================
# Phase 2 / 3 staging
# =============================================================================

stage_next_phases() {
  hdr "Staging harden.sh and software.sh"
  gitw_log_step "stage_next" "Fetching phase 2/3 scripts and helpers"
  mkdir -p /mnt/root/gitw/helpers /mnt/usr/local/lib/gitw

  # Stage the logging library to a stable system path so harden.sh and
  # software.sh can source it without re-fetching.
  if curl -fsSL "$REPO_BASE/shared/lib/gitw-log.sh" -o /mnt/usr/local/lib/gitw/gitw-log.sh 2>/dev/null; then
    chmod 0644 /mnt/usr/local/lib/gitw/gitw-log.sh
    gitw_verify_file_contains "logging library staged" \
      /mnt/usr/local/lib/gitw/gitw-log.sh '_GITW_LOG_LOADED'
  else
    gitw_log_fail "Could not fetch logging library"
  fi

  local arch_files=(harden.sh software.sh)
  for f in "${arch_files[@]}"; do
    if curl -fsSL "$REPO_BASE/arch/$f" -o "/mnt/root/gitw/$f" 2>/dev/null; then
      info "Fetched arch/$f"
      gitw_verify_command "$f staged at /root/gitw" 0 \
        test -s "/mnt/root/gitw/$f"
    else
      gitw_log_fail "Could not fetch arch/$f from $REPO_BASE"
    fi
  done

  if curl -fsSL "$REPO_BASE/README.md" -o "/mnt/root/gitw/README.md" 2>/dev/null; then
    info "Fetched README.md"
  fi

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
  gitw_log_step "sentinel" "Writing phase-1 sentinel"
  mkdir -p "$SENTINEL_DIR"
  date -u +%FT%TZ > "$SENTINEL_DIR/phase-1-install.done"
  gitw_verify_command "phase-1 sentinel exists" 0 \
    test -s "$SENTINEL_DIR/phase-1-install.done"
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
  gitw_log_step "verify_install" "Final critical-file checks"
  gitw_verify_command "grub.cfg present" 0 test -f /mnt/boot/grub/grub.cfg
  gitw_verify_command "initramfs present" 0 test -f /mnt/boot/initramfs-linux.img
  gitw_verify_command "fstab present"     0 test -f /mnt/etc/fstab
  gitw_verify_command "locale.conf present" 0 test -f /mnt/etc/locale.conf
}

copy_log_to_target() {
  # Copy the phase-1 log to the target so phase-2/3 can append to it.
  mkdir -p /mnt/var/log
  if [[ -f $GITW_LOG ]]; then
    cp "$GITW_LOG" /mnt/var/log/gitw-install.log
    chmod 0600 /mnt/var/log/gitw-install.log
  fi
}

safely_unmount() {
  hdr "Unmounting and closing LUKS"
  copy_log_to_target
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
  note "Validation log copied to /var/log/gitw-install.log on the target."
  note "Review with:  awk -F'\\t' '\$7 != \"ok\" && \$7 != \"info\"' /var/log/gitw-install.log"
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
  bootstrap_log_lib
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

  gitw_log_phase_summary

  safely_unmount
  final_message
}

main "$@"
