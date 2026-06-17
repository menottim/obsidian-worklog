---
title: Cross-Link Index Helper — Design
date: 2026-06-17
status: draft
feature: cross-link-index
---

# Cross-Link Index Helper — Design

Replace the "glob `People/*.md` + `Programs/*.md` (and read bodies to resolve aliases) on
every write" step of the worklog skill's cross-linking flow with a single read-only bash
helper that returns a compact entity/alias digest. The model keeps all linking judgment;
it just stops loading the vault to discover entities. First of three independent
context-scaling sub-projects (the other two — note tiering/compaction and eval-gated
scale-invariance — get their own spec/plan/implementation cycles).

## Motivation

`SKILL.md §Cross-Linking` step 1 instructs, on every write to any vault file:

> 1. Glob `People/*.md` and `Programs/*.md` to get the current list of known entities

Today that is __272 People + 71 Programs = 343 files__, and resolving which "Brian" a
mention means — and what alias form to use — pulls note bodies into the model. This recurs
on _every_ edit (worklogs, people notes, program notes, archive), so it is the
highest-frequency context cost in the skill, even though it is dwarfed per-call by `audit`.

The work this helper removes is mechanical and already provably doable in bash:
`audit-scan.sh`'s `missing_links` check builds a throwaway name list (`mktemp` + `grep -Ff`)
and detects unlinked mentions entirely off-model. This sub-project promotes that throwaway
list into a first-class, alias-aware digest the _write_ path consumes.

The vault also already contains the disambiguation signal needed to make first-name aliases
safe: __355 distinct `[[Canonical|alias]]` forms__, dominated by a single referent
(`[[Brian Gaines|Brian]]` ×95, `[[Nick Siow|Nick]]` ×58, `[[Scott Behrens|Scott]]` ×48).
Mining observed usage is far higher-signal than splitting filenames.

## Goals

- Eliminate the 343-file glob and the body-reads-for-alias-resolution on every write,
  replacing them with one bash call returning a compact JSON digest.
- Resolve aliases the way the user already does: declared > observed > derived, with
  first-name collisions resolved by observed frequency and only genuinely-tied forms left
  for the model to disambiguate.
- Zero change to linking _judgment_: first-mention-only, heading linking, body cross-links,
  and the privacy model are untouched. Only entity discovery moves to bash.
- No new runtime dependencies (bash 3.2 + `jq`/`grep`/`awk`/`sed`, matching existing helpers).
- No persisted index file (compute fresh each call; no invalidation surface).

## Non-goals (this sub-project)

- Any auto-linking or text rewriting. The helper emits an index; the model wraps mentions.
  (Considered and rejected: linking judgment — first-mention, headings, code/frontmatter
  skipping, already-linked detection — is unsafe to encode in bash.)
- A mention-scan mode (given text → spans to wrap). Considered; deferred as YAGNI. The index
  fully solves the stated cost; the model has its own draft text in context already.
- Teams. Only 2 path-based `[[Teams/...]]` links exist in the whole vault and 0 in weeklies;
  Teams use a different link form and collide with Program names. The model links Teams
  manually as it does today.
- Refactoring `audit-scan.sh`'s `missing_links` to consume the shared index. Tempting DRY,
  but it risks the frozen audit-parity baseline (eval 9 hard gate). Future consolidation.
- Note tiering/compaction and eval-gated scale-invariance (separate sub-projects).
- A persisted index, subagent fanout, or model tiering.

## Architecture

A single read-only helper, invoked exactly like the existing scanners:

```
skills/worklog/scripts/cross-link-index.sh <vault-path>
```

From `SKILL.md` (after placeholder substitution by `setup.sh`):

```
__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh '__VAULT_PATH__'
```

The `__SKILL_INSTALL_PATH__/skills/worklog/scripts/` prefix is mandatory:
`__SKILL_INSTALL_PATH__` is the plugin _root_, so `skills/worklog/` must appear in the path.
(This is the exact v5.8.1 hotfix lesson — the literal substituted string must be the one
that gets verified, not an equivalent path.)

Conventions copied from `audit-scan.sh` / `preferences-index.sh`:
`set -euo pipefail`; vault arg required; `cd "$VAULT"`; `shopt -s nullglob`; bash 3.2
(while-read loops, no `mapfile`); `jq` for JSON; read-only (no writes anywhere).

### Output schema

One JSON object on stdout:

```json
{
  "entities": [
    { "canonical": "Astha Singhal",  "type": "person",  "aliases": ["Astha"] },
    { "canonical": "Brian Gaines",   "type": "person",  "aliases": ["Brian"],
      "alias_notes": [ { "alias": "Brian", "dominant": true, "alts": ["Brian Lee"] } ] },
    { "canonical": "Cloud Security", "type": "program", "aliases": [] }
  ],
  "ambiguous": {
    "Chris": ["Chris Vincent", "Chris Park"]
  },
  "meta": { "people": 272, "programs": 71, "generated_for": "<vault>" }
}
```

- `entities[].canonical` — filename minus `.md`. Always an implicit surface form itself.
- `entities[].type` — `person` or `program`, from frontmatter `type:` (fallback: source dir).
- `entities[].aliases` — surface forms the model may link __directly__: unambiguous aliases,
  plus the dominant referent of a contested first name.
