# Worklog Model Guard - Design

- Status: `Approved`
- Date: `2026-07-01`
- Scope: `skills/worklog/SKILL.md` (prompt-level only), `.claude-plugin/plugin.json` (version bump)

## Problem

The worklog skill runs under whatever model the Claude Code session happens to be on, and it never signals when that choice matters. A/B testing showed the choice mostly does __not__ matter for interactive worklog work: on eight vault-only eval cases Opus 4.8 and Sonnet 5 tied 8/8. The one place a gap appeared was __heavy single-shot synthesis__: ingesting a large meeting transcript, a big Slack `pull`, a full visualization, or a bulk `tidy`/quarter synthesis. On those, a smaller model or lower effort is more likely to truncate, lose fidelity, or degrade. Today the skill gives the user no heads-up before spending effort on a heavy task under a model that may handle it less well.

## Goal

Before the skill executes a __heavy__ command while running on a __sub-Opus__ model, pause and ask the user whether to continue on the current model or switch to Opus 4.8 first. Keep it advisory, honest about its own limits, and low-friction (ask at most once per conversation).

## Non-goals

- No programmatic model detection. There is no reliable signal for the session model in the shell (no env var; only the running model knows its own identity). A detection script would be theater.
- No hard gate or block. The guard asks; it never refuses to run.
- No guard on light commands: `add`, `review`, `audit` (its heavy work is in bash), `rollover`, single-item ops, or monthly summary.
- No effort-based trigger. A model does not reliably know its own effort setting, so effort is mentioned as advice in the prompt but is not a trigger.

## Detection mechanism (soft, fail-open)

The guard instructs the running model to read its own identity from its context. Claude Code places a line such as "You are powered by the model named X" in the system prompt, so the model can self-report.

- If the model is confident it is __Opus-tier__ (Opus 4.x): proceed silently, no guard.
- If the model is confident it is __sub-Opus__ (Sonnet or Haiku tier): trigger the guard.
- If the model __cannot tell__: skip the guard silently. Fail open. Never guess or nag on uncertainty.

This is explicitly a soft, prompt-level check, not a reliable gate. That tradeoff is acceptable because the guard is advisory and low-cost.

## Trigger points

Five SKILL.md command sections each get a one-line pointer to the shared guard as their first step:

1. `### Processing raw input (meeting notes, Slack messages, transcripts)` - only when the input is substantial (a real transcript or a long notes doc), not a one-line add.
2. `### `/worklog pull``
3. `### `/worklog viz [period]``
4. `### `/worklog tidy``
5. `### `/worklog summary [period]`` - quarter synthesis only; monthly summary is lighter and excluded.

## Behavior

Add one shared section, `## Model Guard`, defining the check. When triggered (guarded command + sub-Opus + not already answered this conversation), the model pauses and asks, roughly:

> This is a heavy synthesis task and you're running on `<model>`. In testing, Opus 4.8 was the most reliable on large worklog inputs; smaller models can truncate or lose fidelity. Continue on `<model>`, or pause so you can switch (`/model` to Opus 4.8, ideally at high or xhigh effort) and re-run?

- On __continue__: proceed normally.
- On __switch__: state how (`/model`) and stop so the user can re-invoke.
- Ask __at most once per conversation__. Remember the user's answer and honor it for subsequent heavy commands in the same session.

## Distribution and rollout

- Edit `skills/worklog/SKILL.md`: add the `## Model Guard` section plus five one-line pointers. No new scripts.
- Bump `.claude-plugin/plugin.json` version `5.9.0` -> `5.10.0` (the plugin cache is keyed by version).
- Re-sync to the `personal-plugins` marketplace and the install cache per the distribution pipeline.
- The recommendation names Opus 4.8, which is also a sensible default for anyone who forks the skill.

## Testing

The guard is model-conditional, so it cannot be exercised by a single eval run under one model. Verification plan:

- Manual: run a heavy command (e.g., transcript ingestion) once under Sonnet (guard should ask) and once under Opus 4.8 (should proceed silently).
- Add an eval note in `evals/evals.json` describing the expected guard behavior for a heavy-command prompt, graded against "asks before proceeding when sub-Opus; silent when Opus-tier."
- Confirm light commands (`add`, `review`, `audit`) never trigger the guard.

## Rationale for the approach

A single shared `## Model Guard` section referenced by the guarded commands keeps the logic in one place, adds no scripts to maintain, and is a pure prompt-level change. A helper-script approach was rejected as infeasible (no reliable model signal in the shell). A separate `references/model-guard.md` file was considered but is unnecessary while the guard text is short; it can be split out later if it grows.
