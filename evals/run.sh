#!/usr/bin/env bash
# run.sh - run evals/evals.json cases headlessly across model/effort configs and
# report pass/fail alongside the cost the run actually billed.
#
#   evals/run.sh --cases 1,2,3,4 --configs haiku:low,sonnet:medium,opus:high
#
# Each run gets a throwaway plugin copy and a throwaway git-backed vault, with the
# skill's placeholders rendered at that vault. The graded artifact is `git diff`
# of the vault plus the model's final text.
#
# Isolation: --bare drops hooks, CLAUDE.md, auto-memory and plugin sync, so a
# result does not depend on whoever's machine ran it. The settings file is a
# derived copy carrying auth and nothing else. --strict-mcp-config drops every
# MCP server except a case's own fixture server.
#
# Containment is layered, because two runs escaped onto the real vault during
# development by two different routes:
#   - the settings copy drops enabledPlugins, so the real installed plugin cannot
#     load alongside the fixture copy
#   - only .claude-plugin and skills are staged, so the real vault path in the
#     repo's docs and defaults never enters the sandbox
#   - a pre-flight grep refuses to start if the staged copy names the real vault
#   - the real vault is fingerprinted before the batch and after every run
# Set WORKLOG_REAL_VAULT if your vault is not at ~/Documents/Obsidian Vault, or
# the last two layers silently disarm.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
CASES=""
CONFIGS="sonnet:medium"
# Headroom over the most expensive run observed (~$1.50, opus:high on audit). A
# run that hits the cap stops mid-task and grades as a quality failure, which is
# a confound, not a result.
BUDGET="${WORKLOG_EVAL_BUDGET:-5}"
TIMEOUT="${WORKLOG_EVAL_TIMEOUT:-600}"
KEEP=1
REPEAT=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cases)    CASES="$2"; shift 2 ;;
    --configs)  CONFIGS="$2"; shift 2 ;;
    --budget)   BUDGET="$2"; shift 2 ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    --repeat)   REPEAT="$2"; shift 2 ;;
    --no-keep)  KEEP=0; shift ;;
    *) echo "run.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$CASES" ] || { echo "run.sh: --cases is required" >&2; exit 2; }
case "$CASES" in *[!0-9,]*) echo "run.sh: --cases takes comma-separated ids: $CASES" >&2; exit 2 ;; esac
case "$REPEAT" in ''|*[!0-9]*) echo "run.sh: --repeat takes a positive integer: $REPEAT" >&2; exit 2 ;; esac
[ "$REPEAT" -ge 1 ] || { echo "run.sh: --repeat must be at least 1" >&2; exit 2; }

# --- containment -------------------------------------------------------------
# The user's settings file carries enabledPlugins, which pulls in the REAL
# installed obsidian-worklog plugin - already rendered with the real vault path -
# alongside the fixture copy passed via --plugin-dir. When that happened, runs
# followed the real skill and wrote to the real vault. Strip the plugin keys, and
# keep a tripwire on the real vault in case something else reaches it.
# Relocate the config dir so ~/.claude/plugins - which holds the REAL installed
# worklog plugin, rendered with the real vault path - does not exist as far as the
# run is concerned. Two skills named worklog otherwise compete, and the installed
# one sometimes wins: that is what escape #3 was, with enabledPlugins already
# stripped. HOME stays real so the CLI does not re-download its native build.
EVAL_CONFIG_DIR=""

HOST_SETTINGS="$HOME/.claude/settings.json"
[ -f "$HOST_SETTINGS" ] || {
  echo "run.sh: $HOST_SETTINGS not found; it is the only source of auth for --bare" >&2
  exit 2
}
EVAL_SETTINGS="$(mktemp -t worklog-eval-settings)"
trap 'rm -f "$EVAL_SETTINGS"' EXIT
python3 - "$HOST_SETTINGS" "$EVAL_SETTINGS" <<'PYSET'
import json, os, sys
src, dst = sys.argv[1:3]
s = json.load(open(src))
for k in ("enabledPlugins", "extraKnownMarketplaces", "hooks", "statusLine", "outputStyle"):
    s.pop(k, None)
fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(s, f)
PYSET

REAL_VAULT="${WORKLOG_REAL_VAULT:-$(ls -d "$HOME/Documents/Obsidian Vault" 2>/dev/null)}"
vault_fingerprint() {
  [ -n "$REAL_VAULT" ] && [ -d "$REAL_VAULT" ] || { echo "no-real-vault"; return; }
  git -C "$REAL_VAULT" status --porcelain 2>/dev/null | shasum | cut -d' ' -f1
}
GUARD_BASE="$(vault_fingerprint)"
if [ "$GUARD_BASE" = "no-real-vault" ]; then
  echo "run.sh: WARNING - real vault not found, containment tripwire is off" >&2
else
  echo "run.sh: tripwire armed on $REAL_VAULT"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
