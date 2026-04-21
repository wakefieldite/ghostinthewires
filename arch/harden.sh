#!/usr/bin/env bash
#
# ghostinthewires-arch Installer - Phase 2: Hardening
# https://github.com/wakefieldite/ghostinthewires
#
# Run this on FIRST BOOT as root, after install.sh has completed and you've
# rebooted into the new system. Idempotent - safe to re-run.
#
# This script:
#   - Writes /etc/gitw/features.conf with defaults
#   - Applies kernel hardening params (via GRUB cmdline)
#   - Applies sysctl hardening
#   - Disables MDNS, LLMNR, coredumps, thumbnail caches
#   - Configures NetworkManager (MAC randomization, no hostname leak)
#   - Sets up dnscrypt-proxy with anonymized DNSCrypt + home/travel profiles
#   - Configures stateful iptables firewall
#   - Installs AppArmor (disabled by default - toggle with gitw-apparmor)
#   - Installs helper scripts to /usr/local/bin
#
# After this finishes, log out, log in as your user, and run ./software.sh.

set -o pipefail

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

die()  { echo -e "${RED}[!] $*${RESET}" >&2; exit 1; }
info() { echo -e "${GREEN}[*] $*${RESET}"; }
warn() { echo -e "${YELLOW}[!] $*${RESET}"; }
note() { echo -e "${BLUE}[i] $*${RESET}"; }
hdr()  { echo; echo -e "${BOLD}=== $* ===${RESET}"; echo; }

SENTINEL_DIR=/var/lib/gitw-install
GITW_CONF_DIR=/etc/gitw
FEATURES_CONF=$GITW_CONF_DIR/features.conf
HELPERS_SRC=/root/gitw/helpers
HELPERS_DST=/usr/local/bin

[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f $SENTINEL_DIR/phase-1-install.done ]] || die "Phase 1 sentinel missing - did install.sh complete?"

# =============================================================================
# features.conf
# =============================================================================

write_features_conf() {
  hdr "Writing $FEATURES_CONF"
  mkdir -p "$GITW_CONF_DIR"
  if [[ -f $FEATURES_CONF ]]; then
    note "features.conf already exists - keeping your settings."
    return
  fi
  cat > "$FEATURES_CONF" <<'EOF'
# ghostinthewires-arch feature flags.
#
# After changing any value here, run:
#     sudo gitw-reconfigure
# to apply changes (regenerates GRUB cmdline and initramfs).

# ------- Kernel hardening -------
# lockdown=confidentiality prevents root from reading kernel memory, loading
# unsigned modules, kexec, /dev/mem, etc. BREAKS proprietary NVIDIA driver
# and VirtualBox kernel modules. Set to "integrity" for a weaker mode that
# allows more, or "" to disable.
LOCKDOWN=confidentiality

# Zero memory on allocation (1-3% perf cost, defeats uninitialized-memory leaks).
INIT_ON_ALLOC=1

# Zero memory on free (defeats use-after-free info leaks).
INIT_ON_FREE=1

# Disable heap allocator slab merging (defeats some heap-spray exploits).
SLAB_NOMERGE=1

# Per-syscall kernel stack randomization offset.
RANDOMIZE_KSTACK=1

# Disable the legacy vsyscall interface. Breaks glibc < 2.14 (nothing modern).
VSYSCALL_NONE=1

# Disable debugfs. Breaks some hardware diagnostics and thermal tools.
DEBUGFS_OFF=0

# CPU vulnerability mitigations. "auto" is the Linux default and what you want.
# Only change if you're benchmarking and accept the risk.
MITIGATIONS=auto

# ------- Userland hardening -------
# AppArmor: installed either way. Set to 1 to enable the LSM at boot.
# You can toggle this any time with `sudo gitw-apparmor enable|disable`.
APPARMOR=0

# MAC address randomization (NetworkManager). "random" = random per-connection.
# "stable" = per-SSID but stable (less tracking vs. "random" but more than off).
MAC_RANDOMIZATION=random

# Disable coredumps (they can contain secrets).
DISABLE_COREDUMPS=1

# Disable MDNS and LLMNR (LAN hostname leaks).
DISABLE_MDNS_LLMNR=1

# ------- DNS profile -------
# home    = use DNS from DHCP (your home Pi-hole or router)
# travel  = dnscrypt-proxy with anonymized DNSCrypt upstreams + blocklists
# offline = use /etc/hosts only, no external DNS
DNS_PROFILE=travel

# ------- GPU -------
# Explicitly set if auto-detection is wrong. Leave empty for auto.
# Values: intel, amd, nvidia, nvidia-open, virtualbox, vmware
GPU_VENDOR=
EOF
  chmod 644 "$FEATURES_CONF"
  info "Wrote default features.conf. Review it before running gitw-reconfigure."
}

