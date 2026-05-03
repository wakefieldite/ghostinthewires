# Threat modeling

This directory holds documents that help users think through their personal security situation. Threat modeling is intentionally **out of scope** for the ghostinthewires installer itself — the choices that actually keep most people safe are upstream of any setting in `/etc/`.

## Why threat modeling lives here, not in the installer

ghostinthewires installs a hardened workstation. It does not know:

- Whether you have a person in your life who would harm you if they could find you
- Whether your employer might retaliate against you for something you've reported
- Whether you're crossing borders into countries hostile to your work
- Whether your real risk is a $50 ransomware operator or a state actor
- Whether you have a lawyer, an Address Confidentiality Program enrollment, a restraining order, or none of those

The installer can configure your disk encryption and your firewall. It cannot replace any of the above. Pretending otherwise — by trying to derive an installer config from a multiple-choice quiz about your life — would create false confidence in the wrong place.

So we ship a worksheet instead. You fill it out yourself (or with help from an AI assistant), think through your actual situation, and sort the resulting actions into "things ghostinthewires can configure," "things that need a lawyer," "things that need a different conversation with a person in your life," and "things only you can decide."

## Files

- **[`THREAT_MODEL_WORKSHEET.md`](./THREAT_MODEL_WORKSHEET.md)** — the worksheet. Read it once, fill it out in plain language, take it to an AI assistant for discussion, end up with an action plan.

## How to use the worksheet

1. Read it through once before filling anything in.
2. Save it locally and fill it out in plain language. Be specific about your actual situation, not abstractions.
3. The completed worksheet is sensitive — store it encrypted, don't sync it through cloud services you wouldn't trust with your journal.
4. Take it to an AI assistant (Claude, ChatGPT, Lumo, Grok, or whatever you pay for) and ask the assistant to help you turn it into an action plan.
5. Update it when situations change. Rewrite from scratch every six to twelve months, or after any significant life event.

## What ghostinthewires can and cannot do

After the worksheet conversation, you'll have an action plan. Some items map to ghostinthewires features:

- **Disk encryption, tamper-evident boot** → `arch/install.sh` / `gentoo/install.sh`
- **Kernel and userland hardening** → `harden.sh` + `/etc/gitw/features.conf`
- **Network firewall** → `gitw-firewall`
- **Private DNS** → `gitw-dns-profile`
- **Browser hardening guidance** → `gitw-verify-fingerprint`
- **Snapshot rollback** → Snapper + grub-btrfs (configured at install)
- **Hardware-backed unlock** → `gitw-unlock-mode`
- **CIS-style hardening controls** (when shipped) → `gitw-cis`

Other items will not. Things ghostinthewires explicitly cannot help with include legal counsel, address protection programs, restraining orders, financial runway, therapy, sleep, the decision to leave a job or a relationship, or protection from a person who has already been to your home. Those are the more important parts of most people's threat models, and they live outside this project's scope.

If you want to compare notes with a community of people thinking about similar problems, the EFF's [Surveillance Self-Defense](https://ssd.eff.org/) is a good place to start — particularly their threat-modeling guide, which inspired some of the structure of our worksheet.

## A note on AI confidentiality

Before you paste your filled-out worksheet into a chatbot:

- LLM conversations are **not confidential** in the legal sense. Attorney-client privilege does not apply.
- Some providers offer settings to disable training-data retention; some don't.
- If the contents of your worksheet would be damaging if disclosed in legal proceedings, consult your attorney before using an AI for the discussion. They may suggest a different approach (a human, a paid service with confidentiality terms, an on-device model).

For most people, most of the time, a thoughtful AI conversation about threat modeling is fine. For people in active legal proceedings, it's worth a five-minute consultation first.
