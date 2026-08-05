#!/usr/bin/env bash
# cross-link-index.sh <vault> - emit an entity/alias digest (JSON) for the worklog
# cross-linking flow. Read-only; computes fresh each call (no persisted index).
# bash 3.2; jq/awk/sed/grep. Precedence: declared > observed > derived.
set -euo pipefail

WITH_SUMMARIES=0
VAULT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-summaries) WITH_SUMMARIES=1 ;;
    -*) echo "cross-link-index: unknown option: $1" >&2; exit 2 ;;
    *)  [ -n "$VAULT" ] || VAULT="$1" ;;
  esac
  shift
done
[ -n "$VAULT" ] || { echo "usage: cross-link-index.sh <vault-path> [--with-summaries]" >&2; exit 2; }
[ -d "$VAULT" ] || { echo "cross-link-index: vault dir not found: $VAULT" >&2; exit 2; }
cd "$VAULT"

DOM_RATIO="${CROSSLINK_DOM_RATIO:-3}"   # top observed count must be >= ratio * runner-up
DOM_ABS="${CROSSLINK_DOM_ABS:-5}"       # AND top must be >= this absolute count

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ENTS="$TMP/ents.tsv"      # canonical \t type
TUP="$TMP/tuples.tsv"     # surface \t canonical \t source(canonical|derived|declared|observed)
OBS="$TMP/observed.tsv"   # surface \t canonical \t count
NAMES="$TMP/names"        # one canonical per line
: > "$ENTS"; : > "$TUP"; : > "$OBS"
SUMS="$TMP/sums.tsv"      # canonical \t source \t summary
: > "$SUMS"
shopt -s nullglob

# --- Summary extraction (only used with --with-summaries) ---
# Declared: a frontmatter `summary:` line. Wins outright.
summary_declared(){ # <file>
  awk 'BEGIN{fm=0}
       /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
       fm==1 && /^summary:/{ s=$0; sub(/^summary:[[:space:]]*/,"",s)
                             gsub(/^["'\'']|["'\'']$/,"",s); print s; exit }' "$1"
}
# Derived: first body bullet after the frontmatter. Never reads frontmatter list items.
summary_derived(){ # <file>
  awk 'BEGIN{fm=0}
       /^---[[:space:]]*$/{fm++; next}
       (fm==0 || fm>=2) && /^[[:space:]]*-[[:space:]]+/{
         s=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",s); print s; exit }' "$1" | cut -c1-120
}

# --- Stage 1: entities (canonical + type) ---
for dir in People Programs; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    name="$(basename "$f" .md)"
    type="$(sed -n 's/^type:[[:space:]]*//p' "$f" | head -1 | tr -d '"' | tr -d "'")"
    [ -n "$type" ] || { case "$dir" in People) type=person;; Programs) type=program;; esac; }
    printf '%s\t%s\n' "$name" "$type" >> "$ENTS"
    if [ "$WITH_SUMMARIES" = "1" ]; then
      s="$(summary_declared "$f")"; src="declared"
      if [ -z "$s" ]; then s="$(summary_derived "$f")"; src="derived"; fi
      [ -n "$s" ] || src="none"
      s="$(printf '%s' "$s" | tr -d '\t')"     # protect the TSV separator
      printf '%s\t%s\t%s\n' "$name" "$src" "$s" >> "$SUMS"
    fi
  done
done
cut -f1 "$ENTS" | sort -u > "$NAMES"

# --- Stage 2: canonical + derived tuples ---
while IFS="$(printf '\t')" read -r name type; do
  [ -n "$name" ] || continue
  printf '%s\t%s\tcanonical\n' "$name" "$name" >> "$TUP"
  if [ "$type" = "person" ]; then
    first="${name%% *}"
    [ "$first" != "$name" ] && printf '%s\t%s\tderived\n' "$first" "$name" >> "$TUP"
  fi
