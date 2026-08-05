#!/usr/bin/env bash
# audit-scan.sh <vault> - compute the six /worklog audit checks; emit JSON findings to stdout.
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
ACTIVE_BN="$(ls Worklogs 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -r | head -1)"
ACTIVE="${ACTIVE_BN:+Worklogs/${ACTIVE_BN}}"

emit_array(){ jq -s '.'; }

stale_people(){
  shopt -s nullglob
  # Build sorted list of ALL weekly files (Worklogs + Archive) for last_seen lookup.
  ALL_WEEKLY=()
  while IFS= read -r b; do ALL_WEEKLY+=("$b"); done < <(
    { ls Worklogs 2>/dev/null; ls Archive 2>/dev/null; } \
      | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -u | sort
  )
  for f in People/*.md; do
    name="$(basename "$f" .md)"
    if ! grep -Fq "[[$name" "${RECENT[@]:-/dev/null}" "$BACKLOG" 2>/dev/null; then
      # Find last_seen: highest WNN weekly file (basename without .md, sorted desc)
      # among ALL weekly files in which [[<name appears.
      last_seen="never"
      for b in "${ALL_WEEKLY[@]:-}"; do
        [ -n "$b" ] || continue
        found_in=""
        [ -f "Worklogs/$b" ] && grep -Fq "[[$name" "Worklogs/$b" 2>/dev/null && found_in="$b"
        [ -f "Archive/$b"  ] && grep -Fq "[[$name" "Archive/$b"  2>/dev/null && found_in="$b"
        if [ -n "$found_in" ]; then
          # basename without .md = week label e.g. 2026-W19
          last_seen="${found_in%.md}"
        fi
      done
      # ALL_WEEKLY is sorted ascending, so last iteration that matched is the highest week
      jq -cn --arg file "$f" --arg last_seen "$last_seen" '{file:$file, last_seen:$last_seen}'
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
    bullets="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm<2{next} /^[[:space:]]*-[[:space:]]/{n++} END{print n+0}' "$f")"
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
  local pfile
  pfile="$(mktemp)"
  { ls People 2>/dev/null; ls Programs 2>/dev/null; } | sed 's/\.md$//' | sort -u > "$pfile"
  for f in "${RECENT[@]:-}"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    grep -nFf "$pfile" "$f" 2>/dev/null | while IFS=: read -r ln rest; do
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$rest" in *"[[$name"*) continue ;; esac
        case "$rest" in
          *"$name"*)
            jq -cn --arg file "$f" --argjson line "$ln" --arg text "$name" \
               '{file:$file, line:$line, text:$text, suggest:("[[" + $text + "]]")}'
          ;;
        esac
      done < "$pfile"
    done
  done | emit_array
  rm -f "$pfile"
}

stuck_items(){
  [ -n "${ACTIVE:-}" ] && [ -f "$ACTIVE" ] || { echo '[]'; return; }
  shopt -s nullglob
  # Sorted ascending list of archive basenames (e.g. 2026-W14.md, 2026-W15.md, ...)
  ARCH=()
  while IFS= read -r a; do ARCH+=("$a"); done < <(ls Archive 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort)
  ARCH_LEN="${#ARCH[@]}"
  norm(){ printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9 ' | tr -s ' '; }
  while IFS= read -r line; do
    title="${line#*In Progress - }"
    nt="$(norm "$title")"
    [ -n "$nt" ] || continue
    prefix20="$(printf '%s' "$nt" | cut -c1-20)"

    # --- Step 1: Collect indices of matching archives ---
    match_indices=""
    since_week=""
    i=0
    while [ "$i" -lt "$ARCH_LEN" ]; do
      a="${ARCH[$i]}"
      roll="$(grep -oE 'rolled forward to [^(]*\(([^)]*)\)' "Archive/$a" 2>/dev/null | sed 's/.*(\(.*\))/\1/')"
      if [ -n "$roll" ] && printf '%s' "$(norm "$roll")" | grep -qF "$prefix20"; then
        match_indices="${match_indices} $i"
        # earliest matching archive week (ascending sort => first match)
        if [ -z "$since_week" ]; then since_week="${a%.md}"; fi
      fi
      i=$((i+1))
    done

    # Need at least 2 matches for any consecutiveness check
    match_count=$(printf '%s' "$match_indices" | wc -w | tr -d ' ')
    [ "$match_count" -ge 2 ] || continue

    # --- Step 2: Require at least two ADJACENT (consecutive) matching indices ---
    consecutive=0
    prev=-99
    for idx in $match_indices; do
      if [ "$((idx - prev))" -eq 1 ]; then consecutive=1; break; fi
      prev="$idx"
    done
    [ "$consecutive" -eq 1 ] || continue

    # --- Step 3: Extract item block from active week, check for (Mon D) dated sub-item ---
    # Capture lines from the item's header up to (but not including) the next P0/P1/P2 header.
    item_block="$(awk -v tgt="$title" '
      BEGIN{found=0}
      /^- \*\*P[012]\*\* ⏳ In Progress - /{
        if(found){exit}
        if(index($0, tgt)>0){found=1; print; next}
      }
      found{print}
    ' "$ACTIVE" 2>/dev/null)"
    # Regex for (Mon D) or (Mon DD): e.g. (May 14), (Jun 4)
    if printf '%s' "$item_block" | grep -qE '\([A-Z][a-z][a-z] [0-9]{1,2}\)'; then
      continue  # has dated progress - not stuck
    fi

    # --- Step 4: Emit {title, since, last_dated:null} ---
    jq -cn --arg title "$title" --arg since "$since_week" \
       '{title:$title, since:$since, last_dated:null}'
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
