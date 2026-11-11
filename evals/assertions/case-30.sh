#!/usr/bin/env bash
# Case 30: /worklog rollup. Clipboard copy carries no wiki-link syntax; the filed
# copy keeps its links so the rollup lands in the graph. Both renderings obey the
# same audience filter.
#
# This is also the guard for progressive disclosure: the rollup rules now live in
# references/rollup.md, so a run that ignores the stub and works from memory
# shows up here. Unlike a month summary, rollup always has material - it targets
# the current week - so it does not shift with the calendar.
. "$(dirname "$0")/_lib.sh"

REF="$(ls "$VAULT"/References/*Rollup*.md 2>/dev/null | head -1)"
[ -n "$REF" ]; check "a References rollup note was filed" $?
if [ -z "$REF" ]; then exit $FAILS; fi

grep -qE '^type: *reference' "$REF"; check "frontmatter declares type: reference" $?
grep -qE '^subtype: *rollup' "$REF"; check "frontmatter declares subtype: rollup" $?
grep -qE '^period:' "$REF"; check "frontmatter carries a period" $?
grep -qF '[[' "$REF"; check "filed copy KEEPS wiki-links (lands in the graph)" $?

# Content has to come from the week, not be invented.
HITS=0
for t in 'Platform Migration' 'Backend EM Hiring' 'Cloud Security'; do
  grep -qiF "$t" "$REF" && HITS=$((HITS + 1))
done
[ "$HITS" -ge 2 ]; check "rollup draws on the week's real programs (got $HITS of 3)" $?

# Audience filter: 1:1 content and per-person coaching stay out of a rollup.
! grep -qiE '1:1|one.on.one' "$REF"; check "no 1:1 specifics in the filed rollup" $?
grep -rqE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] rollup \|' "$VAULT"/Logs/*.md; check "ops log has a rollup entry" $?
exit $FAILS
