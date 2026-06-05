#!/usr/bin/env bash
# preferences-index.sh <vault> — emit a compact digest of Preferences/*.md (title, applies-to, rule).
# Read-only. Lets the model pick relevant preferences without loading all bodies.
set -euo pipefail
VAULT="${1:?usage: preferences-index.sh <vault-path>}"
DIR="$VAULT/Preferences"
[ -d "$DIR" ] || { echo "preferences-index: no Preferences dir in $VAULT" >&2; exit 2; }
cd "$DIR"
shopt -s nullglob
for f in *.md; do
  title="$(basename "$f" .md)"
  applies="$(awk -F'applies-to:' '/^applies-to:/{print $2; exit}' "$f" | tr -d '[]"' | sed 's/^ *//; s/ *$//')"
  # rule = first non-empty line after "## The Rule"; fallback = description field from frontmatter;
  # final fallback = first non-heading, non-empty body line after frontmatter
  rule="$(awk '/^## The Rule/{f=1; next} f && NF {print; exit}' "$f")"
  if [ -z "$rule" ]; then
    rule="$(awk -F'description:' '/^description:/{print $2; exit}' "$f" | sed 's/^ *//; s/ *$//' | tr -d '"')"
  fi
  if [ -z "$rule" ]; then
    # fallback: first non-heading, non-empty body line after frontmatter (or after title if no frontmatter)
    rule="$(awk '
      BEGIN{fm=0; past_title=0}
      /^---$/{fm++; next}
      fm>=2 && /^#/{next}
      fm>=2 && NF {print; exit}
      fm==0 && /^#/{past_title=1; next}
      fm==0 && past_title && NF && !/^#/ {print; exit}
    ' "$f")"
  fi
  jq -cn --arg t "$title" --arg a "$applies" --arg r "$rule" \
     '{title:$t,
       applies_to:($a|split(",")|map(gsub("^ +| +$";""))|map(select(length>0))),
       rule:$r}'
done
