#!/usr/bin/env bash
# Static compatibility checks for the shared Claude Code and Codex skill.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"
CODEX_MANIFEST="$REPO_ROOT/.codex-plugin/plugin.json"
SKILL="$REPO_ROOT/skills/worklog/SKILL.md"
NETFLIX_COMMANDS="$REPO_ROOT/skills/worklog/references/netflix-commands.md"
CODEX_ADAPTER="$REPO_ROOT/skills/worklog/references/netflix-tools-codex.md"
PULL_FLOW="$REPO_ROOT/skills/worklog/references/pull-flow.md"

failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n' "$label"
    failures=$((failures + 1))
  fi
}

manifest_version() {
  sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$1"
}

CLAUDE_VERSION="$(manifest_version "$CLAUDE_MANIFEST")"
CODEX_VERSION="$(manifest_version "$CODEX_MANIFEST")"

check "Claude manifest version is present" test -n "$CLAUDE_VERSION"
check "Codex manifest version is present" test -n "$CODEX_VERSION"
check "plugin manifest versions match" test "$CLAUDE_VERSION" = "$CODEX_VERSION"
check "Codex adapter exists" test -f "$CODEX_ADAPTER"
check "Codex document reads handle truncated responses" \
  grep -qF 'If the requested result has `truncated: true`' "$CODEX_ADAPTER"
check "Codex document reads use bounded pages" \
  grep -qF '`max_chars: 50000`' "$CODEX_ADAPTER"
check "Codex document reads advance start_offset" \
  grep -qF '`start_offset` advanced by the number of content characters returned so far' "$CODEX_ADAPTER"
check "Codex document reads stop on pagination stalls" \
  grep -qF 'does not advance the offset, stop before changing the' "$CODEX_ADAPTER"

for tool_id in \
  mcp__core_tools__fetch_slack_thread \
  mcp__core_tools__nusdgs_search_knowledge_base \
  mcp__core_tools__nusdgs_read_knowledge_base_content \
  mcp__atlassian_rovo__getAccessibleAtlassianResources \
  mcp__atlassian_rovo__getJiraIssue; do
  check "Codex adapter pins $tool_id" grep -qF "$tool_id" "$CODEX_ADAPTER"
done

check "Codex pull requires an exhaustive capability preflight" \
  grep -qF 'Codex capability preflight' "$PULL_FLOW"
check "Codex pull rejects Slack RAG cursor substitution" \
  grep -qF 'Do not substitute semantic/RAG Slack search' "$PULL_FLOW"
check "Codex pull preserves cursor on failed preflight" \
  grep -qF 'stop without advancing `last_scan_ts`' "$PULL_FLOW"

for tool_id in \
  mcp__core-tools__fetch-slack-thread \
  mcp__core-tools__netflix_search_data \
  mcp__core-tools__netflix_search_api \
  mcp__plugin_atlassian_atlassian__getJiraIssue; do
  check "Claude binding remains $tool_id" grep -qF "$tool_id" "$NETFLIX_COMMANDS"
done

check "shared skill keeps Claude's Opus guard" grep -qF 'If the host is Claude Code' "$SKILL"
check "shared skill bypasses Claude model choices in Codex" grep -qF 'If the host is Codex' "$SKILL"
check "Codex choices do not require AskUserQuestion" \
  grep -qF 'in Codex, use a concise plain-text question' "$PULL_FLOW"
check "shared edits do not require Claude's Edit tool" \
  sh -c "! grep -qF 'Use the Edit tool' '$SKILL' '$PULL_FLOW'"

if [[ "$failures" -ne 0 ]]; then
  printf '\n%d compatibility check(s) failed\n' "$failures"
  exit 1
fi

printf '\nAll Codex compatibility checks passed\n'
