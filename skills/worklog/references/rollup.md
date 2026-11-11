# `/worklog rollup`

Loaded on demand from `SKILL.md`. Everything the command needs is here.


Generate an IC-appropriate weekly context dump for posting to a broad team
channel (e.g. `#eng-all`, `#team-broadcasts`). This is your voice speaking to the
whole org: what happened this week that individual contributors would benefit
from knowing, organized into two buckets. Copies a Slack-mrkdwn-formatted
message to the clipboard via `pbcopy`.

**Audience:**

- Individual contributors across the org (not just leads or peers)
- Posted to a broad channel, not DM or leadership-only

**Content rules — what to INCLUDE:**

- Program-level updates, structural decisions, publications
- Framework changes, org-wide patterns (e.g., paved roads)
- Ownership / tech lead assignments at the program level
- Cross-team themes and trade-offs
- Public artifacts (docs shipped, decisions landed)
- Things ICs can act on, escalate, or route based on

**Content rules — what to FILTER OUT:**

- Performance commentary (growth conversations, assessments, team performance issues)
- 1:1 specifics (what someone said privately, personal context)
- Hiring candidate names, pipeline details, feedback notes
- Career conversations, individual coaching, certainty scores
- Inter-leader negotiation details (who said what to whom behind the scenes)
- Anything marked as private or sensitive in the source item

**Source:**

Read the current week file. Scan both active and Done items. Each item should be
evaluated against the include/filter rules. When in doubt, soften or drop - this
is a broadcast channel, not the leadership thread.

**Structure:**

```
:wave: Weekly context dump - W<NN> (Mon D-D)

*Stuff you should probably know*

• *Headline for item one.* One or two sentences of context. What's the action or implication for the reader?

• *Headline for item two.* ...

(6-8 bullets. The items most likely to affect the reader's own work or routing decisions.)

*Context: everything else*

• Item one, one sentence.

• Item two, one sentence.

(5-8 bullets. Lighter, one-liner style. FYI-grade items.)

Next week: <one-liner, if relevant>
```

**Formatting:**

- Use Slack mrkdwn: `*bold*` for bold, `_italic_` for italic, `•` for bullets
- In the clipboard rendering, no wiki-link syntax (`[[...]]`) - Slack cannot render
  it. The filed copy keeps its links; see Output below
- Include names only when they denote program ownership or the right contact
  for a question (e.g., "Sam is tech lead" is fine; "strong signal on
  candidate X" is not)
- Keep bullets to 1-3 sentences each; link to the source doc in Slack if the
  item needs more depth (user can add link after pasting)
- Emoji are welcome but sparing - a friendly opener and maybe a sign-off

**Output:**

After generating the message, copy it to the clipboard via `pbcopy` and tell the user the
message is ready to paste.

__Then file it.__ Write `References/YYYY-WNN Rollup.md`:

```markdown
---
type: reference
subtype: rollup
period: 2026-W31
source: /worklog rollup
---

# W31 Rollup (Jul 27-31)

<the same content, with [[wiki-links]] kept>
```

Two renderings of one artifact. The clipboard version strips `[[wiki-links]]` because
Slack cannot render them; the filed version keeps them, which is the entire reason
filing is worth doing - the rollup then shows up in backlinks on every program it
names, and the judgment that went into it compounds instead of evaporating.

__Filing does not relax the filter.__ The include and exclude rules above apply to both
renderings. `References/` is synced to the backup repo, so performance commentary, 1:1
specifics, and candidate details stay out of the filed copy too.

If a file already exists for the period, tell the user and ask whether to overwrite.

__Log it:__ append one entry with op `rollup` and target the filed path.

**Edge cases:**

- If the current week has very few Done items and most work is In Progress,
  frame items as "in flight" and still surface them if program-relevant.
- If the user requests a different audience ("send this to leads" or "make it
  shorter"), adapt the filter/structure on the fly but keep the same split.