done < "$ENTS"
# --- Stage 3: declared tuples (frontmatter aliases: list or inline [a, b]) ---
for dir in People Programs; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    name="$(basename "$f" .md)"
    awk '
      BEGIN{fm=0; ina=0}
      /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
      fm==1 && /^aliases:/{
        rest=$0; sub(/^aliases:[[:space:]]*/,"",rest)
        if (rest ~ /^\[/) {                         # inline: aliases: [A, B]
          gsub(/[][]/,"",rest); m=split(rest,a,",")
          for (i=1;i<=m;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",a[i]); if(a[i]!="") print a[i] }
          ina=0
        } else ina=1
        next
      }
      fm==1 && ina && /^[[:space:]]+-[[:space:]]*/{ item=$0; sub(/^[[:space:]]+-[[:space:]]*/,"",item); print item; next }
      fm==1 && ina && /^[^[:space:]]/{ ina=0 }
    ' "$f" | sed -e 's/^["'\'']//' -e 's/["'\'']$//' | while IFS= read -r al; do
      [ -n "$al" ] && printf '%s\t%s\tdeclared\n' "$al" "$name" >> "$TUP"
    done
  done
done
# --- Stage 4: observed tuples + counts (mine [[Canonical|alias]]) ---
# Mine [[Canonical|alias]] from markdown only; tolerate grep's no-match (exit 1) but NOT real errors (exit 2).
grep -rhoE --include='*.md' '\[\[[^]]+\|[^]]+\]\]' . > "$TMP/obs.raw" 2>/dev/null || [ $? -eq 1 ]
sed -E 's/^\[\[//; s/\]\]$//' "$TMP/obs.raw" \
  | awk -F'|' 'NF>=2 { canon=$1; alias=$2; cnt[alias "\t" canon]++ }
               END { for (k in cnt) print k "\t" cnt[k] }' \
  > "$TMP/obs.all"
while IFS="$(printf '\t')" read -r alias canon cnt; do
  [ -n "$alias" ] && [ -n "$canon" ] || continue
  grep -Fxq "$canon" "$NAMES" || continue          # only links to existing People/Programs
  printf '%s\t%s\tobserved\n' "$alias" "$canon" >> "$TUP"
  printf '%s\t%s\t%s\n' "$alias" "$canon" "$cnt"  >> "$OBS"
done < "$TMP/obs.all"

# --- Reducer: group tuples by surface form, resolve collisions ---
REDUCE="$TMP/reduced.tsv"   # "R" canonical surface dominant(0|1) alts(\x1f-joined)  |  "A" surface candidate
awk -F'\t' -v DOM_RATIO="$DOM_RATIO" -v DOM_ABS="$DOM_ABS" '
  FNR==NR {
    s=$1; c=$2; src=$3; key=s SUBSEP c
    if (!(key in seen)) { seen[key]=1; cand[s]=cand[s] (cand[s]==""?"":"\037") c; ncand[s]++ }
    if (src=="canonical") iscanon[s]=1
    if (src=="declared")  { decl[key]=1; ndecl[s]++; declc[s]=c }
    next
  }
  { cnt[$1 SUBSEP $2]=$3+0 }
  END{
    OFS="\t"
    for (s in cand) {
      if ((s in iscanon) && ncand[s] <= 1) continue       # pure canonical, not an alias
      n=split(cand[s], arr, "\037")
      if (ndecl[s] >= 1) {                                 # declared wins outright
        if (ndecl[s] == 1) { print "R", declc[s], s, 0, ""; continue }
        for (i=1;i<=n;i++) if ((s SUBSEP arr[i]) in decl) print "A", s, arr[i]
        continue
      }
      if (n == 1) { print "R", arr[1], s, 0, ""; continue } # unambiguous
      topc=""; topn=-1; secn=0                              # dominance by observed count
      for (i=1;i<=n;i++) {
        v=cnt[s SUBSEP arr[i]] + 0
        if (v > topn) { secn=(topn<0?0:topn); topc=arr[i]; topn=v }
        else if (v > secn) secn=v
      }
      if (topn >= DOM_ABS && topn >= DOM_RATIO * secn) {
        alts=""
        for (i=1;i<=n;i++) if (arr[i] != topc) alts=alts (alts==""?"":"\037") arr[i]
        print "R", topc, s, 1, alts
      } else {
        for (i=1;i<=n;i++) print "A", s, arr[i]
      }
    }
  }
' "$TUP" "$OBS" > "$REDUCE"

# --- Assembly: build final JSON via jq (jq handles all string escaping) ---
# alts uses split("") -- 0x1f unit separator byte (invisible in editors); matches awk \037 join above -- do not "correct" to ""
RJSON="$({ grep '^R' "$REDUCE" || true; } | jq -R -s '
  split("\n") | map(select(length>0) | split("\t"))
  | map({canonical: .[1], alias: .[2], dominant: (.[3]=="1"),
         alts: (if (.[4]|length)>0 then (.[4]|split("")) else [] end)})')"
AJSON="$({ grep '^A' "$REDUCE" || true; } | jq -R -s '
  split("\n") | map(select(length>0) | split("\t"))
  | reduce .[] as $r ({}; .[$r[1]] += [$r[2]]) | map_values(sort)')"
ENTJSON="$(jq -R -s '
  split("\n") | map(select(length>0) | split("\t"))
  | map({canonical: .[0], type: .[1]})' "$ENTS")"

SUMJSON='{}'
if [ "$WITH_SUMMARIES" = "1" ]; then
  SUMJSON="$(jq -R -s '
    split("\n") | map(select(length>0) | split("\t"))
    | reduce .[] as $r ({}; .[$r[0]] = {summary: ($r[2] // ""), summary_source: $r[1]})' "$SUMS")"
fi

PEOPLE="$(awk -F'\t' '$2=="person"{n++} END{print n+0}' "$ENTS")"
PROGRAMS="$(awk -F'\t' '$2=="program"{n++} END{print n+0}' "$ENTS")"

jq -n \
  --argjson ents "$ENTJSON" \
  --argjson r "$RJSON" \
  --argjson ambiguous "$AJSON" \
  --argjson people "$PEOPLE" \
  --argjson programs "$PROGRAMS" \
  --argjson sums "$SUMJSON" \
  --argjson withsum "$WITH_SUMMARIES" \
  --arg vault "$VAULT" '
  {
    entities: ($ents | map(. as $e
      | ($r | map(select(.canonical == $e.canonical))) as $mine
      | $e + { aliases: ($mine | map(.alias) | unique),
               alias_notes: ($mine | map(select(.dominant)) | map({alias, alts})) }
      | if (.alias_notes | length) == 0 then del(.alias_notes) else . end
      | if $withsum == 1
        then . + ($sums[.canonical] // {summary: "", summary_source: "none"})
        else . end)),
    ambiguous: $ambiguous,
    meta: { people: $people, programs: $programs, generated_for: $vault }
  }'
