# Preferences

Loaded on demand from `SKILL.md`. Everything the command needs is here.


The `Preferences/` directory is the skill's general-purpose memory layer for
durable preferences it discovers about how the user works. This is a __core
feature__ of the worklog skill: anything the user wants you to remember across
sessions - about their voice, their tools, their conventions, their decision rules,
their workflow, their formatting choices, their interaction style - gets captured
here as one note per preference.

This is broader than communication. Preferences span the full surface area of
working together:

- __Voice & communication__ - how to write status updates, DMs, status updates,
  meeting notes, emails, peer messages
- __Style & formatting__ - markdown conventions, em-dash policy, list style, when
  to bold, when to use code blocks
- __Workflow & process__ - when to ask vs proceed, when to plan vs execute, how
  fine-grained to make todos, when to commit, when to push
- __Vault conventions__ - how to phrase subgroup labels, when to split items, how
  to date sub-items, what counts as substantive enough to log
- __Decision rules__ - heuristics the user reuses ("never compare candidates",
  "always sync the public mirror after edits", "never send on behalf of me")
- __Tooling__ - which CLI flags to prefer, which APIs to call first, which
  servers / tools the user dislikes
- __Knowledge graph hygiene__ - linking conventions, stub-creation rules, when to
  promote a stub to a real note

Anything the user expects you to remember and apply later belongs here.

### Why this exists

Working preferences are high-leverage and high-context. The user has specific ways
they like things done - some they'll articulate, some they'll only correct after
you've gotten it wrong, some they'll silently accept when you guess right. These
patterns are not visible in the codebase or in the worklog itself; they live in how
the user reacts to your work and what they explicitly ask you to remember.

When you save a preference durably, you're protecting the user from having to give
the same feedback twice. That is the entire point.

### When to capture a preference

Watch for these signals during a session:

1. __Explicit asks__: "always do X", "never do Y", "from now on when X, do Z",
   "save this as a preference", "remember this for next time"
2. __Repeated corrections__: the user has corrected you on the same kind of thing
   more than once. Examples: dropping em-dashes from drafts, re-framing closes to
   be more casual, switching from a checklist to a paragraph, asking for shorter
   summaries, asking you not to commit without confirming
3. __Quiet endorsements__: the user accepts your output without edits when you
   made a non-obvious choice (a particular structural move, a tone calibration, a
   tool selection, a default). These are easy to miss but signal the pattern is
   right
4. __Patterns they explicitly name__: when the user says "in my X voice" or
   "the X-style answer" or "the X workflow" - they're telling you they have a
   named pattern. Capture it under that name

### How to capture a preference

Create a note in `Preferences/` with a Title Case filename describing the
preference. One preference per note. Keep them tight.

```markdown
---
type: preference
applies-to: ["communication", "slack-dm"]
---

# <Preference Name>

## The Rule

<One or two sentences stating the preference crisply.>

## When It Applies

<Triggers - contexts, situations, tasks where this preference activates. Be
specific so future-you can judge edge cases.>

## Why

<The reason - often a past incident, a stylistic choice, a stated value, or a
constraint. The "why" lets future-you adapt the rule when context changes.>

## Examples

<Optional. A good example, a counter-example, or a tiny verbatim phrase the user
has confirmed.>
```

The `applies-to` frontmatter tag helps the skill find relevant preferences fast.
Use short slug-like values that describe the surface or context the preference
governs (e.g., `communication`, `slack-dm`, `status-update`, `markdown`,
`workflow`, `tooling`, `vault-convention`, `decision-rule`).

__Log it:__ append one entry with op `preference` and target the preference title.

### When to apply a preference

Before doing any task that has a preference-shaped surface - drafting a message, writing
markdown, making a workflow choice, picking a tool, structuring a note - run the index:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/preferences-index.sh '__VAULT_PATH__'
```

It prints one record per preference (`title`, `applies_to`, `rule`). Select the 1-3 whose
`applies_to`/title/rule match the task, then read __only those__ full bodies from
`Preferences/<Title>.md`. Do not read every preference file. Cite the ones you applied
lightly so the user can correct you.

### Examples of preference notes worth capturing

These are illustrative - the actual notes are whatever the user wants to remember:

- __Markdown Formatting__ - bold/italic conventions, em-dash policy, list style
- __Slack DM Voice__ - opener style, closing patterns, formality level
- __Status Update Voice__ - structure, tone, framing for upward-facing notes
- __Meeting Notes Style__ - how to structure transcripts and decisions
- __Commit Discipline__ - when to commit, push, ask first, use a different identity
- __No Comparisons__ - never compare candidates / teams / people in writing
- __Sub-item Linking__ - which kinds of items get sub-items vs new top-level items
- __Tool Preferences__ - which CLI flags, which APIs, which servers to prefer
- __Frontmatter Conventions__ - vault-specific rules for YAML fields
- __Default Recipes__ - canonical defaults the user wants you to confirm before
  acting (e.g., a default protein shake, a default deploy target)

The skill simply helps create, maintain, and apply these notes.

### Editing and removing preferences

If a preference becomes outdated (the user changes how they want something done),
update the note rather than creating a new one. Note the date of the change
inline so you can see how the preference has evolved.

If the user explicitly retracts a preference ("I don't want to do that anymore"),
update the file to mark it deprecated rather than deleting - preserves the
history of the user's evolving working style. Or delete entirely if they prefer.
