# Shared assertion helpers. Sourced by case-N.sh, which the runner invokes with
# VAULT, OUT, DIFF and CHANGED in the environment.
#
# Every check prints one PASS or FAIL line; the script exits with the failure
# count. Checks here are deterministic on purpose: no judge model is needed to
# know whether a second week file appeared.
FAILS=0
ok()  { printf 'PASS: %s\n' "$1"; }
no()  { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }
check() { # <desc> <condition-exit-code-already-run>
  if [ "$2" -eq 0 ]; then ok "$1"; else no "$1"; fi
}

CUR_WEEK="$(python3 -c 'import datetime;y,w,_=datetime.date.today().isocalendar();print(f"{y}-W{w:02d}")')"
WEEK_FILE="$VAULT/Worklogs/$CUR_WEEK.md"

week_files()   { ls "$VAULT"/Worklogs/*-W*.md 2>/dev/null | wc -l | tr -d ' '; }
changed_in()   { grep -qE "	$1" "$CHANGED"; }   # <path-prefix-regex>
changed_count(){ grep -c . "$CHANGED"; }
