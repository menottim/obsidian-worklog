# Worklog Model Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an advisory guard that, before a heavy worklog command runs on a sub-Opus model, pauses and asks the user whether to continue or switch to Opus 4.8.

**Architecture:** One shared `## Model Guard` section in `skills/worklog/SKILL.md`, referenced by a one-line pointer at the start of the five heavy command sections. Detection is soft self-report (the running model reads its own identity from its system prompt); it fails open (skips silently) when Opus-tier or unknown, and asks at most once per conversation when sub-Opus. Pure prompt-level; no scripts, no programmatic detection.

**Tech Stack:** Markdown skill prose (`SKILL.md`), Claude Code plugin packaging (`plugin.json`, version-keyed cache), `evals/evals.json`, bash (`rsync`, `sed`, `git`) for propagation.

## Global Constraints

- Edits are made to the repo TEMPLATE at `skills/worklog/SKILL.md`. The `## Model Guard` section references no vault paths or user names, so it must introduce NO new `__PLACEHOLDER__` tokens.
- Version bump is mandatory: the plugin cache is keyed by version. Bump `.claude-plugin/plugin.json` from `5.9.0` to `5.10.0`.
- Propagation must substitute the 6 template placeholders after rsync (`__USER_NAME__`, `__VAULT_PATH__`, `__GIT_USER_NAME__`, `__GIT_USER_EMAIL__`, `__SKILL_INSTALL_PATH__`, `__BACKUP_REPO_URL__`). Never leave a raw placeholder in the live skill.
- Voice: no emdashes (use hyphens or rewrite), `__bold__` with underscores, no hyperbole. Match the surrounding SKILL.md prose.
- Work happens on branch `worklog-model-guard` (already created).

---

### Task 1: Add the shared `## Model Guard` section

**Files:**
- Modify: `skills/worklog/SKILL.md` (add one new top-level section)

**Interfaces:**
- Produces: a top-level heading exactly `## Model Guard`, referenced by name from Task 2's pointers.

- [ ] **Step 1: Choose the insertion point**

Read `skills/worklog/SKILL.md` and locate the end of the `## Vault Layout` section (the block that lists `- People:`, `- Programs:`, `- Teams:` paths). The new section goes immediately after that section and before the next `##` heading. Placing it near the top is fine; it is referenced by name, not position.

- [ ] **Step 2: Insert the section**

Insert exactly this block (verbatim):

```markdown
## Model Guard

Some worklog commands are heavy, single-shot synthesis and are more reliable on a more capable model. Before running one of those commands (each such section says "run the Model Guard first"), do this check:

1. Determine which model you are running as, from your own context. Claude Code states this in your system prompt (for example, "You are powered by the model named ...").
2. If you are Opus-tier (Opus 4.x): proceed silently. No guard.
3. If you cannot determine your model with confidence: proceed silently. Do not guess and do not ask.
4. If you are sub-Opus (Sonnet or Haiku tier) AND you have not already asked about this earlier in the current conversation: pause, ask the user, and wait for their answer:

   > This is a heavy synthesis task and you're running on `<your model>`. In testing, Opus 4.8 was the most reliable on large worklog inputs; smaller models can truncate or lose fidelity. Want me to continue on `<your model>`, or pause so you can switch (`/model` to Opus 4.8, ideally at high or xhigh effort) and re-run?

   - If the user says continue: proceed normally.
   - If the user says switch: tell them to run `/model` and pick Opus 4.8, then re-invoke the command, and stop.
   - Remember the user's choice for the rest of this conversation and do not ask again this session.

This is advisory, not a hard gate. It never blocks work on its own, and it never fires for `add`, `review`, `audit`, `rollover`, single-item edits, or a monthly summary.
```

- [ ] **Step 3: Verify the section is present and introduces no placeholders**