- `entities[].alias_notes` — present only when a listed alias is _dominant-but-contested_;
  carries `dominant: true` and `alts` (the losing canonicals) so the model can override from
  context.
- `ambiguous` — surface form → all candidate canonicals, for collisions with __no__ clear
  winner. The helper deliberately does not resolve these; the model disambiguates from
  context. Not emitted under any entity's `aliases`.
- `meta` — counts + the vault path, for smoke assertions.

Case-matching is the model's responsibility (case-insensitive match against canonical and
aliases). The digest stays in canonical case and does not enumerate `cloud security` /
`Cloud Security` variants, keeping it lean. The skill's existing rule to alias case variants
(`[[Cloud Security|cloud security]]`) is unchanged.

### Alias resolution algorithm

Precedence: __declared → observed → derived__.

1. __Canonical + type__ — for each `People/*.md` and `Programs/*.md`: canonical = basename
   without `.md`; type from frontmatter `type:` (fallback to the source directory).
2. __Declared__ — parse the `aliases:` YAML list from frontmatter where present (~13 notes).
   Authoritative. bash 3.2 list parsing (no `mapfile`).
3. __Observed__ — one `grep -oE '\[\[[^]]+\|[^]]+\]\]'` pass over the vault; tally
   `alias → canonical` occurrence counts. Encodes the disambiguation already made by the
   user.
4. __Derived__ — first whitespace token of a multi-word person name. Skipped for
   single-token names. (Programs get no derived alias; their case-variant aliasing is the
   model's job.)
5. __Collision resolution__ — for any surface form claimed by ≥2 canonicals:
   - A declared (frontmatter) alias wins outright, regardless of counts.
   - Else if one referent's observed count is __≥3× the runner-up and ≥5 absolute__
     (`DOMINANCE`), emit it under that entity's `aliases` with
     `alias_notes {dominant: true, alts: [...]}`.
   - Else emit the surface form in top-level `ambiguous` with all candidates; it appears
     under no entity's `aliases`.

`DOMINANCE = (top ≥ 3×runner-up) AND (top ≥ 5)` is a tunable constant at the top of the
script. Rationale: `≥5 absolute` avoids promoting a barely-used alias; `≥3×` requires a clear
lead, so genuinely-split names (e.g. two roughly-equally-referenced people) fall to
`ambiguous` rather than guessing.

### Error handling

Mirrors `audit-scan.sh`:

- Missing/empty vault arg → usage message to stderr, exit 2.
- Vault dir not found → message to stderr, exit 2.
- Missing `People/` or `Programs/` → that type contributes an empty set (not an error).
- Names containing regex metacharacters → fixed-string matching (`grep -F`) wherever names
  are matched, so `[`, `.`, `*` in a name can't break the scan.
- Empty vault → `{ "entities": [], "ambiguous": {}, "meta": {...} }`.

## Integration

- __`SKILL.md §Cross-Linking` step 1__ changes from "Glob `People/*.md` and `Programs/*.md`
  …" to "Run `__SKILL_INSTALL_PATH__/skills/worklog/scripts/cross-link-index.sh
  '__VAULT_PATH__'` once to get the entity/alias digest; use it to recognize mentions, pick
  the canonical link target, and choose aliases (treat `ambiguous` entries as
  resolve-from-context)." Steps 2–7 (linking judgment) stay verbatim. The body-reading for
  alias resolution is removed because the digest carries aliases + dominance + ambiguity.
- __No new placeholder tokens.__ The helper takes the vault as an argument; the invocation
  line reuses `__SKILL_INSTALL_PATH__` and `__VAULT_PATH__`, both already substituted by
  `setup.sh`.
- __`audit-scan.sh` is untouched__ (protects eval 9 / the audit-parity baseline).
- __Versioning:__ feature → bump `5.8.3 → 5.9.0` in `.claude-plugin/plugin.json`. Commit to
  the fork; propagate to the live install via the distribution pipeline (republish to
  `personal-plugins`, `/plugin marketplace update personal`, restart). Public-upstream
  parity is out of scope (separate parity-workflow project).

## Testing

1. __Fixture unit test__ — a tiny synthetic vault under `tests/fixtures/`, asserting exact
   JSON for: an unambiguous alias (Astha → Astha Singhal); a dominant-but-contested first
   name (Brian, with `alts`); a true tie landing in `ambiguous`; a declared frontmatter alias
   overriding a derived collision; a single-name person (no first-token alias); a name with
   regex metacharacters (fixed-string safety); empty `People/`/`Programs/`.
2. __Real-vault smoke__ — run against the live vault; assert `meta.people == 272`,
   `meta.programs == 71`, `Astha` resolves clean, `Brian` carries `dominant`, and the digest
   is materially smaller than 343 file bodies.
3. __No-regression__ — run `tests/e2e-setup.sh`, and re-run `audit-scan.sh` against the
   baseline to confirm eval 9 still passes (we did not touch it).
4. __One behavioral eval__ added to `evals/evals.json` — given the digest, the model links a
   sample correctly without globbing, picks the dominant alias, and surfaces (does not
   auto-resolve) an ambiguous one. A light preview of the future scale-invariance suite.

## Open questions

None blocking. `DOMINANCE` thresholds (≥3×, ≥5) are tunable and validated by the fixture +
real-vault smoke; adjust if the smoke surfaces a miscategorized real-world name.