RUNDIR="$HERE/runs/$STAMP"
mkdir -p "$RUNDIR"
EVAL_CONFIG_DIR="$RUNDIR/claude-config"
mkdir -p "$EVAL_CONFIG_DIR"
CSV="$RUNDIR/results.csv"
echo "case,model,effort,rep,pass,checks_passed,checks_total,cost_usd,input_tokens,cache_read,cache_creation,output_tokens,seconds,turns" > "$CSV"

prompt_for() { # <case-id>
  python3 -c "
import json,sys
cid=int(sys.argv[1])
for c in json.load(open(sys.argv[2]))['evals']:
    if c['id']==cid:
        sys.stdout.write(c['prompt']); raise SystemExit
raise SystemExit('no case '+str(cid))
" "$1" "$HERE/evals.json"
}

for CASE in $(echo "$CASES" | tr ',' ' '); do
  ASSERT="$HERE/assertions/case-$CASE.sh"
  if [ ! -x "$ASSERT" ]; then
    echo "SKIP case $CASE: no assertion script at $ASSERT" >&2
    continue
  fi
  PROMPT="$(prompt_for "$CASE")" || { echo "SKIP case $CASE: not in evals.json" >&2; continue; }
  # Pull-case prompts in evals.json carry a trailing parenthetical describing the
  # fixture state, e.g. "/worklog pull (context-channel with a thread that clearly
  # names a program already tracked...)". That text is setup, and sending it would
  # hand the model the classification the case is meant to test. The scenario file
  # supplies the state instead, so strip it.
  if [ -f "$HERE/scenarios/case-$CASE.json" ]; then
    PROMPT="$(printf '%s' "$PROMPT" | sed -E 's/[[:space:]]*\(.*\)[[:space:]]*$//')"
  fi

  for CFG in $(echo "$CONFIGS" | tr ',' ' '); do
   for REP in $(seq 1 "$REPEAT"); do
    MODEL="${CFG%%:*}"
    EFFORT="${CFG##*:}"
    [ "$EFFORT" = "$MODEL" ] && EFFORT=""
    W="$RUNDIR/case$CASE-$MODEL-${EFFORT:-default}-r$REP"
    mkdir -p "$W"

    # Throwaway plugin copy. Copy ONLY what the plugin needs to load. The rest of
    # the repo - setup.sh's defaults, docs/superpowers/plans, and this runner
    # itself - contains the real vault path in plain text, and copying it into a
    # directory the model is free to read is how a run finds a vault it was never
    # supposed to touch.
    mkdir -p "$W/plugin"
    cp -R "$REPO/.claude-plugin" "$REPO/skills" "$W/plugin/"
    SCENARIO="$HERE/scenarios/case-$CASE.json"
    if [ -f "$SCENARIO" ]; then
      "$HERE/make-vault.sh" "$W/vault" --context-channel >/dev/null
    else
      "$HERE/make-vault.sh" "$W/vault" >/dev/null
    fi
    # Render every markdown file the skill can load, matching setup.sh. Rendering
    # SKILL.md alone leaves literal __VAULT_PATH__ in references/, which is a
    # configuration no real install produces - so the harness would be testing
    # something the user never runs.
    python3 - "$W/plugin/skills/worklog" "$W/vault" "$W/plugin" <<'PY'
import sys, pathlib
root, vault, install = sys.argv[1:4]
subs = (("__VAULT_PATH__", vault), ("__SKILL_INSTALL_PATH__", install),
        ("__USER_NAME__", "Eval User"), ("__GIT_USER_NAME__", "eval"),
        ("__GIT_USER_EMAIL__", "eval@example.com"), ("__BACKUP_REPO_URL__", "NONE"))
for f in sorted(pathlib.Path(root).rglob("*.md")):
    t = f.read_text()
    for k, v in subs:
        t = t.replace(k, v)
    f.write_text(t)
PY

    LEFT="$(grep -rlE '__(VAULT_PATH|SKILL_INSTALL_PATH|USER_NAME|GIT_USER_NAME|GIT_USER_EMAIL|BACKUP_REPO_URL)__' "$W/plugin/skills" 2>/dev/null)"
    if [ -n "$LEFT" ]; then
      echo "run.sh: ABORT - unrendered placeholders in the staged skill:" >&2
      printf '%s\n' "$LEFT" >&2
      exit 1
    fi

    if [ -n "$REAL_VAULT" ] && grep -rqF "$REAL_VAULT" "$W/plugin" 2>/dev/null; then
      echo "run.sh: ABORT - the staged plugin copy names the real vault. Refusing to run." >&2
      grep -rlF "$REAL_VAULT" "$W/plugin" >&2
      exit 1
    fi

    ARGS=(-p "$PROMPT" --bare --settings "$EVAL_SETTINGS"
          --plugin-dir "$W/plugin" --model "$MODEL"
          --output-format json --permission-mode acceptEdits
          --allowedTools Bash Read Edit Write Glob Grep Skill TodoWrite AskUserQuestion mcp__slack
          --strict-mcp-config --no-session-persistence
          --max-budget-usd "$BUDGET" --add-dir "$W/vault")
    [ -n "$EFFORT" ] && ARGS+=(--effort "$EFFORT")
    # Some cases need the model to know no human will answer, or the run measures
    # who asks a question rather than who does the work correctly. Cases whose
    # expected behavior IS to stop and ask get no such file.
    SYS="$HERE/prompts/case-$CASE.sysprompt"
    [ -f "$SYS" ] && ARGS+=(--append-system-prompt "$(cat "$SYS")")
    # Pull cases talk to a fixture Slack rather than the real one, so a result
    # does not depend on what happened to be in a channel that day.
    if [ -f "$SCENARIO" ]; then
      python3 - "$W/mcp.json" "$HERE/fake-slack/server.py" "$SCENARIO" <<'PYCFG'
