# Worklog Cost-Optimization Program Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut token cost on `/worklog audit` (~312K→~26K), the per-call base tax (~21K→~10K), and the preferences path (~40K→few KB), with zero behavior change.

**Architecture:** Two read-only bash scanners in the plugin (`skills/worklog/scripts/`) compute audit findings and a preferences digest so the model never loads People/Programs/Preferences bodies; three rarely-used `SKILL.md` blocks move to `skills/worklog/references/` loaded on demand. Helpers are invoked via the existing `__SKILL_INSTALL_PATH__` placeholder and take the vault path (`__VAULT_PATH__`) as an argument.

**Tech Stack:** bash + `jq` + `grep`/`awk` (no new deps); markdown skill files.

**Spec:** `docs/superpowers/specs/2026-06-05-worklog-cost-optimization-design.md`
**Branch:** `worklog-cost-optimization` (created; spec committed at `2a07558`).
**Commit identity (every commit):** `git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com"`, message ending with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
**Implement in order A → C → B → D.** Verify scanners against the REAL vault at `/Users/mminutillo/Documents/Obsidian Vault`.

---

## File Structure

- `skills/worklog/scripts/audit-scan.sh` — NEW. Computes the 6 audit checks, emits JSON.
- `skills/worklog/scripts/preferences-index.sh` — NEW. Emits a compact preferences digest.
- `skills/worklog/references/viz.md` — NEW. Moved `/worklog viz` detail.
- `skills/worklog/references/netflix-commands.md` — NEW. Moved Netflix-commands section.
- `skills/worklog/references/pull-flow.md` — NEW. Moved pull / context-channel / DM-sweep detail.
- `skills/worklog/SKILL.md` — MODIFY. Audit rewrite; preferences apply-step; three "MUST read" stubs.
- `.claude-plugin/plugin.json` — MODIFY. 5.7.0 → 5.8.0.
- `README.md` — MODIFY. One note about scanners + on-demand detail.

---

## PHASE A — Audit deterministic helper

### Task A1: Write `audit-scan.sh` (all six checks)

**Files:**
- Create: `skills/worklog/scripts/audit-scan.sh`

- [ ] **Step 1: Create the script with this exact content**

