#!/usr/bin/env bash
# make-vault.sh <dest> - generate a self-contained eval vault, dated relative to
# today so the current-week cases work on any run date. Never touches a real vault.
#
# Fixture invariants the assertions depend on:
#   - the current ISO week file already exists and is `status: active`
#   - three archived weeks exist, summary-bullets only (no priority markers)
#   - People/Alex* does NOT exist (case 1 must create the stub)
#   - "Brian" is a dominant alias: >=5 [[Brian Gaines|Brian]] vs 1 [[Brian Lee|Brian]]
#   - "Chris" is ambiguous: [[Chris Park|Chris]] and [[Chris Vincent|Chris]] tie
#   - Sources/ is empty, so the stale-channel nudge never fires
#   - the active week holds 6 top-level items, one of which is the Sarah Chen /
#     Dev Sharma leave item that case 6's notes are meant to fold into
set -euo pipefail

DEST="${1:?usage: make-vault.sh <dest> [--context-channel]}"
WITH_SOURCE=0
WITH_COMPACT=0
for arg in "$@"; do
  [ "$arg" = "--context-channel" ] && WITH_SOURCE=1
  [ "$arg" = "--compact-notes" ] && WITH_COMPACT=1
done
[ -e "$DEST" ] && { echo "make-vault: $DEST already exists" >&2; exit 1; }

eval "$(python3 - <<'PY'
import datetime
t = datetime.date.today()
y, w, _ = t.isocalendar()
mon = t - datetime.timedelta(days=t.isoweekday() - 1)
print(f'CUR="{y}-W{w:02d}"')
print(f'CUR_START="{mon}"')
print(f'CUR_END="{mon + datetime.timedelta(days=4)}"')
print(f'CUR_TITLE="{mon.strftime("%b %-d, %Y")}"')
for i in (1, 2, 3):
    p = mon - datetime.timedelta(weeks=i)
    py, pw, _ = p.isocalendar()
    print(f'PREV{i}="{py}-W{pw:02d}"')
    print(f'PREV{i}_START="{p}"')
    print(f'PREV{i}_TITLE="{p.strftime("%b %-d, %Y")}"')
print(f'MONTH="{t.strftime("%Y-%m")}"')
PY
)"

mkdir -p "$DEST"/{Worklogs,Archive,People,Programs,Teams,Summaries,Reports,Sources,Meetings,Logs,Preferences,Templates}

# --- current week: active, five items, mixed priorities and statuses ---
cat > "$DEST/Worklogs/$CUR.md" <<EOF
---
type: worklog
week: $CUR
date-start: $CUR_START
date-end: $CUR_END
status: active
prev: "[[$PREV1]]"
programs:
  - "[[Cloud Security]]"
  - "[[Platform Migration]]"
  - "[[Backend EM Hiring]]"
people:
  - "[[Sarah Chen]]"
  - "[[Brian Gaines]]"
  - "[[Astha Singhal]]"
tags:
  - hiring
  - strategy
  - people-management
item-count: 6
done-count: 1
---

# Week of $CUR_TITLE

**[[Cloud Security]] Strategy**

- **P0** ⏳ In Progress - [[Platform Migration]] cutover plan with [[Brian Gaines|Brian]]
  - Reviewed the rollback path, still missing the data-tier step ($(date +%b\ %-d))
- **P1** ⏳ In Progress - Quarterly risk narrative for [[Astha Singhal|Astha]]

**Hiring & People**

- **P0** ⏳ In Progress - [[Backend EM Hiring]] loop with [[Sarah Chen]]
  - Three onsites scheduled, debrief pending ($(date +%b\ %-d))
- **P0** ⏳ In Progress - Work with [[Sarah Chen]] on [[Dev Sharma]] leave coverage
- **P2** 🔁 Ongoing - Weekly 1:1s with [[Brian Gaines|Brian]] and [[Priya Patel|Priya]]

**Done**

- **P1** ✅ Done - Ship the [[Cloud Security]] access-review summary
EOF

# --- archive weeks: summary bullets only, no priority markers ---
for i in 1 2 3; do
  eval "wk=\$PREV$i; ws=\$PREV${i}_START; wt=\$PREV${i}_TITLE"
  cat > "$DEST/Archive/$wk.md" <<EOF
---
type: worklog
week: $wk
date-start: $ws
status: archived
---

# Week of $wt

## Summary

- Kept [[Platform Migration]] cutover on track with [[Brian Gaines|Brian]]
- Advanced [[Backend EM Hiring]] with [[Sarah Chen]]
- Reviewed [[Cloud Security]] posture with [[Astha Singhal|Astha]]

## Rolled Over

- [[Platform Migration]] cutover plan
- [[Backend EM Hiring]] loop
EOF
done

