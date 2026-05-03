# Threat Model Worksheet

A structured tool for thinking through your personal security situation and what to do about it.

## How to use this document

1. **Read the whole thing once before filling anything in.** The sections build on each other.
2. **Fill it out in plain language.** Not bullet points, not jargon. Write paragraphs that sound like how you'd explain your situation to a thoughtful friend.
3. **Save it somewhere private.** The completed worksheet describes your life in detail. Encrypted, not in cloud sync, not in a shared password manager note.
4. **Take it to an AI assistant for discussion.** Claude, ChatGPT, Lumo, Grok, or another LLM you have a paid subscription to. Paste the whole worksheet at the start of a conversation and ask the assistant to help you turn it into an action plan.

A few important notes about using AI for this:

- **Threat modeling is not a tool decision.** It is a thinking exercise. The AI's job is to help you think, not to tell you what to install.
- **Be skeptical of confident answers.** If an LLM tells you definitively to do X, ask why. Ask what assumptions it's making about your situation. Ask what it would recommend if those assumptions were wrong.
- **The output is yours, not the AI's.** Save the conversation and the action plan that comes out of it. Re-read the plan a week later. If something feels wrong, it probably is.
- **This worksheet does not solve threats.** It identifies them. The follow-on work is choosing controls (some of which ghostinthewires provides, many of which it does not).

## Why this exists outside the installer

Threat modeling is bigger than computer configuration. The choices that actually keep most people safe — where they live, who they talk to, what name appears on what document, what their lawyer is doing for them, how much money they have set aside, who they tell about their work — are upstream of any setting in `/etc/`. A hardening script that pretends otherwise is making promises it cannot keep.

The same threat model, depending on details, might point to:

- A different operating system entirely
- Hiring a lawyer
- Moving to a different state
- Telling a family member to stop posting photos of you on social media
- Buying a different phone
- Changing jobs

None of those are things ghostinthewires can do for you. Naming them honestly is part of the job.

---

## Section 1: Who you are, in the simplest terms

In one paragraph, describe yourself in the way a stranger meeting you for the first time might. Not "Senior Cybersecurity Engineer at Acme Corp." — more like "I'm a software person in my mid-thirties living alone in a city, parents are still alive and live a few hours away, no kids, currently single, a couple of close friends locally and a small online community of people I've known for years."

The point is to ground the rest of the document in the actual texture of your life, not an abstraction.

## Section 2: What you have to lose

List the things you would consider catastrophic to lose. Be honest. Include things that don't sound "security-shaped." Examples of categories to think about, not a checklist:

- **Physical safety** — yours, and people you love
- **Freedom** — not being arrested, not being detained at a border, not having a court order against you
- **Money and stability** — your income, your savings, your housing
- **Reputation** — under your legal name, under any handle you operate, in any community where being known matters
- **Relationships** — people you love and the privacy of those relationships
- **Information** — communications, work product, creative work, photographs, journals, research
- **Time** — what you do during a day, where you go, when you go there
- **The future** — career path, plans, ability to make choices later

For each item that matters to you, write one or two sentences about what losing it would mean and how recoverable it is. Some losses are recoverable (money, even a job). Some are not (a person, a body part, a child custody outcome, a reputation in a small community).

## Section 3: Who could harm you, and how

Think about specific people, organizations, and categories of actor who could plausibly want to harm you. For each one, answer:

- **Who they are.** Specific, if specific. Categorical, if categorical.
- **Why they would.** Their motivation. What they think they would gain or what grievance they hold.
- **What they can do.** Their actual capabilities. Not theoretical capabilities. What have they done before?
- **What they have done.** History matters. Past behavior is the best predictor.
- **How likely they are to engage you specifically.** Probability over the next year.
- **What it would cost you if they did.** Severity if it happens.

Categories to consider:

