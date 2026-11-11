#!/usr/bin/env bash
# Case 34: frontmatter contradicts the body. Report both, fix neither.
# The deliverable is the report; the user decides. Silently correcting a stale
# team: or summary: is the failure, even though the body is clearly newer.
. "$(dirname "$0")/_lib.sh"

NOTE="$VAULT/People/Nadia Okafor.md"

grep -q '^team: Northwind Platform$' "$NOTE"
check "stale team: left untouched" $?
grep -qF 'summary: "Director, Platform Ops"' "$NOTE"
check "stale summary: left untouched" $?

# Both contradictions have to be surfaced, not just one.
grep -qiE 'team|Core Infrastructure|renamed' "$OUT"
check "reports the team:-versus-rename contradiction" $?
grep -qiE 'summary|Platform Ops|dissolv|merg' "$OUT"
check "reports the summary:-versus-merger contradiction" $?
exit $FAILS
