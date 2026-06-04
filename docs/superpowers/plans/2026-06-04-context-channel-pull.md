# Context-Channel Pull Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second Slack source type — `context-channel` — to `/worklog pull` that sweeps high-traffic discussion channels, auto-folds high-confidence matches into existing worklog items, batches uncertain/new items for human approval, and drops noise.

**Architecture:** Extend the existing `Sources/`-driven `/worklog pull` flow with a `type` branch. `meeting-notes-via-email` keeps its per-thread `Meetings/` flow unchanged; `context-channel` runs a sweep → three-way classify (auto-fold / approval-batch / drop) → consolidated end-of-pull approval. No new vault folders; provenance is a Slack permalink in each folded sub-item. Spec: `docs/superpowers/specs/2026-06-04-context-channel-pull-design.md`.

**Tech Stack:** Markdown skill prose (`SKILL.md`), Claude Code plugin packaging (`plugin.json`, version-keyed cache), Slack MCP tools (`slack_read_channel`, `slack_read_thread`, `slack_search_channels`), `evals/evals.json` (LLM-judged scenarios), bash (`git`, `rsync`).

**Repo + propagation context (read before starting):**
- Canonical authoring repo: `~/obsidian-worklog/` — branch `main`, `origin` → `https://git.netflix.net/mminutillo/obsidian-worklog.git` (private fork), `upstream` → `github.com:menottim/obsidian-worklog` (public). All edits happen here.
- Commit identity is the repo default `Menotti Minutillo <mminutillo@netflix.com>` (matches existing history — do NOT use the personal `menottim` identity for this fork).
- The dev clone is AHEAD of the running marketplace/cache (it already has fork-only Netflix commands at `SKILL.md` line ~1340). Propagation in Task 8 brings the dev clone's full current state live, including those.
- Propagation mechanism (authoritative): edit dev clone → bump `plugin.json` version (the version string is the cache key) → `rsync -av --delete` the dev clone into the marketplace copy at `~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/` → `/reload-plugins` (or new session) creates a fresh `cache/.../5.5.0/` dir.
- `Sources/<channel>.md` config files are runtime data created during registration; they live in the Obsidian vault (`~/Documents/Obsidian Vault/Sources/`) and back up via `/worklog sync`. They are NOT part of this code change.

---

## Task 0: Pre-flight — branch, reconcile, relocate the spec

**Files:**
- Modify (git): `~/obsidian-worklog/` (branch + working tree)
- Create: `~/obsidian-worklog/docs/superpowers/specs/2026-06-04-context-channel-pull-design.md`
- Remove (stray copy): `~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/docs/superpowers/specs/2026-06-04-context-channel-pull-design.md`

- [ ] **Step 1: Sync the fork with its remote and confirm a clean base**

```bash
cd ~/obsidian-worklog
git fetch origin
git status
git log --oneline -3
```
Expected: on `main`; only untracked files are pre-existing (`.superpowers/`, `presentation/`, `docs/superpowers/specs/2026-04-14-presentation-design.md`). If `main` is behind `origin/main`, fast-forward: `git pull --ff-only origin main`.

- [ ] **Step 2: Create the feature branch**

```bash
cd ~/obsidian-worklog
git checkout -b feat/context-channel-pull
```
Expected: `Switched to a new branch 'feat/context-channel-pull'`.

- [ ] **Step 3: Relocate the spec into the canonical repo**

The spec was written to the marketplace copy by mistake. Move it to the dev clone so it survives the Task 8 rsync (which uses `--delete`).

```bash
mkdir -p ~/obsidian-worklog/docs/superpowers/specs
cp "/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/docs/superpowers/specs/2026-06-04-context-channel-pull-design.md" \
   ~/obsidian-worklog/docs/superpowers/specs/2026-06-04-context-channel-pull-design.md
rm "/Users/mminutillo/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/docs/superpowers/specs/2026-06-04-context-channel-pull-design.md"
```
Expected: spec now exists under `~/obsidian-worklog/docs/superpowers/specs/`.