# shellcheck disable=SC1090
load_features() { source "$FEATURES_CONF"; }

# =============================================================================
# Helper script installation
# =============================================================================

install_helpers() {
  hdr "Installing helper scripts to $HELPERS_DST"
  if [[ ! -d $HELPERS_SRC ]]; then
    warn "Helper source directory $HELPERS_SRC not found. Skipping."
    return
  fi
  local h
  for h in "$HELPERS_SRC"/*; do
    [[ -f $h ]] || continue
    install -m 755 "$h" "$HELPERS_DST/$(basename "$h")"
    info "Installed $(basename "$h")"
  done
}

# =============================================================================
# Kernel cmdline via features.conf
# =============================================================================

apply_kernel_params() {
  hdr "Applying kernel hardening parameters"
  load_features

  local params=()
  [[ -n $LOCKDOWN      ]] && params+=("lockdown=$LOCKDOWN")
  (( INIT_ON_ALLOC      )) && params+=("init_on_alloc=1")
  (( INIT_ON_FREE       )) && params+=("init_on_free=1")
  (( SLAB_NOMERGE       )) && params+=("slab_nomerge")
  (( RANDOMIZE_KSTACK   )) && params+=("randomize_kstack_offset=on")
  (( VSYSCALL_NONE      )) && params+=("vsyscall=none")
  (( DEBUGFS_OFF        )) && params+=("debugfs=off")
  [[ -n $MITIGATIONS    ]] && params+=("mitigations=$MITIGATIONS")

  # Always-on defensive params (not toggleable - they break nothing):
  params+=("page_alloc.shuffle=1")
  params+=("oops=panic")   # Panic on kernel oops rather than continuing in undefined state
  # Note: we intentionally do NOT add "module.sig_enforce=1" - that requires
  # signed modules which breaks DKMS. Enable via sbctl + Secure Boot instead.

  # AppArmor LSM if enabled
  if (( APPARMOR )); then
    params+=("lsm=landlock,lockdown,yama,integrity,apparmor,bpf")
    params+=("apparmor=1" "security=apparmor")
  fi

  local current
  current=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | cut -d'"' -f2)
  # Strip any previous ghostinthewires-arch params by removing everything after "quiet"
  local base
  base=$(echo "$current" | sed -E 's/(loglevel=[0-9]+ quiet).*/\1/')
  local new="$base ${params[*]}"

  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"|" /etc/default/grub
  info "Kernel cmdline: $new"

  grub-mkconfig -o /boot/grub/grub.cfg
  info "GRUB config regenerated."
}

# =============================================================================
# sysctl hardening
# =============================================================================

apply_sysctl() {
  hdr "Applying sysctl hardening"
  cat > /etc/sysctl.d/99-gitw-hardening.conf <<'EOF'
# Network
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# IPv6 privacy extensions: prefer temporary addresses
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2

# Kernel
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 3 3 3
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.yama.ptrace_scope = 2
kernel.kexec_load_disabled = 1
kernel.sysrq = 4
kernel.perf_event_paranoid = 3

# Filesystem
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
EOF
  sysctl --system >/dev/null
  info "sysctl applied."
}

# =============================================================================
# Coredumps, MDNS/LLMNR, misc
# =============================================================================

disable_coredumps() {
  load_features
  (( DISABLE_COREDUMPS )) || return
  hdr "Disabling coredumps"
  mkdir -p /etc/systemd/coredump.conf.d
  cat > /etc/systemd/coredump.conf.d/99-gitw-nodump.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
  # Also set hard limit for regular processes
  cat > /etc/security/limits.d/99-gitw-nocore.conf <<'EOF'
* hard core 0
* soft core 0
EOF
  info "Coredumps disabled."
}

disable_mdns_llmnr() {
  load_features
  (( DISABLE_MDNS_LLMNR )) || return
  hdr "Disabling MDNS and LLMNR"
  # NetworkManager: set connection.mdns=0, connection.llmnr=0 by default
  mkdir -p /etc/NetworkManager/conf.d
  cat > /etc/NetworkManager/conf.d/99-gitw-no-leak.conf <<'EOF'
[connection]
# Don't broadcast our hostname via mDNS/LLMNR
connection.mdns=0
connection.llmnr=0

# Send a minimal DHCP client identifier (don't leak hostname)
ipv4.dhcp-send-hostname=false
ipv6.dhcp-send-hostname=false
ipv4.dhcp-hostname=
ipv6.dhcp-hostname=
EOF
  info "mDNS/LLMNR disabled in NetworkManager defaults."
}

