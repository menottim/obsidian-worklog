#!/usr/bin/env python3
"""Generate the oversized, structured People notes the compaction cases need.

Kept out of make-vault.sh so every other case keeps a small, fast vault, and
kept in its own file rather than a nested heredoc so it stays readable.

Each note is built for a specific rule in references/compact.md:
  Avery     current-state sections that must survive byte-identical, plus
            frontmatter that contradicts the body
  Rachel    an already-compacted note with an immutable ## History and entries
            that have aged out of the keep window since
  Morgan two same-theme entries whose handling-marker sets differ only
            because one has a stricter nested child
  Bryce     a plain oversized note for the git-state cases
"""
import datetime
import pathlib
import sys

dest = pathlib.Path(sys.argv[1])
today = datetime.date.today()
LOCK = "\U0001F512"


def when(days_ago):
    return (today - datetime.timedelta(days=days_ago)).strftime("%b %-d, %Y")


def entry(days_ago, title, lines, level="##"):
    return "{} {} - {}\n\n{}\n".format(level, when(days_ago), title, "\n".join(lines))


def filler(count, start_day, topic):
    """Enough dated entries to push the note past WORKLOG_COMPACT_LINES (250)."""
    return "\n".join(
        entry(start_day + i * 3, "{} sync {}".format(topic, i + 1),
              ["- Point {} discussed and carried forward.".format(j + 1) for j in range(4)])
        for i in range(count)
    )


def write(rel, parts):
    (dest / rel).write_text("\n".join(parts))


write("People/Avery Sinclair.md", [
    "---",
    "type: person",
    "team: Platform & Reliability",
    'summary: "Director, PLATOPS"',
    "---",
    "",
    "# Avery Sinclair",
    "",
    "## Role (Workday, confirmed {})".format(today.strftime("%Y-%m-%d")),
    "",
    "Leader for the security organization. PLATOPS was dissolved on Jun 22, 2026 and",
    "PRA was renamed Infrastructure & Operations; this section is the current record.",
    "",
    "## 1:1 Doc",
    "",
    "https://example.com/1on1/astha",
    "",
    filler(46, 90, "Leadership"),
    entry(75, "Quarterly planning", [
        "- Reviewed the portfolio end to end.",
        "",
        "### Current Status",
        "",
        "- Nested under a dated entry, so it travels with that entry rather than",
        "  being promoted out as an independent current-state section.",
    ]),
])

write("People/Rachel Turner.md", [
    "---",
    "type: person",
    "team: Detection & Response",
    "compacted: {}".format((today - datetime.timedelta(days=93)).strftime("%Y-%m-%d")),
    "---",
    "",
    "# Rachel Turner",
    "",
    "## Context",
    "",
    "Engineering manager for detection tooling.",
    "",
    filler(44, 100, "Program"),
    "## Recent",
    "",
    entry(70, "Aged past the window since the last compaction",
          ["- Older than the keep window now; must move to History as a new bullet."]),
    entry(12, "Inside the keep window",
          ["- Recent enough to stay under Recent unchanged."]),
    "## History",
    "",
    "- Apr 2026: took over detection tooling and reset the roadmap. IMMUTABLE-MARKER-A",
    "- Mar 2026: onboarded two engineers onto the rotation. IMMUTABLE-MARKER-B",
    "",
])

write("People/Morgan Chambers.md", [
    "---",
    "type: person",
    "team: Detection & Response",
    "---",
    "",
    "# Morgan Chambers",
    "",
    "## Context",
    "",
    "Engineering manager.",
    "",
    filler(46, 95, "Coaching"),
    entry(80, "{} Coaching conversation 3:28-3:31 PM (vault-only)".format(LOCK), [
        "- Discussed the scope-management arc.",
        "",
        "### {} Eval User 3:30 PM (ULTRA-CONFIDENTIAL)".format(LOCK),
        "",
        "- Self-disclosure recorded under a stricter marker than its parent.",
    ]),
    entry(80, "{} Coaching conversation 3:34-3:35 PM (vault-only)".format(LOCK),
          ["- Same coaching arc, same day, but no stricter child beneath it."]),
])

# Laura: a single [[Chris Walden|Chris]] mention, buried once in an old section
# that is a fold candidate. Compressing that section without keeping the mention
# drops a link target, which is what the link gate exists to catch.
write("People/Chris Walden.md", [
    "---",
    "type: person",
    "team: Detection & Response",
    "---",
    "",
    "# Chris Walden",
    "",
    "## Role",
    "",
    "Engineering manager, 360-feedback reviewer.",
    "",
])

write("People/Laura Hensley.md", [
    "---",
    "type: person",
    "team: Platform Security",
    "---",
    "",
    "# Laura Hensley",
    "",
    "## Context",
    "",
    "Engineering manager on platform security.",
    "",
    filler(44, 100, "Workstream"),
    entry(96, "Active Workstreams", [
        "- Running the 360-feedback round for the team.",
        "- Backup reviewer for the 360 round is [[Chris Walden|Chris]], the only",
        "  mention of him anywhere in this note.",
        "- Remaining items carried forward.",
    ]),
])

write("People/Bryce Gale.md", [
    "---",
    "type: person",
    "team: CPE - Cloud Platform Engineering",
    "---",
    "",
    "# Bryce Gale",
    "",
    "## Role",
    "",
    "Staff engineer, technical lead on [[Platform Migration]].",
    "",
    filler(48, 90, "Migration"),
])