- [ ] **Step 4: Read the current edit-target sections** (the dev clone differs from this session's running copy — anchor edits to the real file)

```bash
grep -n "^## Sources\|^### \`/worklog pull\`\|^## Important Behaviors\|meeting-notes-via-email" ~/obsidian-worklog/skills/worklog/SKILL.md | head -30
```
Read the `## Sources` section and the `### \`/worklog pull\`` section in full (use the Read tool on the line ranges grep reports) before editing in later tasks.

- [ ] **Step 5: Commit**

```bash
cd ~/obsidian-worklog
git add docs/superpowers/specs/2026-06-04-context-channel-pull-design.md
git commit -m "docs: add context-channel pull design spec"
```

---

## Task 1: Document the `context-channel` source type in the Sources schema

**Files:**
- Modify: `~/obsidian-worklog/skills/worklog/SKILL.md` (the `## Sources` section)

- [ ] **Step 1: Read the Sources section** to find the exact insertion point (after the `meeting-notes-via-email` frontmatter field docs, before `## Meetings`).

- [ ] **Step 2: Add the context-channel subsection**

Insert this block at the end of the `## Sources` section (after the `first_scan_lookback_days` field description, before the next `##` heading):

````markdown
### Source type: `context-channel`

A second source type for __high-traffic human-discussion channels__ you want swept
for worklog-relevant context (not forwarded-email meeting notes). Same registry,
same `Sources/<channel-name>.md` file shape — only `type` and the lookback default
differ:

```yaml
---
type: context-channel
channel_name: "#infrasec-leads"
channel_id: C0XXXXXXX
nudge_threshold_days: 5
last_scan_ts: null              # null on first run; advances per processed message
first_scan_lookback_days: 7     # smaller default than email sources (high-traffic)
---

# #infrasec-leads

Human-readable notes about this channel — what it's for, who's in it, why it's
worth sweeping.
```

Field semantics are identical to `meeting-notes-via-email` except:
- `type: context-channel` selects the sweep-and-classify pull flow (see `/worklog pull`).
- `first_scan_lookback_days` defaults to __7__ (not 14): a busy channel's first sweep
  over two weeks is large. Tunable per channel.

There are no `Meetings/` notes for this type — relevant content folds directly into
worklog items and People/Program/Team notes, with a Slack permalink for provenance.
````

- [ ] **Step 3: Verify consistency**

Re-read the edited `## Sources` section. Confirm: both source types are documented, the `type` field description now lists both values, and nothing in the `meeting-notes-via-email` docs was altered.

- [ ] **Step 4: Commit**

```bash
cd ~/obsidian-worklog
git add skills/worklog/SKILL.md
git commit -m "feat(pull): document context-channel source type in Sources schema"
```

---

## Task 2: Add the `type` branch and context-channel sweep flow to `/worklog pull`

**Files:**
- Modify: `~/obsidian-worklog/skills/worklog/SKILL.md` (the `### \`/worklog pull\`` section)

- [ ] **Step 1: Add the type-branch note at the top of the Pull flow**

Find the `__Pull flow:__` list in the `### \`/worklog pull\`` section. Immediately before its step 1 (or as a new step 0), insert:

````markdown
__Source-type branch:__ `/worklog pull` processes every `Sources/*.md`. For each
source, branch on `type`:
- `meeting-notes-via-email` → the per-thread flow documented below (unchanged).
- `context-channel` → the __Context-channel sweep flow__ below.

Uncertain and new candidates from all `context-channel` sources accumulate into a
single approval batch presented once, at the very end of the whole pull (after the
email sources finish their own inline paste/skip flow).
````

- [ ] **Step 2: Add the sweep-flow subsection**

After the existing email `__Pull flow:__` steps and before `__First-run registration:__`, insert this complete subsection:

````markdown
__Context-channel sweep flow:__

For each source with `type: context-channel`:

1. Compute the window: messages with `ts > last_scan_ts`. On first run
   (`last_scan_ts` is null), look back `first_scan_lookback_days` (default 7).
   Incremental only — never re-read messages already past `last_scan_ts`.
2. `slack_read_channel` to list top-level messages in the window. Exclude bots
   (`include_bots=false`); include the user's own messages. For each top-level
   message with replies, `slack_read_thread` to fetch the full thread.
3. Build the working set of __conversation units__: a unit is a thread (parent +
   its replies) or a standalone message. The thread is the unit of analysis.
4. __Volume guardrail:__ if a channel yields more than ~100 units, STOP and tell the
   user the count and the window, and ask whether to proceed, narrow the window, or
   skip this channel. Never silently truncate.
5. Classify each unit three ways (see __Three-way classification__).
6. Apply high-confidence matches immediately (see __What auto-fold writes__). Stage
   uncertain + new units for the approval batch.
7. Advance `last_scan_ts` per processed unit (resumable across a crash), then to the
   current time at the end of the channel.

__Three-way classification__ — judge each unit against the __entire vault__ (current
week, Backlog, `Archive/`, `People/`, `Programs/`, `Teams/`):

- __High-confidence match → auto-fold.__ The unit clearly concerns one specific
  existing worklog item, person, program, or team: it names the program/initiative,
  continues a thread already tracked as an item, or is the same people advancing the
  same topic.
- __Weak/uncertain match, OR genuinely new-but-worth-tracking → approval batch.__
  Weak = topically adjacent but not clearly the same item, could attach to more than
  one item, or concerns a tracked person/program without obviously-actionable
  context. New-worthy = matches nothing but is a decision, ownership change, risk,
  ask, commitment, or status change worth tracking. __Never force-fit a weak match —
  always ask.__ When torn between auto-fold and ask, choose ask.
- __Noise → drop silently.__ Banter, logistics, unrelated chatter, FYIs with no
  bearing on tracked work.

__What auto-fold writes__ — same shape as the __Processing raw input__ pipeline:

- A dated sub-item under the matched worklog item:
  `  - <concise summary> ([#channel-name](<slack-permalink>), <Mon D>)` — date from
  the Slack message timestamp (user's local TZ), wiki-linking known
  people/programs/teams and creating stubs per the Cross-Linking rules.
- Substantive context appended to a matched Person/Program/Team note when the unit is
  about that entity.
- Summarize, do not transcribe; the genericize-at-the-public-boundary rule applies
  later, at publish time. The Slack permalink is the provenance (no `Meetings/` note).
- Regenerate enriched frontmatter only if a top-level item was added/changed; pure
  sub-item adds skip regeneration.

__Approval batch (human-in-the-loop)__ — after every source is swept (email +
context), if any uncertain/new candidates were staged, present ONE consolidated
numbered checklist in chat:

```
Context-channel pull — N items need your call:

1. [#infrasec-leads · Jun 4] <one-line summary>
   → Might relate to [[GCP CSPM tool evaluation]] — attach as sub-item? (uncertain match)
   permalink: <url>

2. [#side-team · Jun 3] <one-line summary>
   → No match. Looks new — suggest P1 under "SPA Programs": "<proposed title>". Add?
   permalink: <url>
…
Reply e.g.: "add 1; 2 as P2 under Cloud Security; skip 3; 4 attach to [[Triage SIDE]]"
```

Each entry carries: source channel, date, one-line summary, the proposed action
(attach to `[[item]]` as sub-item / new `P?` item under `<subgroup>` / new Backlog
item), and the permalink. The user approves / rejects / edits in bulk free text. This
is a chat checklist, not `AskUserQuestion` (batches exceed its 4-option cap). On the
response, apply approved additions (dated with the Slack timestamp, wiki-linked,
permalink provenance) and regenerate frontmatter if any top-level items were added.
````

- [ ] **Step 3: Extend the pull summary**

Find the pull-flow summary step ("Print a summary: …"). Replace it (or add alongside the email summary) so context-channels report, per channel:
`N scanned · M auto-folded · J surfaced for approval · K dropped as noise`, then __itemize each auto-fold__ (summary + target item + permalink) so a mis-fold is visible and undoable, then the approval-batch results, then the new `last_scan_ts` per source.

Insert this text into the summary step:

````markdown
For `context-channel` sources, the summary additionally reports, per channel:
`N scanned · M auto-folded · J surfaced for approval · K dropped`, then itemizes each
auto-fold (one line: summary → target item, with permalink) so any mis-classification
is visible and can be undone, followed by the approval-batch outcomes.
````

- [ ] **Step 4: Verify consistency**

Re-read the `### \`/worklog pull\`` section end to end. Confirm: the email flow steps are unchanged; the branch note, sweep flow, classification, approval batch, and summary additions all reference `last_scan_ts`, `first_scan_lookback_days`, and the entity-linking rules consistently with Task 1's schema.

- [ ] **Step 5: Commit**

```bash
cd ~/obsidian-worklog
git add skills/worklog/SKILL.md
git commit -m "feat(pull): add context-channel sweep, 3-way classify, approval batch"
```

---

## Task 3: Update registration and nudge/behavior references for two types

**Files:**
- Modify: `~/obsidian-worklog/skills/worklog/SKILL.md` (`__First-run registration:__`, `__Adding a new source inline:__`, the nudge text, `## Important Behaviors`)

- [ ] **Step 1: Extend inline registration with a type choice**

In `__Adding a new source inline:__` (and the first-run registration), add handling for context channels. Insert after the existing email-source registration description:

````markdown
__Registering a context channel:__ when the user says "register `#X` as a context
channel" (or hands over a list of important channels to sweep), resolve each via
`slack_search_channels`, confirm, and write `Sources/<channel-name>.md` with
`type: context-channel`, `last_scan_ts: null`, `first_scan_lookback_days: 7`,
`nudge_threshold_days: 5`. One file per channel (preserves per-channel state). The
list is the input to registration, not a stored config blob. Then run the first sweep
for the newly-registered channel(s).
````

- [ ] **Step 2: Confirm the nudge covers both types**

The stale-channel nudge iterates `Sources/*.md` and is type-agnostic, so it already covers context channels. Verify the nudge wording doesn't hardcode "meeting-notes" language; if it does, generalize to "last pulled `#<channel>` N days ago." No behavior change needed beyond wording.

- [ ] **Step 3: Note the second type in Important Behaviors**

In `## Important Behaviors`, find the bullet describing `/worklog pull` / sources (if present) and add a sentence: context channels are swept and relevance-folded, never written as `Meetings/` notes. If no such bullet exists, add one short bullet.

- [ ] **Step 4: Verify + Commit**

Re-read the touched spots for consistency, then:
```bash
cd ~/obsidian-worklog
git add skills/worklog/SKILL.md
git commit -m "feat(pull): support context-channel registration; generalize nudge wording"
```

---

## Task 4: Bump plugin version and description

**Files:**
- Modify: `~/obsidian-worklog/.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version 5.4.1 → 5.5.0**

Change `"version": "5.4.1"` to `"version": "5.5.0"`.

- [ ] **Step 2: Update the description**

Append to the description string a phrase noting the new capability, e.g.:
`… and Slack channel inbox (two source types: forwarded-email meeting notes, and context-channel relevance sweep that folds discussion into the worklog with an approval gate for new items).`

- [ ] **Step 3: Validate JSON**

```bash
cd ~/obsidian-worklog
python3 -m json.tool .claude-plugin/plugin.json > /dev/null && echo "valid JSON"
```
Expected: `valid JSON`.

- [ ] **Step 4: Commit**

```bash
cd ~/obsidian-worklog
git add .claude-plugin/plugin.json
git commit -m "chore: bump obsidian-worklog to 5.5.0 (context-channel pull)"
```

---

## Task 5: Add eval scenarios for context-channel pull

**Files:**
- Modify: `~/obsidian-worklog/evals/evals.json` (append to the `evals` array; last existing id is 14)

- [ ] **Step 1: Append evals 15–20**

Insert these objects at the end of the `evals` array (after the id-14 object; add a comma after the id-14 closing brace):

```json
    {
      "id": 15,
      "prompt": "/worklog pull (one meeting-notes-via-email source and one context-channel source registered)",
      "expected_output": "Should branch on type: run the existing per-thread Meetings flow for the email source, and the sweep-and-classify flow for the context-channel source. The two must not interfere. Context-channel must NOT create Meetings/ notes. Email source behavior is unchanged.",
      "issue_tested": "Source-type branch - both pull modes coexist in one /worklog pull"
    },
    {
      "id": 16,
      "prompt": "/worklog pull (context-channel with a thread that clearly names a program already tracked as a worklog item)",
      "expected_output": "Should classify the thread as a high-confidence match and auto-fold it as a dated sub-item under the matching worklog item, wiki-linked, with a Slack permalink for provenance and the Slack timestamp as the date. Should NOT prompt for this item. Should list the auto-fold in the end-of-pull summary (summary -> target item + permalink).",
      "issue_tested": "High-confidence match auto-folds with provenance and is itemized in the summary"
    },
    {
      "id": 17,
      "prompt": "/worklog pull (context-channel with one weakly-related thread and one clearly-new decision thread)",
      "expected_output": "Should stage BOTH into a single end-of-pull approval batch (a numbered chat checklist) - the weak one as an uncertain match proposing attachment to a candidate item, the new one as a proposed new item with priority and subgroup. Nothing is written until the user responds. Should never force-fit the weak match. A bulk reply (e.g. 'add 1; 2 as P2 under X; skip') applies edits correctly and regenerates frontmatter only if a top-level item was added.",
      "issue_tested": "Weak + new candidates batch for approval; no force-fit; bulk edit applies"
    },
    {
      "id": 18,
      "prompt": "/worklog pull (context-channel containing only unrelated banter and logistics)",
      "expected_output": "Should classify all units as noise and drop them silently - zero writes to any worklog item or note, no approval-batch entries. The summary reports them as dropped (count only).",
      "issue_tested": "Noise is dropped silently with no writes"
    },
    {
      "id": 19,
      "prompt": "/worklog pull (run a second time within seconds against the same context-channel, no new Slack content)",
      "expected_output": "Should be idempotent: ts > last_scan_ts yields no new units, so no auto-folds, no approval batch, no writes. last_scan_ts advances to current time. Summary reports 0 scanned/0 folded/0 surfaced/0 dropped for that channel.",
      "issue_tested": "Context-channel idempotency via last_scan_ts"
    },
    {
      "id": 20,
      "prompt": "/worklog pull (context-channel whose window contains more than ~100 conversation units)",
      "expected_output": "Should hit the volume guardrail: stop and tell the user the unit count and the window, and ask whether to proceed, narrow the window, or skip the channel. Should NOT silently truncate or silently analyze only a subset.",
      "issue_tested": "Volume guardrail - no silent truncation on large windows"
    }
```

- [ ] **Step 2: Validate JSON**

```bash
cd ~/obsidian-worklog
python3 -m json.tool evals/evals.json > /dev/null && echo "valid JSON"
```
Expected: `valid JSON`.

- [ ] **Step 3: Commit**

```bash
cd ~/obsidian-worklog
git add evals/evals.json
git commit -m "test: add context-channel pull eval scenarios (15-20)"
```

---

## Task 6: Update README for the two source types

**Files:**
- Modify: `~/obsidian-worklog/README.md`

- [ ] **Step 1: Locate the relevant sections**

```bash
grep -n "pull\|source\|meeting-notes\|What You Get\|## FAQ\|Slack" ~/obsidian-worklog/README.md | head -30
```

- [ ] **Step 2: Update the "What You Get" / Slack bullet**

Edit the Slack-ingest bullet to mention __two source types__: (1) `meeting-notes-via-email` (forwarded-email meeting notes → `Meetings/` notes + action items), and (2) `context-channel` (sweeps an important channel, folds relevant discussion into existing worklog items, and gates genuinely-new items behind an approval batch).

- [ ] **Step 3: Add a FAQ entry**

Add one Q/A under the FAQ:
`Q: What's the difference between the two Slack source types? A: meeting-notes-via-email treats one forwarded-email thread as one meeting and saves a Meetings/ note per thread. context-channel sweeps a busy discussion channel since the last pull, auto-folds high-confidence matches into the items they relate to (with a Slack permalink), asks before adding anything new or uncertain, and drops noise — no per-thread files.`

- [ ] **Step 4: Commit**

```bash
cd ~/obsidian-worklog
git add README.md
git commit -m "docs: README covers both pull source types"
```

---

## Task 7: Self-review against the spec

- [ ] **Step 1: Re-read the spec and grep the skill for each requirement**

```bash
cd ~/obsidian-worklog
grep -n "context-channel\|auto-fold\|approval batch\|three-way\|Volume guardrail\|first_scan_lookback_days: 7" skills/worklog/SKILL.md
```
Confirm a SKILL.md home for each spec section: new type, sweep flow, three-way classify, auto-fold-writes, approval batch, summary itemization, volume guardrail, registration, nudge. List and fix any gap inline (re-commit if fixed).

- [ ] **Step 2: Consistency check**

Confirm field/term names match across Tasks 1–3: `context-channel`, `last_scan_ts`, `first_scan_lookback_days`, `nudge_threshold_days`, and that the summary text and classification buckets use identical wording everywhere.

---

## Task 8: Propagate to the running marketplace/cache and reload

> This makes the dev clone's CURRENT state live — including the pre-existing fork-only Netflix commands the running cache lacks. Confirm with the user this is intended before running (it is, per the "fork is home + propagate" decision, but flag it).

**Files:**
- Sync: `~/obsidian-worklog/` → `~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/`

- [ ] **Step 1: Dry-run the sync to preview what changes**

```bash
rsync -avn --delete \
  --exclude '.git' \
  ~/obsidian-worklog/ \
  ~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/
```
Review the file list. Expect SKILL.md, plugin.json, evals.json, README.md, and docs/ updates; the fork-only command content arrives too. No surprises outside the plugin tree.

- [ ] **Step 2: Run the sync for real**

```bash
rsync -av --delete \
  --exclude '.git' \
  ~/obsidian-worklog/ \
  ~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/
```

- [ ] **Step 3: Confirm the marketplace copy now matches and shows 5.5.0**

```bash
diff -q ~/obsidian-worklog/skills/worklog/SKILL.md \
  ~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/skills/worklog/SKILL.md && echo "SKILL.md in sync"
grep '"version"' ~/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog/.claude-plugin/plugin.json
```
Expected: `SKILL.md in sync` and `"version": "5.5.0"`.

- [ ] **Step 4: Reload plugins to rebuild the cache at 5.5.0**

Run `/reload-plugins` in the Claude Code session (or start a new session). Then verify the new cache dir exists:
```bash
ls ~/.claude/plugins/cache/personal/obsidian-worklog/
```
Expected: a `5.5.0` directory appears (the version bump is the cache key).

---

## Task 9: Manual smoke test (live)

> Requires the user's channel list and a live Slack pull. Do with the user.

- [ ] **Step 1: Register one real context channel**

Ask the user for one important channel. Register it: resolve via `slack_search_channels`, write `~/Documents/Obsidian Vault/Sources/<channel>.md` with `type: context-channel`, `first_scan_lookback_days: 7`, `last_scan_ts: null`.

- [ ] **Step 2: Run `/worklog pull` and verify**

Confirm: high-confidence discussion folds under the right items with a working permalink and a Slack-timestamp date; the approval batch lists uncertain/new candidates with sensible proposed actions; bulk approve/edit/skip applies correctly; the summary itemizes auto-folds and reports scanned/folded/surfaced/dropped.

- [ ] **Step 3: Re-run immediately and confirm idempotency**

A second `/worklog pull` with no new Slack content makes zero changes for that channel.

- [ ] **Step 4: Back up config via `/worklog sync`**

Run `/worklog sync` so the new `Sources/<channel>.md` and the updated `.skills/worklog/SKILL.md` are committed to the vault repo.

---

## Task 10: Push the fork (USER-AUTHORIZED)

> Per the user's commit-only-when-asked rule, do NOT push without explicit go-ahead.

- [ ] **Step 1: Push the feature branch to the private fork**

```bash
cd ~/obsidian-worklog
git push -u origin feat/context-channel-pull
```
Origin is `https://git.netflix.net/mminutillo/obsidian-worklog.git` (private). Do NOT push to `upstream` (public) — this is internal-Slack-channel functionality; any upstream contribution requires a separate scrubbed cherry-pick per the fork's contribute-back rule.

- [ ] **Step 2: Open a PR or fast-forward `main`**

Per the user's preference: either open a PR on git.netflix.net, or `git checkout main && git merge --ff-only feat/context-channel-pull && git push origin main`. Ask which.