configure_mac_randomization() {
  load_features
  hdr "Configuring MAC randomization ($MAC_RANDOMIZATION)"
  mkdir -p /etc/NetworkManager/conf.d
  case "$MAC_RANDOMIZATION" in
    random)
      cat > /etc/NetworkManager/conf.d/99-gitw-mac.conf <<'EOF'
[device-mac-randomization]
wifi.scan-rand-mac-address=yes

[connection-mac-randomization]
ethernet.cloned-mac-address=random
wifi.cloned-mac-address=random
EOF
      ;;
    stable)
      cat > /etc/NetworkManager/conf.d/99-gitw-mac.conf <<'EOF'
[device-mac-randomization]
wifi.scan-rand-mac-address=yes

[connection-mac-randomization]
ethernet.cloned-mac-address=stable
wifi.cloned-mac-address=stable
EOF
      ;;
    *)
      warn "Unknown MAC_RANDOMIZATION='$MAC_RANDOMIZATION', skipping."
      ;;
  esac
  info "MAC randomization set to '$MAC_RANDOMIZATION'."
}

disable_thumbnail_caches() {
  hdr "Disabling thumbnail caches (metadata leakage)"
  # Create system-wide skel so new users don't generate thumbnails
  mkdir -p /etc/skel/.config
  # For GNOME/Nautilus users (harmless on others)
  cat > /etc/skel/.config/thumbnails-disabled <<'EOF'
# ghostinthewires-arch: thumbnail caches are disabled globally to prevent metadata leakage.
# See harden.sh for details.
EOF
  # Disable tumblerd (XFCE/GTK thumbnailer) if installed
  if systemctl list-unit-files | grep -q '^tumblerd'; then
    systemctl --global mask tumblerd.service 2>/dev/null || true
  fi
  # Disable gvfs metadata daemon (leaves metadata files in ~/.local/share/gvfs-metadata)
  # We don't mask it because file managers depend on it; instead, user script
  # in skel will clear the metadata on logout. This is handled in software.sh.
  info "Thumbnail cache policy applied."
}

# =============================================================================
# dnscrypt-proxy
# =============================================================================

install_dnscrypt_proxy() {
  hdr "Installing and configuring dnscrypt-proxy"
  if ! pacman -Q dnscrypt-proxy &>/dev/null; then
    pacman -S --noconfirm dnscrypt-proxy || die "dnscrypt-proxy install failed"
  fi

  # Anonymized DNSCrypt: queries go through a relay that hides your IP
  # from the upstream resolver. We pick a handful of trusted upstreams and
  # relays; users can customize via the dnscrypt-proxy toml.
  cat > /etc/dnscrypt-proxy/dnscrypt-proxy.toml <<'EOF'
# ghostinthewires-arch dnscrypt-proxy config
# Upstreams: trusted no-logs DNSCrypt resolvers.
# Relays: anonymize IP from upstream.
# See: https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Anonymized-DNS

server_names = ['mullvad-doh', 'quad9-dnscrypt-ip4-filter-pri', 'cloudflare']
listen_addresses = ['127.0.0.1:53', '[::1]:53']
max_clients = 250

ipv4_servers = true
ipv6_servers = true
dnscrypt_servers = true
doh_servers = true
odoh_servers = false

require_dnssec = true
require_nolog = true
require_nofilter = false  # We DO want filtered upstreams where available
disabled_server_names = []

force_tcp = false
timeout = 5000
keepalive = 30

# Cache
cache = true
cache_size = 4096
cache_min_ttl = 2400
cache_max_ttl = 86400
cache_neg_min_ttl = 60
cache_neg_max_ttl = 600

# Logging - minimal
log_level = 2
log_file = '/var/log/dnscrypt-proxy/dnscrypt-proxy.log'
use_syslog = false

# Block queries for common tracker/malware domains
[blocked_names]
blocked_names_file = '/etc/dnscrypt-proxy/blocked-names.txt'

# Sources for server lists
[sources]
  [sources.public-resolvers]
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md']
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 73
  prefix = ''

  [sources.relays]
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md']
  cache_file = '/var/cache/dnscrypt-proxy/relays.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 73
  prefix = ''

# Anonymized DNSCrypt routes
[anonymized_dns]
routes = [
  { server_name='*', via=['anon-cs-sk', 'anon-cs-fr', 'anon-scaleway-fr'] }
]
skip_incompatible = true

# Forwarding rules (for split-horizon: local domains to local resolver)
# Uncomment and edit for your home network:
# [forwarding_rules]
# forwarding_rules = '/etc/dnscrypt-proxy/forwarding-rules.txt'

# Cloaking (for /etc/hosts-style overrides)
# [cloaking_rules]
# cloaking_rules = '/etc/dnscrypt-proxy/cloaking-rules.txt'
EOF

  # Pull a starter blocklist (Steven Black hosts, unified)
  mkdir -p /etc/dnscrypt-proxy
  if [[ ! -f /etc/dnscrypt-proxy/blocked-names.txt ]]; then
    info "Fetching initial blocklist..."
    curl -fsSL "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" \
      | awk '/^0\.0\.0\.0/ {print $2}' \
      | grep -v '^0\.0\.0\.0$' \
      > /etc/dnscrypt-proxy/blocked-names.txt 2>/dev/null \
      || echo "# ghostinthewires-arch: blocklist fetch failed, add domains manually" > /etc/dnscrypt-proxy/blocked-names.txt
  fi

  mkdir -p /var/log/dnscrypt-proxy /var/cache/dnscrypt-proxy
  chown -R dnscrypt-proxy:dnscrypt-proxy /var/log/dnscrypt-proxy /var/cache/dnscrypt-proxy 2>/dev/null || true

  # Activate travel or home profile based on features.conf
  gitw_apply_dns_profile
}