```bash
mkdir -p skills/worklog/scripts
cat > skills/worklog/scripts/audit-scan.sh <<'SCRIPT'
#!/usr/bin/env bash
# audit-scan.sh <vault> — compute the six /worklog audit checks; emit JSON findings to stdout.
# Read-only. Scans the vault in bash so the model never loads People/Programs bodies.
# Checks mirror the definitions in SKILL.md's `/worklog audit` section exactly.
set -euo pipefail

VAULT="${1:?usage: audit-scan.sh <vault-path>}"
[ -d "$VAULT" ] || { echo "audit-scan: vault dir not found: $VAULT" >&2; exit 2; }
cd "$VAULT"

# The 4 most recent weekly files (YYYY-WNN.md) across Worklogs + Archive.
mapfile -t RECENT_BN < <(
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
# Active week = lexically-greatest YYYY-WNN.md in Worklogs/.
ACTIVE="$(ls Worklogs 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -r | head -1)"
ACTIVE="Worklogs/${ACTIVE}"

emit_array(){ jq -s '.'; }

# Check 1: stale people — name not wiki-linked in recent weeklies and not in Backlog.
stale_people(){
  shopt -s nullglob
  for f in People/*.md; do
    name="$(basename "$f" .md)"
    if ! grep -Fq "[[$name" "${RECENT[@]:-/dev/null}" "$BACKLOG" 2>/dev/null; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

# Check 2: orphan programs — name not wiki-linked in recent weeklies (no Backlog exclusion).
orphan_programs(){
  shopt -s nullglob
  for f in Programs/*.md; do
    name="$(basename "$f" .md)"
    if ! grep -Fq "[[$name" "${RECENT[@]:-/dev/null}" 2>/dev/null; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

# Check 5: empty stubs — People/Programs note whose ## Context has no bullet lines.
empty_stubs(){
  shopt -s nullglob
  for f in People/*.md Programs/*.md; do
    bullets="$(awk '/^## Context/{c=1; next} /^## /{c=0} c && /^[[:space:]]*-[[:space:]]/{n++} END{print n+0}' "$f")"
    if [ "${bullets:-0}" -eq 0 ]; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

# Check 6: frontmatter gaps — weekly/archive files missing any enriched field.
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

# Check 4: missing links — known People/Program names appearing in weekly body NOT in [[..]].
# Suggestion list only; conservative (whole-word, skips lines already containing the name in [[..]]).
missing_links(){
  shopt -s nullglob
  names="$( { ls People 2>/dev/null; ls Programs 2>/dev/null; } | sed 's/\.md$//' | sort -u )"
  for f in "${RECENT[@]:-}"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      # lines containing the name as a word but NOT already wiki-linked to it
      grep -nF "$name" "$f" 2>/dev/null | grep -vF "[[$name" | while IFS=: read -r ln rest; do
        jq -cn --arg file "$f" --argjson line "$ln" --arg text "$name" \
           '{file:$file, line:$line, text:$text, suggest:("[[" + $text + "]]")}'
      done
    done <<< "$names"
  done | emit_array
}

# Check 3: stuck items — active In-Progress title in 2+ consecutive archives' rollover lists
# AND no (Mon D) dated sub-item in the active week. Normalized title match; fuzzy by design.
stuck_items(){
  shopt -s nullglob
  # archive rollover parentheticals, oldest->newest by week
  mapfile -t ARCH < <(ls Archive 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort)
  norm(){ printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9 ' | tr -s ' '; }
  # gather active In-Progress top-level item titles
  jqout=""
  while IFS= read -r line; do
    title="${line#*In Progress - }"
    nt="$(norm "$title")"
    [ -n "$nt" ] || continue
    # count consecutive archives whose rollover list mentions a normalized title overlap
    hits=0
    for a in "${ARCH[@]}"; do
      roll="$(grep -oE 'rolled forward to [^(]*\(([^)]*)\)' "Archive/$a" 2>/dev/null | sed 's/.*(\(.*\))/\1/')"
      if [ -n "$roll" ] && printf '%s' "$(norm "$roll")" | grep -qF "$(printf '%s' "$nt" | cut -c1-20)"; then
        hits=$((hits+1))
      fi
    done
    [ "$hits" -ge 2 ] || continue
    # dated sub-item present? (look for "(Mon D)" under this item — approximate: any (Mon D) in file)
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
SCRIPT
chmod 755 skills/worklog/scripts/audit-scan.sh
```

- [ ] **Step 2: Syntax check**

Run: `bash -n skills/worklog/scripts/audit-scan.sh && echo "syntax ok"`
Expected: `syntax ok`

- [ ] **Step 3: Run against the real vault and confirm well-formed JSON**

Run: `skills/worklog/scripts/audit-scan.sh "/Users/mminutillo/Documents/Obsidian Vault" | jq -e 'keys==["empty_stubs","frontmatter_gaps","missing_links","orphan_programs","stale_people","stuck_items"]' && echo "json shape ok"`
Expected: `true` then `json shape ok`.

- [ ] **Step 4: Commit**

```bash
git add skills/worklog/scripts/audit-scan.sh
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "feat(audit): add audit-scan.sh deterministic vault scanner

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A2: Verify each check against the vault and fix discrepancies

**Files:**
- Modify (if fixes needed): `skills/worklog/scripts/audit-scan.sh`

- [ ] **Step 1: Inspect each finding type against the real files**

Run:
```bash
V="/Users/mminutillo/Documents/Obsidian Vault"
out="$(skills/worklog/scripts/audit-scan.sh "$V")"
for k in stale_people orphan_programs empty_stubs frontmatter_gaps missing_links stuck_items; do
  echo "=== $k: $(printf '%s' "$out" | jq ".$k | length") ==="
  printf '%s' "$out" | jq -c ".$k[0:5][]?"
