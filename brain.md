# ghostinthewires — Brain Document

A single document capturing what a fresh Claude conversation needs to know to pick up this project. Pair this with the parity spec in the repo and you have full context.

---

## What this project is

**ghostinthewires** is a security-focused, reproducible Linux workstation, available in Arch and Gentoo editions. The two editions maintain user-facing parity — same helper CLIs, same configuration schema, same behavior — and differ only where the underlying distribution forces them to.

It is not "an install script." It is a complete workstation specification with two distro-backed implementations, a parity discipline that keeps them aligned, and explicit acknowledgment of where computer hardening ends and other kinds of safety work (legal, social, financial, geographic) begin.

**Repo:** `github.com/wakefieldite/ghostinthewires` (public, monorepo, GPLv3, branches `main` and `dev`).

**Status:** Arch edition is code-complete pending tooling additions (`gitw-aur-review`, `gitw-build-mode`, `gitw-ai`, `gitw-cis` framework, runtime logging, test harness) and VM testing. Gentoo edition is being ported to parity by a parallel Claude conversation. v0.1 release gate requires both editions VM-tested end-to-end.

**Maintainer:** wakefieldite. Throughout this project they should be referred to as "the maintainer" or addressed in second person ("you"). Do not invent a name. (A previous version of this brain document hallucinated one — that's been corrected.)

---

## How it's organized

```
ghostinthewires/
├── README.md              Landing page
├── PARITY_SPEC.md         Source of truth for cross-edition decisions (currently v0.3)
├── CIS_CONTROLS.md        Per-control rationale, impact, recommendations
├── GENTOO_BRIEF.md        Handoff doc for the Gentoo conversation
├── LICENSE                GPLv3 placeholder (replace with full text)
├── arch/                  Arch edition (install.sh, harden.sh, software.sh, helpers/, README.md)
├── gentoo/                Gentoo edition (in progress, parallel Claude conversation)
├── shared/
│   ├── helpers/           Distro-neutral gitw-* helpers
│   ├── lib/               Shared shell libraries (logging, validation) — TO BUILD
│   └── cis/               CIS control bundles — TO BUILD
├── docs/
│   ├── threat-modeling/   Worksheet + README — recently added
│   └── (more to come)
└── tests/                 Test harness — TO BUILD
    ├── static/            shellcheck, schema, CLI contract
    └── cis/               control round-trip
```

The monorepo design exists because parity is the architectural commitment. Two repos would mean every shared decision needs two PRs that drift; one repo means a parity-affecting change is a single atomic diff.

---

## The three-phase install model

Both editions follow the same shape:

**Phase 1 — `install.sh`** (root, live ISO/stage3): partition, encrypt with LUKS2+argon2id, fill with random data pre-encryption, create Btrfs subvolumes, install base system, configure GRUB with encrypted `/boot`, enroll TPM2+PIN and FIDO2 keyslots, set up Snapper. Sentinel: `/var/lib/gitw-install/phase-1-install.done`.

**Phase 2 — `harden.sh`** (root, first boot): writes `/etc/gitw/features.conf`, applies kernel cmdline hardening, sysctl hardening, native nftables firewall (INPUT drop default), dnscrypt-proxy with Anonymized DNSCrypt, NetworkManager MAC randomization, MDNS/LLMNR off, coredump disable, AppArmor install (off by default). Installs all helpers to `/usr/local/bin/`. Sentinel: `phase-2-harden.done`.

**Phase 3 — `software.sh`** (user, sudo internally): bootstraps paru on Arch from `paru-bin`, installs Hyprland + Wayland ecosystem, GPU drivers (Intel/AMD/NVIDIA/nvidia-open for Blackwell), Librewolf + Tor Browser via paru with PKGBUILD review, greetd login manager, prompts for AI stack if NVIDIA+CUDA detected. Sentinel: `phase-3-software.done`.

Each phase is sentinel-gated and re-runnable. Failure in phase N doesn't destroy phase N-1.

---

## The locked invariants (don't relitigate without parity-spec amendment)

These are identical across both editions:

- **Encryption:** LUKS2, argon2id, aes-xts-plain64, pre-encryption random fill, encrypted `/boot` via GRUB.
- **Unlock modes:** `simple` / `tpm-pin` (default) / `combined` (stubbed for v0.1). Break-glass long passphrase always in slot 0.
- **TPM2:** PCRs 0+7. Survives kernel/initramfs/bootloader updates. Breaks on firmware updates and Secure Boot state changes (intentional — those are tamper signals).
- **FIDO2:** primary + backup enrollment prompted in Phase 1.
- **Init:** systemd on both editions (Gentoo uses systemd profile, not OpenRC).
- **Filesystem:** Btrfs with subvolumes `@`, `@home`, `@snapshots`, `@var_log`, `@var_log_audit`, `@var_cache`, `@var_tmp`, `@var_lib_docker` (created unmounted). zstd:3 compression, autodefrag only on rotational disks.
- **Snapshots:** Snapper + grub-btrfs + pre/post package-manager hooks (`snap-pac` Arch, custom `/etc/portage/bashrc` Gentoo).
- **Firewall:** native nftables, INPUT drop default, stateful, `/etc/nftables.d/` for per-machine rules. SSH off by default.
- **DNS:** dnscrypt-proxy with Anonymized DNSCrypt, three profiles (home/travel/offline). Steven Black blocklist.
- **Network:** NetworkManager only.
- **MAC layer:** AppArmor on both editions, default off. SELinux opt-in on Gentoo only.
- **Browsers:** Librewolf + Tor Browser. Arch via AUR/paru, Gentoo via official overlays. **No Flatpak in default path.**
- **Compositor:** Hyprland + greetd. NVIDIA early KMS configured.
- **Swap:** zram via zram-generator. No disk swap, no hibernate.
- **AI stack:** opt-in, NVIDIA+CUDA gated, prompted in Phase 3. `/ai/pytorch-env/` and `/ai/tensorflow-env/`. Ollama + Open WebUI on localhost. Runs as user, sudos for system bits.
- **License:** GPLv3.

---

## What's been built vs. what's pending

### Built and committed to the repo
- `arch/install.sh`, `arch/harden.sh`, `arch/software.sh` (passes `bash -n`, not VM-tested)
- `arch/helpers/gitw-enable-blackarch`, `arch/helpers/gitw-enable-chaotic-aur`
- `shared/helpers/gitw-{reconfigure,unlock-mode,dns-profile,firewall,apparmor,setup-secureboot,network-check,tpm-reenroll,verify-fingerprint}` (9 distro-neutral helpers)
- `README.md`, `PARITY_SPEC.md` v0.3, `CIS_CONTROLS.md` (5 starter controls), `GENTOO_BRIEF.md`, `arch/README.md`, `LICENSE` placeholder
- `docs/threat-modeling/THREAT_MODEL_WORKSHEET.md` and its README

### Stubbed (CLI exists, no implementation)
- Combined unlock mode (`gitw-unlock-mode set combined` errors with "hook source not found")

### Pending for v0.1, in priority order
1. **`gitw-aur-review`** — paru wrapper with PKGBUILD review, `validpgpkeys` parsing, signing-key change detection. Highest priority because it gates Librewolf/Tor Browser installs in Phase 3.
2. **`gitw-build-mode`** — binary/source/source-only AUR build preference toggle.
3. **`gitw-ai`** — runs as user, sudos for system bits. NVIDIA+CUDA detection, Ollama + Open WebUI + PyTorch/TF venvs.
4. **`gitw-cis` framework + 5 starter L1 controls** — minimal scope. Full benchmark adaptation deferred to v0.2.
5. **Runtime validation logging** — structured logging library at `shared/lib/gitw-log.sh`, log entries for every settings-applying action and its verification, end-of-phase summaries. Critical: this is the integration test.
6. **Static test harness** — shellcheck, features.conf schema validator, helper CLI contract tests, parity checks.
7. **VM testing** — QEMU + OVMF + swtpm. Final validation.

### Deferred to v0.2 explicitly
- Combined unlock mode (TPM AND FIDO2 hook)
- Full CIS benchmark adaptation (RHEL primary, Ubuntu for AppArmor)
- Wintermute desktop build (RTX 5090 testing)
- `gitw-ai proxy`
- Pentoo integration
- VPN-aware DNS profile auto-switching

---

## Important caveats for any new conversation to know

1. **Nothing has been VM-tested.** All "this works" claims are syntax-only or static-analysis-only. The Arch installer might fail in QEMU and we wouldn't know yet.

2. **The combined unlock hook is vaporware.** Designed on paper, no implementation. Don't promise users this works.

3. **The `harch-*` to `gitw-*` rename happened.** The repo is `wakefieldite/ghostinthewires`, not `wakefieldite/hArch`. All paths are `/etc/gitw`, `/var/lib/gitw-install`, `/usr/share/gitw`. The hArch repo is deprecated.

4. **No autonomous GitHub write access.** I (and the Gentoo conversation) can read public URLs via `web_fetch`. Writes go through the maintainer as patches/zips/file contents they commit. The current model is "Claude produces, maintainer reviews and commits."

5. **The maintainer is a learning user, not a Linux internals expert.** They're competent and motivated, but explicitly asked: "do not trust what I have here as gospel... if there's a better way to do things, I want everything to be done the best it can be." When their instinct conflicts with current best practice, correct them with sourced reasoning. They value that more than agreement. When they say something works in their existing setup, verify the claim — past examples include NVIDIA modules in HOOKS instead of MODULES, deprecated `xf86-video-intel`, conflicting network stacks all enabled at once, and copy-pasted zram folklore tuning.

6. **Threat modeling is out of scope for the installer.** v0.3 of the parity spec removes the `gitw-threat-profile` questionnaire concept. Instead, `docs/threat-modeling/THREAT_MODEL_WORKSHEET.md` is a worksheet users fill out (with help from an AI of their choice) and turn into an action plan separately. The installer is one small part of that plan; the rest is upstream.

7. **CIS scope:** v0.1 ships the framework + 5 starter L1 controls only. Full RHEL/Ubuntu benchmark adaptation is v0.2 work, sequenced after both editions reach feature parity and pass VM testing. This matters because it's tempting to expand v0.1 to "all CIS controls" and the maintainer has explicitly chosen not to.

8. **Runtime logging is the integration test.** The plan is to bake structured verification into every install/harden/software action — apply a setting, then check the setting actually took effect, log the result. The log itself becomes the proof of correctness. Static unit tests for shell scripts have limited value compared to this.

9. **"Push back when I'm wrong" is explicit consent.** Don't agree just to be agreeable. Don't soften criticism to be polite. Don't recommend something you wouldn't recommend if asked directly.

10. **The maintainer is managing significant outside-of-project load.** Don't take this as a reason to be sycophantic, but do take it as a reason to keep responses focused, well-scoped, and aligned with what actually moves the project forward.

---

## How to brief a new conversation

Paste this document plus the current `PARITY_SPEC.md` from the repo (fetch via `https://raw.githubusercontent.com/wakefieldite/ghostinthewires/main/PARITY_SPEC.md`).

Tell them:
- Whether they're the Arch conversation or the Gentoo conversation
- What task you want them to work on
- That writes go through the maintainer as patches/file contents, not direct GitHub commits

A typical session opener:
> I'm continuing work on ghostinthewires-arch. Read this brain document and fetch the current `PARITY_SPEC.md` from the repo. I want to work on `gitw-aur-review` next — implement the helper per parity spec §3 invariant 31. Produce file contents for me to commit.

That's enough context for a clean handoff.

---

## Open items

- **Runtime validation logging design** — needs implementation. Library at `shared/lib/gitw-log.sh`, used by all three phase scripts. Verifiers for kernel params, services, file content, LUKS keyslots, packages.
- **Test harness directory** — `tests/static/` and `tests/cis/`. Scripts written, not yet hooked up to CI (CI hookup deferred).
- **`gitw-aur-review` implementation** — wraps paru, parses PKGBUILDs for `validpgpkeys`, maintains signing-key database at `/var/lib/gitw/aur-keys.db`, warns on unsigned packages.
- **`gitw-build-mode` implementation** — three modes (binary-preferred, source-preferred, source-only), allowlist for slow-compile fallback packages (chromium, libreoffice, rust, llvm).
- **`gitw-ai` implementation** — NVIDIA+CUDA detection, prompt UX, install/remove/status/models subcommands.
- **`gitw-cis` framework** — apply/revert/status/diff loop, JSON state tracking, backup directory layout, 5 starter control bundles.
- **VM testing recipe** — QEMU + OVMF + swtpm. Documented in `docs/dev/testing.md`. Not written yet.

The next session should pick one of these and produce the implementation as files for the maintainer to commit. Suggested order: aur-review → build-mode → ai → cis-framework → logging library → test harness → VM testing.
