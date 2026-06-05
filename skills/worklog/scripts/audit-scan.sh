#!/usr/bin/env bash
# audit-scan.sh <vault> — compute the six /worklog audit checks; emit JSON findings to stdout.
# Read-only. Scans the vault in bash so the model never loads People/Programs bodies.
# Checks mirror the definitions in SKILL.md's `/worklog audit` section exactly.
set -euo pipefail

VAULT="${1:?usage: audit-scan.sh <vault-path>}"
[ -d "$VAULT" ] || { echo "audit-scan: vault dir not found: $VAULT" >&2; exit 2; }
cd "$VAULT"

# The 4 most recent weekly files (YYYY-WNN.md) across Worklogs + Archive.
# Use while-read loop instead of mapfile for bash 3.2 compatibility (macOS default bash).
RECENT_BN=()
while IFS= read -r b; do
  RECENT_BN+=("$b")
done < <(
  { ls Worklogs 2>/dev/null; ls Archive 2>/dev/null; } \
    | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -u -r | head -4
)
RECENT=()
for b in "${RECENT_BN[@]:-}"; do
  [ -n "$b" ] || continue
  [ -f "Worklogs/$b" ] && RECENT+=("Worklogs/$b")
  [ -f "Archive/$b" ]  && RECENT+=("Archive/$b")
done
BACKLOG="Worklogs/Backlog.md"
ACTIVE="$(ls Worklogs 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -r | head -1)"
ACTIVE="Worklogs/${ACTIVE}"

emit_array(){ jq -s '.'; }

stale_people(){
  shopt -s nullglob
  for f in People/*.md; do
    name="$(basename "$f" .md)"
    if ! grep -Fq "[[$name" "${RECENT[@]:-/dev/null}" "$BACKLOG" 2>/dev/null; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

orphan_programs(){
  shopt -s nullglob
  for f in Programs/*.md; do
    name="$(basename "$f" .md)"
    if ! grep -Fq "[[$name" "${RECENT[@]:-/dev/null}" 2>/dev/null; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

empty_stubs(){
  shopt -s nullglob
  for f in People/*.md Programs/*.md; do
    # For Programs notes: count bullets under ## Context (canonical section per SKILL.md).
    # For People notes: count ALL body bullets (section structure varies — Role, Current Focus,
    # Working Dynamics, dated headers, etc.). A People note with any bullets is not a stub.
    if [[ "$f" == Programs/* ]]; then
      bullets="$(awk '/^## Context$/{c=1; next} /^## /{c=0} c && /^[[:space:]]*-[[:space:]]/{n++} END{print n+0}' "$f")"
    else
      # Skip frontmatter (between first and second ---), count all bullet lines in body
      bullets="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm<2{next} /^[[:space:]]*-[[:space:]]/{n++} END{print n+0}' "$f")"
    fi
    if [ "${bullets:-0}" -eq 0 ]; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

frontmatter_gaps(){
  shopt -s nullglob
  for f in Worklogs/[0-9]*-W*.md Archive/[0-9]*-W*.md; do
    [ -f "$f" ] || continue
    fm="$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$f")"
    missing="$(for k in programs people tags item-count done-count; do
                 printf '%s\n' "$fm" | grep -Eq "^${k}:" || echo "$k"
               done | jq -R . | jq -s '.')"
    if [ "$(printf '%s' "$missing" | jq 'length')" -gt 0 ]; then
      jq -cn --arg file "$f" --argjson missing "$missing" '{file:$file, missing:$missing}'
    fi
  done | emit_array
}

missing_links(){
  shopt -s nullglob
  names="$( { ls People 2>/dev/null; ls Programs 2>/dev/null; } | sed 's/\.md$//' | sort -u )"
  for f in "${RECENT[@]:-}"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      grep -nF "$name" "$f" 2>/dev/null | grep -vF "[[$name" | while IFS=: read -r ln rest; do
        jq -cn --arg file "$f" --argjson line "$ln" --arg text "$name" \
           '{file:$file, line:$line, text:$text, suggest:("[[" + $text + "]]")}'
      done
    done <<< "$names"
  done | emit_array
}

stuck_items(){
  shopt -s nullglob
  ARCH=()
  while IFS= read -r a; do ARCH+=("$a"); done < <(ls Archive 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort)
  norm(){ printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9 ' | tr -s ' '; }
  while IFS= read -r line; do
    title="${line#*In Progress - }"
    nt="$(norm "$title")"
    [ -n "$nt" ] || continue
    hits=0
    for a in "${ARCH[@]}"; do
      roll="$(grep -oE 'rolled forward to [^(]*\(([^)]*)\)' "Archive/$a" 2>/dev/null | sed 's/.*(\(.*\))/\1/')"
      if [ -n "$roll" ] && printf '%s' "$(norm "$roll")" | grep -qF "$(printf '%s' "$nt" | cut -c1-20)"; then
        hits=$((hits+1))
      fi
    done
    [ "$hits" -ge 2 ] || continue
    jq -cn --arg title "$title" --argjson hits "$hits" '{title:$title, archives_hit:$hits}'
  done < <(grep -E '^- \*\*P[012]\*\* ⏳ In Progress - ' "$ACTIVE" 2>/dev/null) | emit_array
}

jq -n \
  --argjson stale_people "$(stale_people)" \
  --argjson orphan_programs "$(orphan_programs)" \
  --argjson stuck_items "$(stuck_items)" \
  --argjson missing_links "$(missing_links)" \
  --argjson empty_stubs "$(empty_stubs)" \
  --argjson frontmatter_gaps "$(frontmatter_gaps)" \
  '{stale_people:$stale_people, orphan_programs:$orphan_programs, stuck_items:$stuck_items, missing_links:$missing_links, empty_stubs:$empty_stubs, frontmatter_gaps:$frontmatter_gaps}'