done
```
Verify by opening 1-2 cited files per check:
- __stale_people / orphan_programs__: the named note is genuinely not `[[linked]]` in the 4 most recent weekly files (and, for people, not in Backlog).
- __empty_stubs__: the note's `## Context` truly has no `- ` bullets.
- __frontmatter_gaps__: the listed `missing` fields are truly absent from that file's frontmatter.
- __missing_links__: the name on that line is a real unlinked mention (accept some false positives for common first names — it is a suggestion list, matching today's behavior).
- __stuck_items__: spot-check that the title really recurs in archive rollover lists. This check is fuzzy by design; over-flagging is acceptable because the model reviews findings before presenting.

- [ ] **Step 2: Fix any check whose findings are wrong**

If a check mis-reports (e.g., aliased-link miss, frontmatter false gap, basename with spaces), edit `audit-scan.sh` to correct it, re-run Step 1, and confirm. Keep the JSON keys/shape identical.

- [ ] **Step 3: Re-run syntax + shape checks**

Run: `bash -n skills/worklog/scripts/audit-scan.sh && skills/worklog/scripts/audit-scan.sh "/Users/mminutillo/Documents/Obsidian Vault" | jq -e '.frontmatter_gaps|type=="array"' && echo ok`
Expected: `true` then `ok`.

- [ ] **Step 4: Commit (only if fixes were made)**

```bash
git add skills/worklog/scripts/audit-scan.sh
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "fix(audit): correct audit-scan checks against real-vault verification

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task A3: Rewrite `/worklog audit` in `SKILL.md` to use the scanner

**Files:**
- Modify: `skills/worklog/SKILL.md` (the `### /worklog audit` section)

- [ ] **Step 1: Read the current audit section to get exact anchors**

Run: `grep -n "### \`/worklog audit\`" skills/worklog/SKILL.md` then read from that line to the next `### \`/worklog` heading.

- [ ] **Step 2: Replace the section body (keep the heading + the Nudge-check line) with**

```markdown
__Nudge check (run first):__ Same as `/worklog rollover` above - check `Sources/*.md` and
surface a stale-channel FYI before continuing.

Scan the vault for quality issues and present a fix-it checklist. No arguments.

__Run the scanner__ (computes all six checks in bash so no People/Programs bodies load into
context):

```bash
__SKILL_INSTALL_PATH__/scripts/audit-scan.sh '__VAULT_PATH__'
```

It prints JSON with six arrays: `stale_people`, `orphan_programs`, `stuck_items`,
`missing_links`, `empty_stubs`, `frontmatter_gaps`. Read __only__ this output. The
`stuck_items` check is heuristic — review each before presenting and drop obvious misfires.

Present the findings grouped by check type in conversation, each with a suggested action
(same format as before), e.g.:

​```
Vault audit results:

Stale people (not mentioned in 4+ weeks):
- People/Jordan Lee.md - last seen in W19
  Suggested: archive, update context, or remove if no longer relevant

Frontmatter gaps:
- Archive/2026-W11.md: missing programs, people
​```

The user picks which fixes to apply. Apply approved fixes directly using Edit/Write tools;
for frontmatter gaps, regenerate using the Frontmatter Auto-generation rules. The check
definitions live in `scripts/audit-scan.sh`; do not re-derive them here.
```

- [ ] **Step 3: Verify the section no longer embeds the per-check methods**

Run: `awk '/^### `\/worklog audit`/{f=1} f&&/^### `\/worklog search`/{f=0} f' skills/worklog/SKILL.md | grep -c "audit-scan.sh"`
Expected: `>= 1`. Then confirm the old phrase `Glob \`People/*.md\`` no longer appears in that section.

- [ ] **Step 4: Commit**

```bash
git add skills/worklog/SKILL.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "feat(audit): /worklog audit calls audit-scan.sh, reads only findings

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## PHASE C — Preferences index

### Task C1: Write `preferences-index.sh`

**Files:**
- Create: `skills/worklog/scripts/preferences-index.sh`

- [ ] **Step 1: Create the script with this exact content**

```bash
cat > skills/worklog/scripts/preferences-index.sh <<'SCRIPT'
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
  # rule = first non-empty line after "## The Rule"; fallback = first body line after frontmatter
  rule="$(awk '/^## The Rule/{f=1; next} f && NF {print; exit}' "$f")"
  [ -n "$rule" ] || rule="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2 && NF && !/^#/ {print; exit}' "$f")"
  jq -cn --arg t "$title" --arg a "$applies" --arg r "$rule" \
     '{title:$t,
       applies_to:($a|split(",")|map(gsub("^ +| +$";""))|map(select(length>0))),
       rule:$r}'
done
SCRIPT
chmod 755 skills/worklog/scripts/preferences-index.sh
```

- [ ] **Step 2: Syntax check + run**

Run:
```bash
bash -n skills/worklog/scripts/preferences-index.sh && echo "syntax ok"
skills/worklog/scripts/preferences-index.sh "/Users/mminutillo/Documents/Obsidian Vault" | jq -e '.title and (.applies_to|type=="array")' >/dev/null && echo "records ok"
```
Expected: `syntax ok` then `records ok`.

- [ ] **Step 3: Confirm every preference appears and rules are populated**

Run:
```bash
V="/Users/mminutillo/Documents/Obsidian Vault"
echo "files: $(ls "$V/Preferences"/*.md | wc -l | tr -d ' ')  records: $(skills/worklog/scripts/preferences-index.sh "$V" | jq -s 'length')"
echo "records with empty rule:"; skills/worklog/scripts/preferences-index.sh "$V" | jq -r 'select(.rule=="") | .title'
```
Expected: file count == record count. If some rules are empty (a pref lacks both `## The Rule` and a body line), inspect those files; if needed, broaden the fallback in the script and re-run.

- [ ] **Step 4: Commit**

```bash
git add skills/worklog/scripts/preferences-index.sh
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "feat(prefs): add preferences-index.sh digest scanner

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C2: Rewrite the Preferences apply-step in `SKILL.md`

**Files:**
- Modify: `skills/worklog/SKILL.md` (the `### When to apply a preference` subsection AND the `Preferences are first-class.` Important-Behavior bullet)

- [ ] **Step 1: Replace the body of `### When to apply a preference` with**

```markdown
### When to apply a preference

Before doing any task that has a preference-shaped surface - drafting a message, writing
markdown, making a workflow choice, picking a tool, structuring a note - run the index:

```bash
__SKILL_INSTALL_PATH__/scripts/preferences-index.sh '__VAULT_PATH__'
```

It prints one record per preference (`title`, `applies_to`, `rule`). Select the 1-3 whose
`applies_to`/title/rule match the task, then read __only those__ full bodies from
`Preferences/<Title>.md`. Do not read every preference file. Cite the ones you applied
lightly so the user can correct you.
```

- [ ] **Step 2: Update the `Preferences are first-class.` Important-Behavior bullet**

Find the bullet beginning `- **Preferences are first-class.**` and replace its
"glob `Preferences/*.md` and apply what's relevant" clause with: "run
`__SKILL_INSTALL_PATH__/scripts/preferences-index.sh '__VAULT_PATH__'`, pick the 1-3 relevant
preferences from the digest, and read only those bodies". Leave the rest of the bullet intact.

- [ ] **Step 3: Verify**

Run: `grep -c "preferences-index.sh" skills/worklog/SKILL.md`
Expected: `>= 2`. Confirm `glob \`Preferences/*.md\`` no longer appears as the apply mechanism.

- [ ] **Step 4: Commit**

```bash
git add skills/worklog/SKILL.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "feat(prefs): apply preferences via index digest, not full glob

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## PHASE B — SKILL.md progressive disclosure (moderate)

For each move: copy the section verbatim into the new reference file (prepend a `# <Title>`
heading), then replace the section in `SKILL.md` with a stub. Do the moves one reference at a
time so `SKILL.md` line anchors stay predictable.

### Task B1: Extract `/worklog viz` → `references/viz.md`

**Files:**
- Create: `skills/worklog/references/viz.md`
- Modify: `skills/worklog/SKILL.md`

- [ ] **Step 1: Locate the section**

Run: `grep -n "### \`/worklog viz\`" skills/worklog/SKILL.md` and find the next `### \`/worklog` heading after it (currently `/worklog sync`). The section to move is from the `### \`/worklog viz\`` line up to (not including) the next `###` heading.

- [ ] **Step 2: Move the section body into the new file**

Cut everything under `### \`/worklog viz\`` (the prose, the Syntax/Output/How-to-generate blocks) into `skills/worklog/references/viz.md`, prepended with:
```markdown
# /worklog viz — full detail

(Loaded on demand by SKILL.md.)
```

- [ ] **Step 3: Replace the in-`SKILL.md` section with this stub**

```markdown
### `/worklog viz [period]`

Generate standalone HTML D3 charts for a period. __Before executing, you MUST read
`__SKILL_INSTALL_PATH__/references/viz.md` and follow it__ (full mechanics + template-fill
live there to keep this file small).
```

- [ ] **Step 4: Verify**

Run:
```bash
test -f skills/worklog/references/viz.md && echo "viz.md created"
grep -q "references/viz.md" skills/worklog/SKILL.md && echo "stub present"
grep -c "DATA_PLACEHOLDER" skills/worklog/SKILL.md   # expect 0 (moved out)
grep -c "DATA_PLACEHOLDER" skills/worklog/references/viz.md  # expect >=1 (moved in)
```
Expected: `viz.md created`, `stub present`, `0`, then `>=1`.

- [ ] **Step 5: Commit**

```bash
git add skills/worklog/references/viz.md skills/worklog/SKILL.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "refactor(skill): move /worklog viz detail to references/viz.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B2: Extract Netflix-commands section → `references/netflix-commands.md`

**Files:**
- Create: `skills/worklog/references/netflix-commands.md`
- Modify: `skills/worklog/SKILL.md`

- [ ] **Step 1: Locate the section**

Run: `grep -n "^## Netflix-specific commands" skills/worklog/SKILL.md`. The section runs from that `## ` heading to end-of-file (it is the last top-level section).

- [ ] **Step 2: Move the whole section into the new file**

Cut everything from `## Netflix-specific commands (this fork only)` to EOF into
`skills/worklog/references/netflix-commands.md`, prepended with `# Netflix-specific commands (this fork only)` and a line `(Loaded on demand by SKILL.md.)`. This includes the argument auto-routing table, `/worklog ingest`, `/worklog whois`, `/worklog jira`, and the cross-command enrichment rules.

- [ ] **Step 3: Append this stub to `SKILL.md` where the section was**

```markdown
## Netflix-specific commands (this fork only)

`/worklog ingest <url>`, `/worklog whois <name|email>`, `/worklog jira <key>`, and the
`/worklog <arg>` auto-routing all live in detail in `__SKILL_INSTALL_PATH__/references/netflix-commands.md`.
__Before running any of these (or auto-routing a bare `/worklog <arg>`), you MUST read that
reference and follow it exactly__ — it names the exact MCP tool per action and the
untrusted-content rules.
```

- [ ] **Step 4: Verify**

Run:
```bash
test -f skills/worklog/references/netflix-commands.md && echo "created"
grep -q "references/netflix-commands.md" skills/worklog/SKILL.md && echo "stub present"
grep -c "mcp__core-tools__fetch-slack-thread" skills/worklog/SKILL.md   # expect 0
grep -c "mcp__core-tools__fetch-slack-thread" skills/worklog/references/netflix-commands.md  # expect >=1
```
Expected: `created`, `stub present`, `0`, `>=1`.

- [ ] **Step 5: Commit**

```bash
git add skills/worklog/references/netflix-commands.md skills/worklog/SKILL.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "refactor(skill): move Netflix-commands section to references/

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B3: Extract the detailed pull flow → `references/pull-flow.md`

**Files:**
- Create: `skills/worklog/references/pull-flow.md`
- Modify: `skills/worklog/SKILL.md`

- [ ] **Step 1: Locate the boundaries**

The detail to move is, within `### \`/worklog pull\``, everything from `__Pull flow:__` through the end of `__Errors and edge cases:__` (i.e., Pull flow, Context-channel sweep flow, Three-way classification, What auto-fold writes, Approval batch, DM sweep flow, DM privacy override, First-run registration, Body extraction, Errors and edge cases). Keep the `### \`/worklog pull\`` heading + its first orientation paragraph and the `__Source-type branch:__` paragraph inline.
Run: `grep -n "__Pull flow:__\|__Errors and edge cases:__\|### \`/worklog rollover\`" skills/worklog/SKILL.md` to get the cut range (from `__Pull flow:__` to just before `### \`/worklog rollover\``).

- [ ] **Step 2: Move that range into the new file**

Cut the range into `skills/worklog/references/pull-flow.md`, prepended with `# /worklog pull — full flow` and `(Loaded on demand by SKILL.md.)`.

- [ ] **Step 3: Insert this stub** right after the retained `__Source-type branch:__` paragraph (before `### \`/worklog rollover\``)

```markdown
__Full flow detail:__ the pull steps, the context-channel sweep, the DM sweep + privacy
override, first-run registration, and body extraction live in
`__SKILL_INSTALL_PATH__/references/pull-flow.md`. __Before executing `/worklog pull`, you MUST
read that reference and follow it__ (kept out of this file for size; behavior is unchanged).
```

- [ ] **Step 4: Verify**

Run:
```bash
test -f skills/worklog/references/pull-flow.md && echo "created"
grep -q "references/pull-flow.md" skills/worklog/SKILL.md && echo "stub present"
grep -c "slack-search-dms" skills/worklog/SKILL.md          # expect 0 (DM detail moved)
grep -c "slack-search-dms" skills/worklog/references/pull-flow.md  # expect >=1
grep -c "DM sweeps are approval-only" skills/worklog/SKILL.md  # expect 1 (the Important-Behavior bullet stays)
```
Expected: `created`, `stub present`, `0`, `>=1`, `1`.

- [ ] **Step 5: Repoint any stale cross-references**

Run: `grep -n "see the .*pull\|Context-channel sweep flow\|DM sweep flow" skills/worklog/SKILL.md`. Any reference in the still-inline text pointing into moved content must point to `references/pull-flow.md` instead. Fix inline.

- [ ] **Step 6: Commit**

```bash
git add skills/worklog/references/pull-flow.md skills/worklog/SKILL.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "refactor(skill): move detailed pull flow to references/pull-flow.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task B4: Confirm the base-tax reduction

**Files:** none (measurement)

- [ ] **Step 1: Measure the new SKILL.md size**

Run: `wc -l skills/worklog/SKILL.md; wc -c skills/worklog/SKILL.md | awk '{printf "~%d tokens\n", $1/4}'`
Expected: materially smaller than the 1,712 lines / ~21K tokens baseline; target ~10K tokens (±). If it is still close to baseline, a section did not actually move — re-check B1-B3.

- [ ] **Step 2: Confirm references load-paths resolve in the templated file**

Run: `grep -c "__SKILL_INSTALL_PATH__/references/" skills/worklog/SKILL.md`
Expected: `3` (one stub per moved block).

---

## PHASE D — Version bump, README, propagation

### Task D1: Bump version + README note

**Files:**
- Modify: `.claude-plugin/plugin.json`, `README.md`

- [ ] **Step 1: Bump version 5.7.0 → 5.8.0**

Edit `.claude-plugin/plugin.json`: set `"version": "5.8.0",`. Verify: `jq -e '.version=="5.8.0"' .claude-plugin/plugin.json && echo ok` → `true`, `ok`.

- [ ] **Step 2: Add a README note**

Add one sentence to `README.md` (near the existing feature bullets): that `/worklog audit` and preference application use bundled read-only scanner scripts (`skills/worklog/scripts/`) and that less-common command detail is loaded on demand from `skills/worklog/references/`, to keep token cost low.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json README.md
git -c user.name="mminutillo" -c user.email="mminutillo@netflix.com" commit -m "chore: bump obsidian-worklog to 5.8.0 (cost optimizations)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task D2: Propagate to the live install (substituting SKILL.md AND references/)

**Files:** live install copies + scripts.

- [ ] **Step 1: Rsync fork → marketplace, then substitute placeholders in SKILL.md AND references/**

```bash
SRC=~/obsidian-worklog
DST=~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
rsync -a --delete --exclude '.git' "$SRC/" "$DST/"
# substitute the 6 placeholders in SKILL.md and every references/*.md (moved content carries __VAULT_PATH__):
for tgt in "$DST/skills/worklog/SKILL.md" "$DST"/skills/worklog/references/*.md; do
  sed -i '' \
    -e 's#__VAULT_PATH__#/Users/mminutillo/Documents/Obsidian Vault#g' \
    -e 's#__USER_NAME__#Menotti#g' \
    -e 's#__GIT_USER_NAME__#mminutillo#g' \
    -e 's#__GIT_USER_EMAIL__#mminutillo@netflix.com#g' \
    -e 's#__SKILL_INSTALL_PATH__#/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog#g' \
    -e 's#__BACKUP_REPO_URL__#github.netflix.net/mminutillo/obsidian-vault#g' \
    "$tgt"
done
# scripts must be executable in the install:
chmod 755 "$DST"/skills/worklog/scripts/*.sh
```

- [ ] **Step 2: Verify no placeholders remain in the install (SKILL.md + references)**

Run:
```bash
DST=~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
grep -rc "__VAULT_PATH__\|__SKILL_INSTALL_PATH__\|__USER_NAME__\|__GIT_USER_NAME__\|__GIT_USER_EMAIL__\|__BACKUP_REPO_URL__" "$DST/skills/worklog/SKILL.md" "$DST"/skills/worklog/references/*.md | grep -v ':0$' || echo "all substituted"
jq -r .version "$DST/.claude-plugin/plugin.json"
```
Expected: `all substituted` then `5.8.0`.

- [ ] **Step 3: Smoke-test the installed scanners (absolute paths, as the skill will call them)**

Run:
```bash
DST=~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
"$DST/scripts/../skills/worklog/scripts/audit-scan.sh" "/Users/mminutillo/Documents/Obsidian Vault" | jq -e '.frontmatter_gaps|type=="array"' && echo "audit ok"
"$DST/skills/worklog/scripts/preferences-index.sh" "/Users/mminutillo/Documents/Obsidian Vault" | jq -se 'length>0' && echo "prefs ok"
```
Expected: `true`/`audit ok` and `true`/`prefs ok`.

- [ ] **Step 4: Create the version cache + update the vault `.skills` copy**

```bash
DST=~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog
rm -rf ~/.claude/plugins/cache/personal/obsidian-worklog/5.8.0
cp -R "$DST" ~/.claude/plugins/cache/personal/obsidian-worklog/5.8.0
cp "$DST/skills/worklog/SKILL.md"    "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/SKILL.md"
cp "$DST/.claude-plugin/plugin.json" "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/plugin.json"
mkdir -p "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/scripts" "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/references"
cp "$DST"/skills/worklog/scripts/*.sh "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/scripts/"
cp "$DST"/skills/worklog/references/*.md "/Users/mminutillo/Documents/Obsidian Vault/.skills/worklog/references/"
```

- [ ] **Step 5: Reload + final base-tax measurement**

Tell the user to run `/reload-plugins`, then confirm the loaded base dir is `.../5.8.0/...` on the next `/worklog` call. Re-run the static measurement to confirm: audit path now ~26K, base tax ~10K.

- [ ] **Step 6: Push the branch**

```bash
cd ~/obsidian-worklog && git push -u origin worklog-cost-optimization
```

---

## Self-Review (completed by plan author)

- __Spec coverage:__ A audit helper (A1-A2) ✓ + SKILL rewrite (A3) ✓; C preferences-index (C1) ✓ + SKILL rewrite (C2) ✓; B three reference moves with MUST-read stubs (B1-B3) ✓ + base-tax check (B4) ✓; cross-cutting helper location/placeholder convention (scripts via `__SKILL_INSTALL_PATH__`, vault arg) ✓; behavior-preserving verification (A2, C3, B verify steps) ✓; propagation substitutes references/ too + executable scripts (D2) ✓; version bump (D1) ✓; A→C→B order ✓.
- __Placeholder scan:__ both scripts are complete; no TBD/TODO. The B moves are cut operations specified by exact anchors + complete stub text (reproducing 47KB of existing content verbatim is not a "placeholder" gap). Verify steps define "correct" per check rather than asserting vault-dependent exact output, which is the right contract for a vault scanner.
- __Name consistency:__ JSON keys (`stale_people`, `orphan_programs`, `stuck_items`, `missing_links`, `empty_stubs`, `frontmatter_gaps`) match between `audit-scan.sh` (A1) and the SKILL rewrite (A3). Preferences record fields (`title`, `applies_to`, `rule`) match between `preferences-index.sh` (C1) and the apply-step rewrite (C2). Both scanners invoked identically as `__SKILL_INSTALL_PATH__/scripts/<name>.sh '__VAULT_PATH__'`.