Run:
```bash
grep -n '^## Model Guard$' skills/worklog/SKILL.md
awk '/^## Model Guard$/{f=1} f&&/^## /&&!/^## Model Guard$/{f=0} f' skills/worklog/SKILL.md | grep -cE '__[A-Z_]+__'
```
Expected: the heading matches on one line; the placeholder count in the new section is `0`.

- [ ] **Step 4: Commit**

```bash
git add skills/worklog/SKILL.md
git commit -m "feat(worklog): add Model Guard section (advisory heavy-task model check)"
```

---

### Task 2: Add the five command pointers

**Files:**
- Modify: `skills/worklog/SKILL.md` (five command sections)

**Interfaces:**
- Consumes: the `## Model Guard` heading from Task 1.

- [ ] **Step 1: Add a pointer as the first instruction under each guarded section**

For each of the five section headings below, insert its pointer line as the first content line directly under the heading. Find each heading with `grep -n`:

- Under `### Processing raw input (meeting notes, Slack messages, transcripts)`:
  ```markdown
  Before processing a substantial input (a full transcript or a long notes doc, not a one-line add), run the Model Guard (see `## Model Guard`).
  ```
- Under ``### `/worklog pull` ``:
  ```markdown
  Before proceeding, run the Model Guard (see `## Model Guard`).
  ```
- Under ``### `/worklog viz [period]` ``:
  ```markdown
  Before proceeding, run the Model Guard (see `## Model Guard`).
  ```
- Under ``### `/worklog tidy` ``:
  ```markdown
  Before proceeding, run the Model Guard (see `## Model Guard`).
  ```
- Under ``### `/worklog summary [period]` ``:
  ```markdown
  For a quarter summary, run the Model Guard (see `## Model Guard`) before proceeding. (Week and month summaries are lighter and do not need it.)
  ```

- [ ] **Step 2: Verify all five pointers exist**

Run:
```bash
grep -c 'run the Model Guard (see `## Model Guard`)' skills/worklog/SKILL.md
```
Expected: `5`.

- [ ] **Step 3: Commit**

```bash
git add skills/worklog/SKILL.md
git commit -m "feat(worklog): wire Model Guard into the five heavy commands"
```

---

### Task 3: Bump the plugin version

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Change the version**

Change `"version": "5.9.0"` to `"version": "5.10.0"`.

- [ ] **Step 2: Verify**

Run:
```bash
grep '"version"' .claude-plugin/plugin.json
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
```
Expected: shows `5.10.0`; JSON parses with no error.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore(worklog): bump plugin version to 5.10.0"
```

---

### Task 4: Add an eval note for the guard

**Files:**
- Modify: `evals/evals.json`

**Interfaces:**
- Consumes: existing `evals[]` array shape `{id, prompt, expected_output, issue_tested}`.

- [ ] **Step 1: Append a new eval object**

Read `evals/evals.json`, find the highest existing `id`, and append one object with `id` = highest + 1:

```json
{
  "id": 29,
  "prompt": "/worklog viz quarter",
  "expected_output": "Model Guard behavior: if running on a sub-Opus model (Sonnet/Haiku), should pause and ask whether to continue or switch to Opus 4.8 before generating the visualization, and ask at most once per conversation. If running on Opus-tier or if the model cannot determine its identity, should proceed silently with no guard prompt. Light commands (add/review/audit) must never trigger the guard.",
  "issue_tested": "Model Guard fires on heavy commands under sub-Opus, fails open otherwise"
}
```

Use `id` = actual highest + 1 if it differs from 29.

- [ ] **Step 2: Verify JSON validity**

Run:
```bash
python3 -c "import json; d=json.load(open('evals/evals.json')); print('ok', len(d['evals']))"
```
Expected: `ok <n>` with no error.

- [ ] **Step 3: Commit**

```bash
git add evals/evals.json
git commit -m "test(worklog): add eval note for Model Guard behavior"
```

---

### Task 5: Propagate to the running marketplace and cache

