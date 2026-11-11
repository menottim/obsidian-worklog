#!/usr/bin/env bash
# cold-gate.sh <vault> <note-relpath> <cold-relpath>... - check that a cold-storage move was lossless.
# Read-only. Base revision is git HEAD of the vault (env WORKLOG_COLD_BASE overrides).
# PASS only when all of these are true:
#   - The note frontmatter is unchanged.
#   - Every non-blank base body line survives in (current note body + cold file bodies) with at
#     least the same count. Base lines come from the note and from any cold file that already
#     existed at base.
#   - Existing cold files keep their base lines and their non-entries/moved frontmatter.
#   - Every wiki-link target survives.
#   - Every cold file is linked from the note's ## Cold storage section and has
#     parent: [[<note stem>]] or [[<note path>]] (quoted or not, alias ok).
# Exit 0 on PASS, 1 on FAIL, 2 on usage error.
# ponytail: checks line multisets, not order or section structure.
# ponytail: link scan drops fenced code, inline backticks, HTML comments and embeds, but it is
# line-based awk, not a markdown parser (a backtick span crossing lines is missed).
# bash 3.2; coreutils + git.
set -uo pipefail

[ "$#" -ge 3 ] || { echo "cold-gate: usage: cold-gate.sh <vault> <note-relpath> <cold-relpath>..." >&2; exit 2; }
VAULT="$1"; NOTE="$2"; shift 2
[ -d "$VAULT" ] || { echo "cold-gate: vault dir not found: $VAULT" >&2; exit 2; }
BASE="${WORKLOG_COLD_BASE:-HEAD}"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILS="$T/fails"; : > "$FAILS"
fail() { printf '  - %s\n' "$1" >> "$FAILS"; }

clean() { tr -d '\r'; }
fm()   { awk 'NR==1 && $0!="---"{exit} {print} NR>1 && $0=="---"{exit}'; }          # frontmatter incl. fences
body() { awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{f=0; next} !f{print}'; }  # everything else
rstrip() { sed 's/[[:space:]]*$//'; }
targets() { grep -o '\[\[[^]]*\]\]' | sed 's/^\[\[//; s/\]\]$//; s/|.*//; s/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/\.md$//' | sort -u; }
# multiset deficit: non-blank lines of $1 whose running count exceeds their count in $2
deficit() { awk 'NR==FNR{c[$0]++; next} $0!=""{n[$0]++; if(n[$0]>c[$0]) print}' "$2" "$1"; }
# the "## Cold storage" section with code fences, HTML comments, inline code and embeds removed
cold_section() { awk '
  /^```/{fen=!fen; next} fen{next}
  /^## /{ins=($0 ~ /^## Cold storage[ \t]*$/); next}
  !ins{next}
  { line=$0; out=""
    while(line!=""){
      if(inc){p=index(line,"-->"); if(!p){line=""; break} line=substr(line,p+3); inc=0}
      else {p=index(line,"<!--"); if(!p){out=out line; line=""} else {out=out substr(line,1,p-1); line=substr(line,p+4); inc=1}}
    }
    gsub(/`[^`]*`/,"",out); gsub(/!\[\[[^]]*\]\]/,"",out); print out }'; }

# strip a leading ./ from cold args
NARGS=0
for c in "$@"; do
  NARGS=$((NARGS + 1)); eval "A$NARGS=\"\${c#./}\""
done
set --; i=0
while [ "$i" -lt "$NARGS" ]; do i=$((i + 1)); eval "set -- \"\$@\" \"\$A$i\""; done
STEM="$(basename "$NOTE" .md)"

if ! git -C "$VAULT" show "$BASE:$NOTE" > "$T/base_raw" 2>/dev/null; then
  printf 'FAIL %s: not present in base revision %s (cannot verify a move)\n' "$NOTE" "$BASE"
  exit 1
fi
if [ ! -f "$VAULT/$NOTE" ]; then
  printf 'FAIL %s: note missing from working tree\n' "$NOTE"; exit 1
fi
clean < "$T/base_raw" > "$T/base"; clean < "$VAULT/$NOTE" > "$T/cur"

