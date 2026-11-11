#!/usr/bin/env bash
# make-vault.sh <dest> - generate a self-contained eval vault, dated relative to
# today so the current-week cases work on any run date. Never touches a real vault.
#
# Fixture invariants the assertions depend on:
#   - the current ISO week file already exists and is `status: active`
#   - three archived weeks exist, summary-bullets only (no priority markers)
#   - People/Alex* does NOT exist (case 1 must create the stub)
#   - "Bryce" is a dominant alias: >=5 [[Bryce Gale|Bryce]] vs 1 [[Bryce Lee|Bryce]]
#   - "Chris" is ambiguous: [[Chris Park|Chris]] and [[Chris Vance|Chris]] tie
#   - Sources/ is empty, so the stale-channel nudge never fires
#   - the active week holds 6 top-level items, one of which is the Sarah Chen /
#     Dev Sharma leave item that case 6's notes are meant to fold into
set -euo pipefail

DEST="${1:?usage: make-vault.sh <dest> [--context-channel]}"
WITH_SOURCE=0
WITH_COMPACT=0
WITH_DMS=0
# Auto sync note: default writes auto_sync: off. --auto-sync-on writes on. --no-auto-sync-note
# writes no note. Both on and no-note also give the vault a local bare origin, so sync.sh can push.
AUTO_SYNC_VALUE=off
WITH_REMOTE=0
for arg in "$@"; do
  [ "$arg" = "--context-channel" ] && WITH_SOURCE=1
  [ "$arg" = "--compact-notes" ] && WITH_COMPACT=1
  [ "$arg" = "--dm-source" ] && WITH_DMS=1
  [ "$arg" = "--auto-sync-on" ] && { AUTO_SYNC_VALUE=on; WITH_REMOTE=1; }
  [ "$arg" = "--no-auto-sync-note" ] && { AUTO_SYNC_VALUE=none; WITH_REMOTE=1; }
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

mkdir -p "$DEST"/{Worklogs,Archive,People,Programs,Threads,Teams,Summaries,Reports,References,Sources,Meetings,Logs,Preferences,Templates}

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
  - "[[Bryce Gale]]"
  - "[[Avery Sinclair]]"
tags:
  - hiring
  - strategy
  - people-management
item-count: 6
done-count: 1
---

# Week of $CUR_TITLE

**[[Cloud Security]] Strategy**

- **P0** ⏳ In Progress - [[Platform Migration]] cutover plan with [[Bryce Gale|Bryce]]
  - Reviewed the rollback path, still missing the data-tier step ($(date +%b\ %-d))
- **P1** ⏳ In Progress - Quarterly risk narrative for [[Avery Sinclair|Avery]]

**Hiring & People**

- **P0** ⏳ In Progress - [[Backend EM Hiring]] loop with [[Sarah Chen]]
  - Three onsites scheduled, debrief pending ($(date +%b\ %-d))
- **P0** ⏳ In Progress - Work with [[Sarah Chen]] on [[Dev Sharma]] leave coverage
- **P2** 🔁 Ongoing - Weekly 1:1s with [[Bryce Gale|Bryce]] and [[Priya Patel|Priya]]

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

- Kept [[Platform Migration]] cutover on track with [[Bryce Gale|Bryce]]
- Advanced [[Backend EM Hiring]] with [[Sarah Chen]]
- Reviewed [[Cloud Security]] posture with [[Avery Sinclair|Avery]]

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
- **P2** ⏳ In Progress - Team charter refresh with [[Chris Vance|Chris]]
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
person "Bryce Gale"    "CPE - Cloud Platform Engineering" "Staff engineer, technical lead on [[Platform Migration]]."
person "Bryce Lee"       "Corp Engineering"                 "Program manager, occasional partner on facilities work."
person "Avery Sinclair"   "Security Leadership"              "Leader, sponsor for [[Cloud Security]]."
person "Marcus Williams" "Edge Platform"                    "Engineer, owns the API rate limit proposal."
person "Chris Park"      "Platform Reliability"             "Engineer, runbook owner."
person "Chris Vance"   "Detection & Response"             "Engineer, detection tooling."
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

