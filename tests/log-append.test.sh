#!/usr/bin/env bash
# Unit tests for log-append.sh. Each case runs against a throwaway vault.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="$HERE/../skills/worklog/scripts/log-append.sh"
FAILS=0

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

MONTH="$(date +%Y-%m)"
DAY="$(date +%Y-%m-%d)"

# --- creates the month file with frontmatter ---
V="$(mktemp -d)"
"$HELPER" "$V" pull '#platform-leads' '24 messages swept' >/dev/null
LOG="$V/Logs/$MONTH.md"
assert_eq "month file created"   "$([ -f "$LOG" ] && echo yes)" "yes"
assert_eq "frontmatter type"     "$(sed -n '2p' "$LOG")" "type: log"
assert_eq "frontmatter month"    "$(sed -n '3p' "$LOG")" "month: $MONTH"
assert_eq "entry prefix"         "$(grep -c "^## \[$DAY\] pull | #platform-leads$" "$LOG")" "1"
assert_eq "body line"            "$(grep -c '^- 24 messages swept$' "$LOG")" "1"

# --- appends without duplicating frontmatter ---
"$HELPER" "$V" compact 'People/Nadia Okafor.md' '852 -> 210 lines' 'links preserved: 34/34' >/dev/null
assert_eq "one frontmatter block" "$(grep -c '^type: log$' "$LOG")" "1"
assert_eq "two entries"           "$(grep -c '^## \[' "$LOG")" "2"
assert_eq "multi body line 1"     "$(grep -c '^- 852 -> 210 lines$' "$LOG")" "1"
assert_eq "multi body line 2"     "$(grep -c '^- links preserved: 34/34$' "$LOG")" "1"
assert_eq "body order preserved"  \
  "$(grep -n '^- 852\|^- links' "$LOG" | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//' | awk '{print ($1 < $2) ? "ok" : "wrong"}')" "ok"

# --- greppable prefix contract ---
assert_eq "prefix grep works"     "$(cat "$V"/Logs/*.md | grep -c '^## \[')" "2"
rm -rf "$V"

# --- entry with no body lines ---
V2="$(mktemp -d)"
"$HELPER" "$V2" sync vault >/dev/null
assert_eq "no-body entry"         "$(grep -c "^## \[$DAY\] sync | vault$" "$V2/Logs/$MONTH.md")" "1"
rm -rf "$V2"

# --- exit codes ---
"$HELPER" >/dev/null 2>&1;               assert_eq "no-arg exit 2"      "$?" "2"
"$HELPER" /tmp pull >/dev/null 2>&1;     assert_eq "two-arg exit 2"     "$?" "2"
"$HELPER" /no/such/vault a b >/dev/null 2>&1; assert_eq "bad-vault exit 2" "$?" "2"

RO="$(mktemp -d)"; chmod 555 "$RO"
"$HELPER" "$RO" pull x >/dev/null 2>&1;  assert_eq "unwritable exit 2"  "$?" "2"
chmod 755 "$RO"; rm -rf "$RO"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'