fm < "$T/base" > "$T/fm_b"; fm < "$T/cur" > "$T/fm_a"
body < "$T/base" | rstrip > "$T/body_b"; body < "$T/cur" | rstrip > "$T/body_a"
cmp -s "$T/fm_b" "$T/fm_a" || fail "note frontmatter changed"

cp "$T/body_a" "$T/union"; cp "$T/body_b" "$T/basebody"
i=0
for c in "$@"; do
  i=$((i + 1))
  if [ ! -f "$VAULT/$c" ]; then fail "cold file not found: $c"; continue; fi
  clean < "$VAULT/$c" > "$T/c$i"
  body < "$T/c$i" | rstrip >> "$T/union"
  pv="$(fm < "$T/c$i" | grep '^parent:' | head -1 | sed 's/^parent:[[:space:]]*//; s/[[:space:]]*$//')"
  pq="${pv#\"}"; pq="${pq%\"}"; pq="$(printf '%s' "$pq" | sed 's/|[^]]*\]\]$/]]/')"   # drop quotes and alias
  case "$pq" in
    "[[$STEM]]"|"[[${NOTE%.md}]]") ;;
    "") fail "cold file has no parent: $c" ;;
    *) fail "cold file parent is not [[$STEM]]: $c (got $pv)" ;;
  esac
  if git -C "$VAULT" show "$BASE:$c" > "$T/cb_raw" 2>/dev/null; then
    clean < "$T/cb_raw" > "$T/cb$i"
    body < "$T/cb$i" | rstrip > "$T/cbb$i"; body < "$T/c$i" | rstrip > "$T/cbn$i"
    cat "$T/cbb$i" >> "$T/basebody"
    deficit "$T/cbb$i" "$T/cbn$i" > "$T/cl$i"
    [ ! -s "$T/cl$i" ] || fail "existing cold file lost $(wc -l < "$T/cl$i" | tr -d ' ') base lines: $c"
    fm < "$T/cb$i" | grep -v -e '^entries:' -e '^moved:' > "$T/cfb$i"
    fm < "$T/c$i"  | grep -v -e '^entries:' -e '^moved:' > "$T/cfn$i"
    cmp -s "$T/cfb$i" "$T/cfn$i" || fail "existing cold file frontmatter changed: $c"
  fi
done
if cmp -s "$T/base" "$T/cur"; then
  fail "note unchanged from base $BASE: nothing to verify; if the move is already committed, set WORKLOG_COLD_BASE to the pre-move revision"
fi

deficit "$T/basebody" "$T/union" > "$T/lost"
NLOST="$(wc -l < "$T/lost" | tr -d ' ')"
if [ "$NLOST" -gt 0 ]; then
  fail "$NLOST lines not found verbatim: $(head -5 "$T/lost" | sed 's/^[[:space:]]*//' | cut -c1-90 | paste -sd '|' - | sed 's/|/ || /g')"
fi

targets < "$T/body_b" > "$T/lk_b"; targets < "$T/union" > "$T/lk_u"
cold_section < "$T/body_a" | targets > "$T/lk_a"
LOSTLK="$(comm -23 "$T/lk_b" "$T/lk_u" | paste -sd ',' - | sed 's/,/, /g')"
[ -z "$LOSTLK" ] || fail "link targets lost: $LOSTLK"

for c in "$@"; do
  stem="${c%.md}"
  grep -Fxq -- "$stem" "$T/lk_a" || fail "cold file not linked from note: $c"
done

SB="$(wc -c < "$T/base" | tr -d ' ')"; SA="$(wc -c < "$T/cur" | tr -d ' ')"
if [ "$SB" -gt 0 ]; then PCT=$(( 100 * (SB - SA) / SB )); else PCT=0; fi
if [ -s "$FAILS" ]; then V=FAIL; else V=PASS; fi
printf '%s %s: warm %s -> %s bytes (%s%% moved to cold); cold files: %s\n' "$V" "$NOTE" "$SB" "$SA" "$PCT" "$#"
cat "$FAILS"
[ "$V" = PASS ]