import json, sys
cfg, server, scenario = sys.argv[1:4]
json.dump({"mcpServers": {"slack": {"command": "python3", "args": [server],
                                    "env": {"FAKE_SLACK_SCENARIO": scenario}}}},
          open(cfg, "w"))
PYCFG
      ARGS+=(--mcp-config "$W/mcp.json")
    fi

    printf 'case %-3s %-8s %-8s r%-2s ... ' "$CASE" "$MODEL" "${EFFORT:-default}" "$REP"
    START=$(date +%s)
    ( cd "$W" && CLAUDE_CONFIG_DIR="$EVAL_CONFIG_DIR" \
        timeout "$TIMEOUT" claude "${ARGS[@]}" < /dev/null ) \
      > "$W/result.json" 2>"$W/stderr.txt"
    RC=$?
    ELAPSED=$(( $(date +%s) - START ))

    if [ "$(vault_fingerprint)" != "$GUARD_BASE" ]; then
      echo
      echo "run.sh: ABORT - the real vault at $REAL_VAULT changed during case $CASE/$MODEL." >&2
      echo "run.sh: a run escaped its fixture. Inspect with: git -C '$REAL_VAULT' status" >&2
      echo "run.sh: artifacts for this run are in $W" >&2
      exit 1
    fi

    python3 - "$W" <<'PY'
import json, pathlib, sys
w = pathlib.Path(sys.argv[1])
raw = (w / "result.json").read_text()
try:
    d = json.loads(raw)
except Exception:
    (w / "metrics.json").write_text(json.dumps({"error": raw[:2000]}))
    (w / "out.txt").write_text(raw[:4000])
    raise SystemExit
u = d.get("usage", {})
(w / "out.txt").write_text(d.get("result") or "")
(w / "metrics.json").write_text(json.dumps({
    "cost_usd": d.get("total_cost_usd", 0),
    "turns": d.get("num_turns", 0),
    "input_tokens": u.get("input_tokens", 0),
    "cache_read": u.get("cache_read_input_tokens", 0),
    "cache_creation": u.get("cache_creation_input_tokens", 0),
    "output_tokens": u.get("output_tokens", 0),
    "is_error": d.get("is_error", False),
}, indent=1))
PY

    # Capture the vault mutation as the graded artifact.
    git -C "$W/vault" add -A >/dev/null 2>&1
    git -C "$W/vault" diff --cached > "$W/diff.txt" 2>/dev/null
    git -C "$W/vault" diff --cached --name-status > "$W/changed.txt" 2>/dev/null

    VAULT="$W/vault" OUT="$W/out.txt" DIFF="$W/diff.txt" CHANGED="$W/changed.txt" \
      "$ASSERT" > "$W/checks.txt" 2>&1
    FAILS=$?
    TOTAL=$(grep -c '^\(PASS\|FAIL\)' "$W/checks.txt")
    PASSED=$(grep -c '^PASS' "$W/checks.txt")
    if [ "$RC" -ne 0 ]; then VERDICT="error"; elif [ "$FAILS" -eq 0 ]; then VERDICT="pass"; else VERDICT="fail"; fi

    python3 - "$W" "$CASE" "$MODEL" "${EFFORT:-default}" "$REP" "$VERDICT" "$PASSED" "$TOTAL" "$ELAPSED" >> "$CSV" <<'PY'
import json, pathlib, sys
w, case, model, effort, rep, verdict, passed, total, secs = sys.argv[1:10]
m = json.loads((pathlib.Path(w) / "metrics.json").read_text())
print(",".join(str(x) for x in [
    case, model, effort, rep, verdict, passed, total,
    m.get("cost_usd", 0), m.get("input_tokens", 0), m.get("cache_read", 0),
    m.get("cache_creation", 0), m.get("output_tokens", 0), secs, m.get("turns", 0),
]))
PY
    COST=$(python3 -c "import json,sys;print('%.4f'%json.load(open(sys.argv[1])).get('cost_usd',0))" "$W/metrics.json")
    printf '%-5s %s/%s  $%s  %ss\n' "$VERDICT" "$PASSED" "$TOTAL" "$COST" "$ELAPSED"
    [ "$KEEP" -eq 1 ] || rm -rf "$W"
   done
  done
done

echo
echo "results: $CSV"
column -s, -t < "$CSV"