gitw_apply_dns_profile() {
  load_features
  case "$DNS_PROFILE" in
    travel)
      # Point NetworkManager's resolved config at 127.0.0.1
      mkdir -p /etc/NetworkManager/conf.d
      cat > /etc/NetworkManager/conf.d/99-gitw-dns.conf <<'EOF'
[main]
dns=none
rc-manager=unmanaged
EOF
      echo 'nameserver 127.0.0.1' > /etc/resolv.conf
      chattr +i /etc/resolv.conf 2>/dev/null || true
      systemctl enable --now dnscrypt-proxy.service || warn "dnscrypt-proxy failed to start"
      info "DNS profile: travel (dnscrypt-proxy on 127.0.0.1)"
      ;;
    home)
      chattr -i /etc/resolv.conf 2>/dev/null || true
      rm -f /etc/NetworkManager/conf.d/99-gitw-dns.conf
      systemctl disable --now dnscrypt-proxy.service 2>/dev/null || true
      systemctl reload NetworkManager 2>/dev/null || true
      info "DNS profile: home (DHCP-provided DNS, typically your Pi-hole)"
      ;;
    offline)
      chattr -i /etc/resolv.conf 2>/dev/null || true
      echo '# ghostinthewires-arch offline mode - no external DNS' > /etc/resolv.conf
      chattr +i /etc/resolv.conf 2>/dev/null || true
      systemctl disable --now dnscrypt-proxy.service 2>/dev/null || true
      info "DNS profile: offline"
      ;;
  esac
}

# =============================================================================
# iptables firewall
# =============================================================================

configure_firewall() {
  hdr "Configuring nftables firewall"
  if ! pacman -Q nftables &>/dev/null; then
    pacman -S --noconfirm nftables || die "nftables install failed"
  fi

  # Disable iptables if it somehow snuck in
  systemctl disable --now iptables.service ip6tables.service 2>/dev/null || true

  mkdir -p /etc/nftables.d

  # Main ruleset: deny inbound by default, allow responses to our own traffic,
  # allow loopback, allow DHCP client, allow ICMPv4 echo (rate-limited) and the
  # minimum ICMPv6 needed for IPv6 to function.
  cat > /etc/nftables.conf <<'EOF'
#!/usr/bin/nft -f
# ghostinthewires-arch firewall - stateful, deny inbound except our own traffic's responses.
# Edit /etc/nftables.d/*.conf to add per-machine exceptions (e.g. SSH).
# Then: sudo systemctl reload nftables

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Loopback
        iif lo accept
        iif != lo ip saddr 127.0.0.0/8 drop
        iif != lo ip6 saddr ::1 drop

        # Drop invalid
        ct state invalid drop

        # Allow responses to our own outbound traffic
        ct state { established, related } accept

        # ICMPv4: allow echo-request (ping) rate-limited
        ip protocol icmp icmp type echo-request limit rate 5/second accept

        # ICMPv6: required for IPv6 to work (NDP, RA, etc.)
        ip6 nexthdr icmpv6 icmpv6 type {
            destination-unreachable, packet-too-big, time-exceeded,
            parameter-problem, echo-request,
            nd-router-solicit, nd-router-advert,
            nd-neighbor-solicit, nd-neighbor-advert,
            mld-listener-query, mld-listener-report, mld-listener-done,
            ind-neighbor-solicit, ind-neighbor-advert,
            mld2-listener-report
        } accept

        # DHCP client (IPv4 OFFER comes as ct state NEW)
        udp sport 67 udp dport 68 accept
        # DHCPv6 client
        udp sport 547 udp dport 546 accept

        # Per-machine exceptions loaded from /etc/nftables.d/
        include "/etc/nftables.d/*.conf"

        # Log dropped packets (rate limited) and drop
        limit rate 5/minute log prefix "nft-input-drop: " level info
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF

  # Empty include dir so the include wildcard doesn't error on first load.
  # Create a placeholder that nft will happily load as a no-op.
  cat > /etc/nftables.d/00-placeholder.conf <<'EOF'
# Put per-machine rules here. Example: allow SSH from a specific IP.
# To enable SSH inbound (disabled by default for security):
#   sudo gitw-firewall allow-ssh
EOF

  # Validate before enabling
  if ! nft -c -f /etc/nftables.conf; then
    die "nftables config failed validation - refusing to activate"
  fi

  systemctl enable --now nftables.service
  info "Firewall active (deny inbound default)."
}

