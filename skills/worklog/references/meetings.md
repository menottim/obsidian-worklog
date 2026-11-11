# Meetings

Loaded on demand from `SKILL.md`. Everything the command needs is here.


The `Meetings/` directory holds one markdown note per ingested Slack thread. These
are durable artifacts: a permanent, searchable record of every meeting whose notes
posted to a registered `Sources/*.md` channel. Linked into the knowledge graph
through wiki-links to participants and programs.

__Filename:__ `Meetings/YYYY-MM-DD-<topic-slug>.md`

- `YYYY-MM-DD` is the email-send date or the top-of-thread Slack timestamp,
  rendered in __the user's local timezone__ (matches how weekly files are dated).
- `<topic-slug>` is kebab-case from the email subject. Lowercase. Strip
  non-alphanumeric characters except hyphens. Cap at ~50 chars.
- On collision (same date + same slug), append `-2`, `-3`, etc.

__Meeting note structure:__

```markdown
---
type: meeting
date: 2026-05-04
source_channel: "#example-meeting-notes"
source_channel_id: C0XXXXXXX
slack_thread_ts: "1714694400.123456"
slack_last_reply_ts: "1714780800.654321"
slack_thread_url: https://example.slack.com/archives/C0X.../p171...
participants:
  - "[[Sarah Chen]]"
  - "[[Marcus Williams]]"
programs:
  - "[[Hiring]]"
status: ingested
---

# <Email Subject>

> [!info] Slack thread in [[Sources/example-meeting-notes|#example-meeting-notes]] · [open in Slack](https://...)
> Original sender: <name> · Posted 2026-05-04 09:00 PT

## Notes

<email body - meeting notes verbatim, lightly cleaned up: strip email-client
chrome (signatures, "On <date> X wrote:" quote blocks, unsubscribe footers),
keep the substantive content>

## Discussion

### 2026-05-04 09:15 — [[Sarah Chen]]
<reply>

### 2026-05-04 11:42 — [[Marcus Williams]]
<reply>

## Extracted Items

- See [[YYYY-WNN]] for items added to this week's worklog
```

__Frontmatter fields:__

- `type`: always `meeting` for files in this directory.
- `date`: YYYY-MM-DD of the email-send date or top-of-thread ts (user's local TZ).
- `source_channel`, `source_channel_id`: which `Sources/*.md` produced this note.
- `slack_thread_ts`: the top-level message's Slack timestamp - the unique thread
  identifier. Used by `/worklog pull` to look up "have we ingested this thread."
- `slack_last_reply_ts`: timestamp of the most recent reply ingested. Equals
  `slack_thread_ts` if the thread has no replies yet. Updated on every pull that
  appends new replies.
- `slack_thread_url`: deep link to the thread in Slack.
- `participants`: wiki-linked array of people who appear in the thread. Sourced
  from thread repliers + names mentioned in the email body. Use
  `slack_search_users` to resolve full names per the existing Cross-Linking rules.
- `programs`: wiki-linked array of programs mentioned in the thread.
- `status`: `ingested` once the meeting note + extraction are complete. Reserved
  for future statuses.

__Discussion section subheadings:__ `### YYYY-MM-DD HH:MM — [[Author]]` in the user's
local timezone, chronological order (oldest first). New replies appended to the
end of the section preserve chronological order naturally.

__User edits are preserved:__ on subsequent pulls, only the `## Discussion` section
is appended to and `slack_last_reply_ts` is updated. The `## Notes` section and
any user-added content elsewhere in the file is never overwritten. If the user
deletes a Meetings note, the next pull recreates it from scratch (because the
`slack_thread_ts` no longer matches any frontmatter).

__No frontmatter auto-generation:__ Meetings notes are not subject to the
Frontmatter Auto-generation rules below (those apply to weekly, archive, and
summary files). The participant/program wiki-link extraction for Meetings
frontmatter happens once at write time and is not regenerated on every edit.

### What earns a page

Create a People stub for any person named who does not have one. People are cheap and
the graph is the point.

Be stricter with Programs. A Program page is a named, ongoing initiative with an owner -
the kind of thing that recurs across weeks and accumulates history. A document, a
proposal, a ticket, a meeting, a review, or simply the subject of one item does not get
one; it stays plain text in the item title. "API rate limit proposal" mentioned once is
not a program, and creating a page for it puts a permanent empty note in the vault that
`audit` will keep reporting.

If you are unsure whether something is a program, leave it as text. The second mention
is a better time to decide, and by then the vault will tell you.

An item that accumulates real history but does not meet this bar gets a `Threads/` note,
not a Program page. A Thread is the dated log of one worklog item; a Program page is the
initiative the item is about. See `references/threads.md`. A Thread never gets promoted to
a Program page, which is what keeps this rule strict rather than merely inconvenient.

### People named by first name only

A mention with no surname that resolves to no existing entity still gets a stub, filed
under the first name exactly as given: `People/Alex.md`. Link to it as `[[Alex]]`.

Record in the body what the mention actually told you - the team, the topic, the date -
and say plainly that the surname is unconfirmed. Do not stop to ask the user, and do not
skip the stub: an unlinked name is invisible in the graph, and the next mention of that
person has nothing to attach to.

When a later mention supplies the surname, rename the note and let the links follow.
This is deliberately the lossy-but-recoverable choice. A missing note cannot be
recovered from a name nobody wrote down.