- A specific individual (ex-partner, family member, former friend, online stalker, neighbor, coworker, manager)
- An employer or former employer (especially if you've made a complaint, raised an issue, or might in the future)
- A government agency (yours or another country's, especially if you cross borders)
- A community you've left or angered
- An ideological group that has named you or your kind of person as a target
- Commercial data brokers and the advertising industry (passive but persistent)
- Opportunistic attackers (random scammers, ransomware operators)
- A former colleague who has reason to retaliate
- The press (if a story you're connected to becomes news)

You don't need to list everything. List who is real for you, and rank them by a combination of likelihood and severity. The top of the list is what your defenses are actually for.

## Section 4: How they could reach you

For each significant adversary in section 3, write down the surfaces through which they can affect you. Some examples of surfaces (not a checklist):

- **Physical location** — your home address, your workplace, where you regularly are
- **Phone number** — calls, SMS, the join key for many data broker records
- **Email addresses** — work, personal, public-facing, recovery
- **Legal name** — court records, news, social media under that name
- **Public handles** — usernames, pseudonyms, project names, GitHub accounts
- **Family members** — addresses, photos, relationships, social media
- **Friends and partners** — same
- **Devices** — phone, laptop, work laptop, home network, IoT
- **Accounts** — banking, healthcare, government, social media, cloud storage
- **Routines** — when you leave the house, what coffee shop, what gym
- **Vehicles** — license plate, regular routes
- **Documents** — passport, driver's license, voter registration, court filings
- **Police as a weapon** — if someone might call 911 with a fabricated emergency at your address

For each adversary, mark which surfaces they realistically have access to and which they don't. This is the honest map of where your real exposure is.

## Section 5: What's already in place

What protections do you already have? Examples:

- Restraining orders, no-contact orders, protective orders
- Address Confidentiality Program enrollment
- Geographic distance from a specific person
- A lawyer who knows your situation
- A locked-down social media presence under your legal name
- Hardware 2FA on important accounts
- A password manager you actually use
- Encrypted backups
- A bug-out plan if something escalates
- Trusted people who would help in an emergency
- Money set aside for a lawyer or a sudden move
- A job that lets you work from anywhere
- A different phone for sensitive matters

Be specific and honest. "I have 2FA on my email" is better than "I take security seriously."

## Section 6: What's not in place but could be

For each significant adversary and each surface, what defenses are realistically available that you haven't put in place yet? Don't filter for "things a Linux installer can do" — write everything. The follow-on AI conversation will help you sort which ones are technical, which are legal, which are about other humans, and which are about your own habits.

Some examples:

- Hire a lawyer. (For what specifically?)
- File for a protective order. (Against whom? On what grounds?)
- Move. (To where? When? Why?)
- Change jobs. (To what kind of role? On what timeline?)
- Talk to family member X about not posting photos. (Which family member? What conversation?)
- Set up a PMB or PO box.
- Enroll in your state's Address Confidentiality Program.
- Sign up for a data broker removal service. (Which one? Why?)
- Rotate your phone number.
- Set up Google Alerts on your legal name.
- Replace a specific account with a more private alternative.
- Change a routine (route home, regular coffee shop, gym).
- Start saving money toward a runway.
- Reduce or eliminate a public-facing online presence under your legal name.
- Tell a small number of people what's actually going on so they can help.
- Get into therapy.

Write the ones that are real for you. Order them by impact and feasibility.

## Section 7: What you're explicitly choosing not to do

This section is important and most worksheets skip it.

For each major risk you identified, are there controls you've considered and rejected? Why?

Examples of legitimate reasons to reject a control:

- "It would interfere with parenting / caretaking obligations."
- "It would damage relationships I'm not willing to damage."
- "I can't afford it."
- "I'm choosing the convenience."
- "The threat is real but the defense is worse than the threat."
- "I've decided I'd rather risk this than live like that."

Writing these down is the difference between a thoughtful adult making real tradeoffs and a list of unfollowed advice that becomes a source of shame. If you're choosing convenience over a defense, own the choice. If a defense is too expensive in money or time or relationships, name it.

## Section 8: The thing you don't want to admit

Most threat models miss the thing the person is most reluctant to face. It might be:

- A relationship you should leave but haven't
- A conversation you should have but haven't
- A pattern in your own behavior that's making you less safe
- A risk you're taking because you're tired or in pain or grieving
- A defense you've put off because it requires admitting something is true
- A person who is harming you that you haven't named to yourself as harmful

You don't have to write this in the worksheet. But you should know what it is. The AI conversation that follows is more useful when it knows what you're not saying.

## Section 9: Things this project specifically can or cannot do

ghostinthewires provides:

- Disk encryption and tamper-evident boot
- Kernel and userland hardening
- Network firewall and DNS privacy
- Browser hardening guidance
- Snapshot rollback
- Tools for managing your own keys, credentials, and unlock methods

ghostinthewires cannot provide:

- A lawyer
- A different address
- Protection from a person who has already been to your home
- Protection from a court order or subpoena
- Recovery from a 911 call to your address
- Protection of your reputation under your legal name
- A relationship with people who are not in your life
- Therapy, sleep, food, or rest
- The decision to change something about your life that needs changing

When you're working through your action plan with the AI, sort items by which category they belong in. ghostinthewires items go in `/etc/gitw/features.conf` and helper scripts. The other items are the more important work.

## Section 10: Action plan

After you finish discussing this worksheet with an AI, write down the resulting action plan. Format it however helps you act on it.

Useful structure:

- **In motion** — things you're already doing
- **This week** — concrete next actions, with named first steps
- **This month** — larger actions with deadlines
- **Pending external** — waiting on someone else (a lawyer's response, a court date, a job application)
- **Deferred for now** — things you've decided to delay, with the conditions under which you'd revisit

Update the plan when situations change. Rewrite the worksheet from scratch every six to twelve months, or after any significant life event.

---

## Recommended prompts for the AI conversation

After pasting the filled-out worksheet, try one of these to start the discussion:

> Based on the threat model I've just shared, help me think through what an action plan should look like. Don't lead with technical recommendations. Start by asking me clarifying questions about the parts of my situation that seem most urgent or unclear.

> Read this threat model. Tell me what you think the top three risks are and why, and where you think I'm underweighting or overweighting specific threats.

> Read this threat model. What questions would a lawyer ask me that I haven't asked myself? What questions would a therapist ask me? What questions would someone with the same threat profile, ten years further along, ask me?

> Help me identify which items from sections 6 and 7 should happen first. Push back if I'm prioritizing the easy ones over the important ones.

The goal is not for the AI to give you a checklist. The goal is for you to think clearly about your situation with a patient, well-read interlocutor who will not be tired of your case.

---

## A note on AI confidentiality

LLM conversations are not confidential the way attorney-client communication is. Some providers offer settings to disable training-data retention; some do not. If the contents of this worksheet would be damaging if disclosed in legal proceedings, save them to encrypted local storage and consult with your attorney about whether to use an AI for the discussion at all.

For most people, most of the time, a thoughtful AI conversation about threat modeling is fine. For people in active legal proceedings, it is worth a five-minute consultation with their attorney before pasting their life into a chat interface.