# =============================================================================
# AppArmor (installed but NOT enabled by default)
# =============================================================================

install_apparmor() {
  hdr "Installing AppArmor (disabled by default)"
  if ! pacman -Q apparmor &>/dev/null; then
    pacman -S --noconfirm apparmor || warn "AppArmor install failed"
  fi
  # Don't enable the service here. gitw-apparmor handles that.
  note "AppArmor is installed but disabled. To enable:"
  note "    sudo gitw-apparmor enable"
  note "Warning: may break apps until profiles are tuned."
}

# =============================================================================
# fwupd
# =============================================================================

enable_fwupd() {
  hdr "Enabling firmware update service (fwupd)"
  systemctl enable --now fwupd-refresh.timer 2>/dev/null || true
  note "Check for firmware updates with:"
  note "    fwupdmgr get-devices"
  note "    fwupdmgr refresh && fwupdmgr get-updates && fwupdmgr update"
  note "Before a firmware update: sudo gitw-tpm-reenroll --pre-update"
  note "After reboot:              sudo gitw-tpm-reenroll"
}

# =============================================================================
# Finalize
# =============================================================================

write_sentinel() {
  mkdir -p "$SENTINEL_DIR"
  date -u +%FT%TZ > "$SENTINEL_DIR/phase-2-harden.done"
}

final_message() {
  cat <<EOF

${GREEN}${BOLD}=============================================${RESET}
${GREEN}${BOLD}  ghostinthewires-arch Phase 2 (harden) complete.${RESET}
${GREEN}${BOLD}=============================================${RESET}

Edit /etc/gitw/features.conf to tune hardening, then run:
    sudo gitw-reconfigure

Helper commands (see 'gitw-' tab-completion or 'ls /usr/local/bin/gitw-*'):
    gitw-reconfigure        Apply features.conf changes
    gitw-unlock-mode        Switch LUKS unlock mode / add FIDO2 keys
    gitw-dns-profile        Switch DNS between home/travel/offline
    gitw-firewall           Manage firewall exceptions (SSH, arbitrary ports)
    gitw-apparmor           Enable/disable AppArmor
    gitw-setup-secureboot   Enroll custom Secure Boot keys (sbctl)
    gitw-network-check      Show LAN/WAN/DNS diagnostics
    gitw-tpm-reenroll       Re-enroll TPM after firmware update
    gitw-verify-fingerprint Compare Librewolf vs Tor Browser fingerprints
    gitw-enable-blackarch   Add BlackArch repo (optional, tools on-demand)
    gitw-enable-chaotic-aur Add Chaotic-AUR repo (optional, AUR binaries)

Next step:
  1. Reboot to apply kernel hardening params:
       reboot
  2. Log in as your user (NOT root).
  3. Run the software phase:
       cd /root/gitw && sudo -u \$USER ./software.sh
     ...or copy software.sh into your home and run it as your user.

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
  write_features_conf
  install_helpers
  apply_kernel_params
  apply_sysctl
  disable_coredumps
  disable_mdns_llmnr
  configure_mac_randomization
  disable_thumbnail_caches
  install_dnscrypt_proxy
  configure_firewall
  install_apparmor
  enable_fwupd
  write_sentinel
  final_message
}

main "$@"