> The repo SKILL.md is a template. Raw rsync alone leaves `__VAULT_PATH__` etc. in the live skill. Substitute after rsync. Reference: memory `worklog-fork-template-propagation` and `docs/superpowers/plans/2026-06-05-dm-sweep.md` Task 7.

**Files:**
- No repo files; updates the installed copies under `~/.claude/plugins/...`.

- [ ] **Step 1: Rsync the working tree to the marketplace copy**

```bash
rsync -a --delete --exclude '.git' --exclude '.DS_Store' \
  ~/obsidian-worklog/ \
  ~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/
```

- [ ] **Step 2: Reload plugins so the new version cache dir is created**

The cache dir `~/.claude/plugins/cache/personal/obsidian-worklog/5.10.0/` exists only after Claude Code detects the version bump. In Claude Code, run: `/reload-plugins`. (This is a user-run slash command; if executing headlessly, ask the user to run it.)

- [ ] **Step 3: Substitute the 6 placeholders in both installed copies**

```bash
for f in \
  ~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/skills/worklog/SKILL.md \
  ~/.claude/plugins/cache/personal/obsidian-worklog/5.10.0/skills/worklog/SKILL.md ; do
  [[ -f "$f" ]] && sed -i '' \
    -e 's|__VAULT_PATH__|/Users/mminutillo/Documents/Obsidian Vault|g' \
    -e 's|__USER_NAME__|Menotti|g' \
    -e 's|__GIT_USER_NAME__|mminutillo|g' \
    -e 's|__GIT_USER_EMAIL__|mminutillo@netflix.com|g' \
    -e 's|__SKILL_INSTALL_PATH__|/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog|g' \
    -e 's|__BACKUP_REPO_URL__|github.netflix.net/mminutillo/obsidian-vault|g' \
    "$f"
done
```

- [ ] **Step 4: Verify the live cache copy is clean and has the guard**

```bash
C=~/.claude/plugins/cache/personal/obsidian-worklog/5.10.0/skills/worklog/SKILL.md
grep -c '__[A-Z][A-Z_]\{3,\}__' "$C"          # expect 0
grep -c '^## Model Guard$' "$C"               # expect 1
grep -c 'run the Model Guard' "$C"            # expect 5
```
Expected: 0 placeholders, 1 guard section, 5 pointers.

---

### Task 6: Manual behavior verification

**Files:** none (runtime check).

- [ ] **Step 1: Verify the guard fires under a sub-Opus model**

In a Claude Code session set to Sonnet 5 (`/model`), run a guarded command, e.g. `/worklog viz quarter` or paste a long transcript and say "add to worklog". Expected: the skill pauses and asks whether to continue or switch, before doing the work.

- [ ] **Step 2: Verify it stays silent under Opus and asks only once**

Set the session to Opus 4.8 and run the same command. Expected: no guard prompt, proceeds directly. Back on Sonnet, answer "continue" once, then run a second guarded command in the same conversation. Expected: no second prompt.

- [ ] **Step 3: Verify light commands never trigger it**

On Sonnet, run `/worklog add P1 test item` and `/worklog audit`. Expected: no guard prompt for either.

---

## Self-Review

- **Spec coverage:** Detection (Task 1 section) ✓; five trigger points (Task 2) ✓; ask-once-per-conversation behavior (Task 1 section) ✓; non-goals of no-programmatic-detection / no-hard-gate / no-light-command guard (Task 1 section text + Task 6 Step 3) ✓; distribution version bump + resync (Tasks 3, 5) ✓; testing (Tasks 4, 6) ✓.
- **Placeholders:** No "TBD"/"TODO"; all step content is concrete. The `<your model>` token in the guard copy is intentional runtime substitution by the running model, not a plan placeholder.
- **Type/name consistency:** The heading `## Model Guard` and the pointer string `run the Model Guard (see \`## Model Guard\`)` are used identically in Tasks 1, 2, and 5 verification.
