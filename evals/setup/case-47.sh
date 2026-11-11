#!/usr/bin/env bash
# Case 47 needs a People note that gives /worklog cold every decision it has to make:
# two old unpinned entries (move), one old entry with an open Eval User action (pinned,
# stays), one recent entry (inside the window, stays) and a Role section (never moves).
#
# The case passes the note by name: the scanner lists only notes with 4 KB or more movable,
# and this fixture is deliberately small, so a no-argument run would find no candidate.
#
# Dates are relative to today so the case does not rot: 120 and 100 days back are past
# the 60-day People window, 90 days back is past it too but pinned, 10 days back is inside.
set -eu
VAULT="${1:?usage: case-47.sh <vault>}"

python3 - "$VAULT/People/Dana Whitfield.md" <<'PY'
import datetime, sys

today = datetime.date.today()
def d(days_ago):
    return (today - datetime.timedelta(days=days_ago)).strftime('%b %-d, %Y')

note = f"""---
type: person
team: Unknown
summary: "Vendor-risk lead on the access review; works with Sarah Chen"
---
# Dana Whitfield

## Role
- Vendor-risk lead, partners closely with [[Sarah Chen]] on the [[Cloud Security]] access review

## {d(120)} - Vendor onboarding sync
Walked through the intake form with [[Sarah Chen]]. Agreed the questionnaire goes out before contract signature.
- Intake form owner: Dana
- Questionnaire template lives with [[Cloud Security]]

## {d(100)} - Access review kickoff
Dana scoped the first pass to production systems. [[Platform Migration]] stays out until cutover completes.
- Scope doc shared with the team

## {d(90)} - Leveling follow-up
Dana asked how the L5 bar is applied to vendor-risk work.
- __Action on Eval User__: send Dana the leveling doc and the examples folder

## {d(10)} - Quarterly check-in
Dana is on track with the access review. No blockers.
"""
open(sys.argv[1], 'w', encoding='utf-8').write(note)
PY

git -C "$VAULT" add -A
git -C "$VAULT" -c user.name=eval -c user.email=eval@example.com \
    commit -q -m "fixture: cold note"