cat > "$DEST/Worklogs/Backlog.md" <<EOF
---
type: backlog
---

# Backlog

- **P1** ⏳ In Progress - Draft the [[Cloud Security]] exception process
- **P2** ⏳ In Progress - Refresh the [[Platform Migration]] runbook with [[Chris Park|Chris]]
- **P2** ⏳ In Progress - Team charter refresh with [[Chris Vincent|Chris]]
EOF

person() { # <name> <role> <extra-body>
  cat > "$DEST/People/$1.md" <<EOF
---
type: person
team: $2
---

# $1

## Role

$3

## Recent

- Active this quarter
EOF
}

person "Sarah Chen"      "Backend Platform"                 "Engineering manager, owns the [[Backend EM Hiring]] loop."
person "Brian Gaines"    "CIS - Cloud Infrastructure Security" "Staff engineer, technical lead on [[Platform Migration]]."
person "Brian Lee"       "Corp Engineering"                 "Program manager, occasional partner on facilities work."
person "Astha Singhal"   "Security Leadership"              "Leader, sponsor for [[Cloud Security]]."
person "Marcus Williams" "Edge Platform"                    "Engineer, owns the API rate limit proposal."
person "Chris Park"      "Platform Reliability"             "Engineer, runbook owner."
person "Chris Vincent"   "Detection & Response"             "Engineer, detection tooling."
person "Priya Patel"     "Backend Platform"                 "Engineer, migration workstream."
person "Dev Sharma"      "Backend Platform"                 "Engineer, out on leave."

program() {
  cat > "$DEST/Programs/$1.md" <<EOF
---
type: program
status: active
---

# $1

## Context

$2
EOF
}

program "Cloud Security"     "Org-wide cloud security posture work, sponsored by [[Astha Singhal|Astha]]."
program "Platform Migration" "Multi-quarter migration led by [[Brian Gaines|Brian]]."
program "Backend EM Hiring"  "Open backend engineering manager role, loop run with [[Sarah Chen]]."

cat > "$DEST/Teams/CIS - Cloud Infrastructure Security.md" <<EOF
---
type: team
---

# CIS - Cloud Infrastructure Security

## Members

- [[Brian Gaines]]
- [[Priya Patel]]

## Context

Owns cloud infrastructure security for the org.
EOF

# Dominance ballast: Brian Gaines reaches 6 observed uses of the "Brian" alias
# across the vault while Brian Lee stays at 1. Chris stays tied at 1 each above.
cat > "$DEST/Meetings/$CUR_START-migration-sync.md" <<EOF
---
type: meeting
date: $CUR_START
---

# Migration Sync

## Notes

- [[Brian Gaines|Brian]] walked the cutover sequence
- [[Brian Gaines|Brian]] flagged the data-tier gap
- [[Brian Gaines|Brian]] will own the rollback rehearsal
- [[Brian Lee|Brian]] joined for the facilities question only
EOF

cat > "$DEST/Logs/$MONTH.md" <<EOF
---
type: log
month: $MONTH
---

## [$PREV1_START] rollover | $PREV1
- archived $PREV1, opened $CUR
EOF

cat > "$DEST/Templates/Weekly.md" <<'EOF'
---
type: worklog
status: active
---

# Week of

**Subgroup**

- **P1** ⏳ In Progress - Item
EOF

: > "$DEST/Summaries/.gitkeep"
: > "$DEST/Reports/.gitkeep"
: > "$DEST/Sources/.gitkeep"

# Pull cases need a registered channel. Everything else leaves Sources empty so
# the stale-channel nudge never fires and never muddies an unrelated assertion.
if [ "$WITH_SOURCE" = "1" ]; then
  rm -f "$DEST/Sources/.gitkeep"
  cat > "$DEST/Sources/infrasec-leads.md" <<EOF
---
type: context-channel
channel_name: "#infrasec-leads"
channel_id: C0EVAL001
nudge_threshold_days: 5
last_scan_ts: null
first_scan_lookback_days: 7
---

# #infrasec-leads

Leads channel for the infrastructure security group. Swept for context that
belongs on tracked work, not for meeting notes.
EOF
fi
: > "$DEST/Preferences/.gitkeep"

# Compaction cases need notes that are genuinely oversized and structured the way
# the rules care about. Behind a flag so every other case keeps a small vault.
if [ "$WITH_COMPACT" = "1" ]; then
  python3 "$(dirname "$0")/fixtures/compact-notes.py" "$DEST"
fi

git -C "$DEST" init -q
git -C "$DEST" -c user.name="eval" -c user.email="eval@example.com" add -A
git -C "$DEST" -c user.name="eval" -c user.email="eval@example.com" commit -qm "fixture"