program "Cloud Security"     "Org-wide cloud security posture work, sponsored by [[Avery Sinclair|Avery]]."
program "Platform Migration" "Multi-quarter migration led by [[Bryce Gale|Bryce]]."
program "Backend EM Hiring"  "Open backend engineering manager role, loop run with [[Sarah Chen]]."

cat > "$DEST/Teams/CPE - Cloud Platform Engineering.md" <<EOF
---
type: team
---

# CPE - Cloud Platform Engineering

## Members

- [[Bryce Gale]]
- [[Priya Patel]]

## Context

Owns cloud infrastructure security for the org.
EOF

# Dominance ballast: Bryce Gale reaches 6 observed uses of the "Bryce" alias
# across the vault while Bryce Lee stays at 1. Chris stays tied at 1 each above.
cat > "$DEST/Meetings/$CUR_START-migration-sync.md" <<EOF
---
type: meeting
date: $CUR_START
---

# Migration Sync

## Notes

- [[Bryce Gale|Bryce]] walked the cutover sequence
- [[Bryce Gale|Bryce]] flagged the data-tier gap
- [[Bryce Gale|Bryce]] will own the rollback rehearsal
- [[Bryce Lee|Bryce]] joined for the facilities question only
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
  cat > "$DEST/Sources/platform-leads.md" <<EOF
---
type: context-channel
channel_name: "#platform-leads"
channel_id: C0EVAL001
nudge_threshold_days: 5
last_scan_ts: null
first_scan_lookback_days: 7
---

# #platform-leads

Leads channel for the infrastructure security group. Swept for context that
belongs on tracked work, not for meeting notes.
EOF
fi
: > "$DEST/Preferences/.gitkeep"

# The DM sweep only runs when Sources/_dms.md exists and is enabled.
if [ "$WITH_DMS" = "1" ]; then
  cat > "$DEST/Sources/_dms.md" <<EOF
---
type: dm-sweep
enabled: true
include_1on1: true
include_groups: true
query: ""
max_results: 100
nudge_threshold_days: 5
last_scan_ts: null
first_scan_lookback_days: 3
exclude_users: []
exclude_conversations: []
---

# Direct Messages

Approval-only sweep of 1:1 and group DMs. Nothing folds automatically.
EOF
fi

# Compaction cases need notes that are genuinely oversized and structured the way
# the rules care about. Behind a flag so every other case keeps a small vault.
if [ "$WITH_COMPACT" = "1" ]; then
  python3 "$(dirname "$0")/fixtures/compact-notes.py" "$DEST"
fi

# Auto sync note goes in before the fixture commit, through the skill's own script so the
# format matches what /worklog writes.
if [ "$AUTO_SYNC_VALUE" != none ]; then
  "$(dirname "$0")/../skills/worklog/scripts/auto-sync.sh" "$DEST" set "$AUTO_SYNC_VALUE" setup
fi

git -C "$DEST" init -q
git -C "$DEST" -c user.name="eval" -c user.email="eval@example.com" add -A
git -C "$DEST" -c user.name="eval" -c user.email="eval@example.com" commit -qm "fixture"

# Local bare origin at <dest>.remote.git, pushed once so both sides start at the same HEAD.
# An absolute path keeps sync.sh's local-remote guard satisfied.
if [ "$WITH_REMOTE" = "1" ]; then
  ABS_DEST="$(cd "$DEST" && pwd -P)"
  REMOTE="$ABS_DEST.remote.git"
  git init -q --bare "$REMOTE"
  BRANCH="$(git -C "$DEST" symbolic-ref --short HEAD)"
  git --git-dir="$REMOTE" symbolic-ref HEAD "refs/heads/$BRANCH"
  git -C "$DEST" remote add origin "$REMOTE"
  git -C "$DEST" push -q origin HEAD
fi
