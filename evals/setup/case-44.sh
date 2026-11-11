#!/usr/bin/env bash
# Case 44 needs a week file that looks like a real one after several rollovers:
# one item carrying far more dated sub-items than the retention rule keeps, and
# one item whose newest dated sub-item is well outside the dormancy window.
#
# make-vault's week file has at most one sub-item per item, so the retention
# rule has nothing to act on there and the case would pass trivially. Fatten it
# here instead of in make-vault, which every other case depends on staying small.
set -eu
VAULT="${1:?usage: case-44.sh <vault>}"
WEEK="$(python3 -c 'import datetime;y,w,_=datetime.date.today().isocalendar();print(f"{y}-W{w:02d}")')"
F="$VAULT/Worklogs/$WEEK.md"

# Dates are written relative to today so the case does not rot: the eight
# entries below land inside the last three weeks, and the dormant item's only
# dated line lands ~40 days back, outside WORKLOG_WEEK_DORMANT_DAYS (14).
python3 - "$F" <<'PY'
import datetime, re, sys

path = sys.argv[1]
today = datetime.date.today()
def d(days_ago):
    return (today - datetime.timedelta(days=days_ago)).strftime('%b %-d')

fat = ["- **P0** ⏳ In Progress - [[Platform Migration]] cutover plan with [[Theo Kask|Theo]]"]
# newest first is NOT assumed by the rule; interleave so "keep the newest N"
# cannot be satisfied by simply taking the first N lines.
for days, text in [
    (11, "Data-tier step still unwritten after the [[Priya Patel|Priya]] review"),
    (2,  "Cutover window agreed with [[Sarah Chen]] for the end of the month"),
    (19, "Rollback path drafted, [[Dev Sharma]] to sanity-check the restore timing"),
    (6,  "⚠️ __Action:__ [[Theo Kask|Theo]] still owes the data-tier runbook"),
    (16, "Dependency on the [[Cloud Security]] access review confirmed"),
    (9,  "Dry run scheduled, [[Nadia Okafor|Nadia]] asked for a written go/no-go"),
    (21, "Original scope split out of the [[Backend EM Hiring]] thread"),
    (13, "Comms plan circulated to the platform leads"),
]:
    fat.append(f"  - {text} ({d(days)})")

dormant = [
    "- **P2** ⏳ In Progress - Retire the legacy access-request form",
    f"  - No movement since the [[Cloud Security]] owner change ({d(40)})",
]

src = open(path, encoding='utf-8').read()
old = ("- **P0** ⏳ In Progress - [[Platform Migration]] cutover plan with "
       "[[Theo Kask|Theo]]\n"
       "  - Reviewed the rollback path, still missing the data-tier step")
assert old.split('\n')[0] in src, "fixture week file changed shape; update case-44 setup"
# replace the thin cutover item (title + its single sub-item) with the fat one
lines = src.split('\n')
i = lines.index(old.split('\n')[0])
j = i + 1
while j < len(lines) and lines[j].startswith('  '):
    j += 1
lines[i:j] = fat + dormant
open(path, 'w', encoding='utf-8').write('\n'.join(lines))
PY

git -C "$VAULT" add -A
git -C "$VAULT" -c user.name=eval -c user.email=eval@example.com \
    commit -q -m "fixture: week file with accumulated sub-items"
