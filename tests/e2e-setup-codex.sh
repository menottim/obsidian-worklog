#!/usr/bin/env bash
# End-to-end test for the additive Codex installer.

set -euo pipefail

SOURCE_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ID="$$"
TEST_REPO="/tmp/worklog-codex-repo-$TEST_ID"
TEST_VAULT="/tmp/worklog-codex-vault-$TEST_ID"
TEST_BUNDLE="$HOME/.codex/plugins/obsidian-worklog-e2e-$TEST_ID"
TEST_LINK="$HOME/.agents/skills/obsidian-worklog-e2e-$TEST_ID"
TEST_LOG="/tmp/worklog-codex-setup-$TEST_ID.log"
ESCAPE_ROOT="/tmp/worklog-codex-escape-$TEST_ID"
ESCAPE_LINK="$HOME/.codex/plugins/obsidian-worklog-e2e-link-$TEST_ID"
ESCAPE_SKILL_LINK="$HOME/.agents/skills/obsidian-worklog-e2e-escape-$TEST_ID"
CUSTOM_TEMPLATE_SENTINEL="custom-template-$TEST_ID"

cleanup() {
  rm -rf "$TEST_REPO" "$TEST_VAULT" "$TEST_BUNDLE" "$TEST_LINK" "$TEST_LOG" \
    "$ESCAPE_ROOT" "$ESCAPE_LINK" "$ESCAPE_SKILL_LINK"
}
trap cleanup EXIT

git clone --quiet "$SOURCE_REPO" "$TEST_REPO"
# Exercise the current installer when this test runs before its changes are committed.
cp "$SOURCE_REPO/setup-codex.sh" "$TEST_REPO/setup-codex.sh"

# Simulate a clone that Claude's setup has already rendered. Codex setup must
# recover the committed template for its own copy without resetting this file.
CLAUDE_SENTINEL="/tmp/existing-claude-vault-$TEST_ID"
if sed --version >/dev/null 2>&1; then
  sed -i "s|__VAULT_PATH__|$CLAUDE_SENTINEL|g" "$TEST_REPO/skills/worklog/SKILL.md"
else
  sed -i '' "s|__VAULT_PATH__|$CLAUDE_SENTINEL|g" "$TEST_REPO/skills/worklog/SKILL.md"
fi

mkdir -p "$TEST_VAULT/Templates"
printf '%s\n' "$CUSTOM_TEMPLATE_SENTINEL" > "$TEST_VAULT/Templates/Weekly.md"

set +e
(
  cd "$TEST_REPO"
  ./setup-codex.sh <<EOF >"$TEST_LOG" 2>&1
$TEST_VAULT
Codex Test User
Codex Test User
codex-test@example.com
NONE
$TEST_BUNDLE
$TEST_LINK
y
EOF
)
SETUP_EXIT=$?
set -e

if [[ "$SETUP_EXIT" -ne 0 ]]; then
  printf 'FAIL: setup-codex.sh exited %s\n\n' "$SETUP_EXIT"
  sed -n '1,240p' "$TEST_LOG"
  exit 1
fi

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

check "setup completed" grep -qF 'Setup complete' "$TEST_LOG"
check "Claude-rendered source remains untouched" grep -qF "$CLAUDE_SENTINEL" "$TEST_REPO/skills/worklog/SKILL.md"
check "installed skill is rendered" grep -qF "$TEST_VAULT" "$TEST_BUNDLE/skills/worklog/SKILL.md"
check "installed skill has no vault placeholder" sh -c "! grep -qF '__VAULT_PATH__' '$TEST_BUNDLE/skills/worklog/SKILL.md'"
check "Codex manifest installed" test -f "$TEST_BUNDLE/.codex-plugin/plugin.json"
check "Claude manifest retained" test -f "$TEST_BUNDLE/.claude-plugin/plugin.json"
check "skill discovery link created" test -L "$TEST_LINK"
check "skill discovery link resolves" test -f "$TEST_LINK/SKILL.md"
check "existing weekly template preserved" \
  grep -qF "$CUSTOM_TEMPLATE_SENTINEL" "$TEST_VAULT/Templates/Weekly.md"

for sub in Worklogs People Programs Teams Meetings Sources Preferences Archive Summaries Reports Templates Logs References; do
  check "vault has $sub" test -d "$TEST_VAULT/$sub"
done

# A lexically valid path whose parent resolves outside the guarded plugin root
# must fail without deleting the outside target.
mkdir -p "$ESCAPE_ROOT/victim"
printf 'outside sentinel\n' > "$ESCAPE_ROOT/victim/sentinel"
ln -s "$ESCAPE_ROOT" "$ESCAPE_LINK"
set +e
(
  cd "$TEST_REPO"
  ./setup-codex.sh <<EOF >>"$TEST_LOG" 2>&1
$TEST_VAULT
Codex Test User
Codex Test User
codex-test@example.com
NONE
$ESCAPE_LINK/victim
$ESCAPE_SKILL_LINK
y
EOF
)
ESCAPE_EXIT=$?
set -e
check "symlink escape path rejected" test "$ESCAPE_EXIT" -ne 0
check "symlink escape target preserved" test -f "$ESCAPE_ROOT/victim/sentinel"

# A successful upgrade must replace the bundle while preserving the template.
printf 'old bundle sentinel\n' > "$TEST_BUNDLE/old-bundle-sentinel"
set +e
(
  cd "$TEST_REPO"
  ./setup-codex.sh <<EOF >>"$TEST_LOG" 2>&1
$TEST_VAULT
Codex Test User
Codex Test User
codex-test@example.com
NONE
$TEST_BUNDLE
$TEST_LINK
y
y
y
EOF
)
UPGRADE_EXIT=$?
set -e
check "successful staged upgrade returns zero" test "$UPGRADE_EXIT" -eq 0
check "successful staged upgrade replaces old bundle" \
  test ! -e "$TEST_BUNDLE/old-bundle-sentinel"
check "successful staged upgrade keeps skill link valid" test -f "$TEST_LINK/SKILL.md"
check "successful staged upgrade preserves template" \
  grep -qF "$CUSTOM_TEMPLATE_SENTINEL" "$TEST_VAULT/Templates/Weekly.md"

# A failed staged copy must leave the prior installed bundle intact.
printf 'existing bundle sentinel\n' > "$TEST_BUNDLE/existing-bundle-sentinel"
mv "$TEST_REPO/README.md" "$TEST_REPO/README.md.missing"
set +e
(
  cd "$TEST_REPO"
  ./setup-codex.sh <<EOF >>"$TEST_LOG" 2>&1
$TEST_VAULT
Codex Test User
Codex Test User
codex-test@example.com
NONE
$TEST_BUNDLE
$TEST_LINK
y
y
y
EOF
)
FAILED_UPGRADE_EXIT=$?
set -e
check "failed staged upgrade returns nonzero" test "$FAILED_UPGRADE_EXIT" -ne 0
check "failed staged upgrade preserves existing bundle" \
  test -f "$TEST_BUNDLE/existing-bundle-sentinel"

# A post-swap skill-link failure must restore both the prior bundle and link.
mv "$TEST_REPO/README.md.missing" "$TEST_REPO/README.md"
printf 'post-swap bundle sentinel\n' > "$TEST_BUNDLE/post-swap-bundle-sentinel"
set +e
(
  ln() {
    return 1
  }
  export -f ln
  cd "$TEST_REPO"
  ./setup-codex.sh <<EOF >>"$TEST_LOG" 2>&1
$TEST_VAULT
Codex Test User
Codex Test User
codex-test@example.com
NONE
$TEST_BUNDLE
$TEST_LINK
y
y
y
EOF
)
LINK_FAILURE_EXIT=$?
set -e
check "post-swap skill-link failure returns nonzero" test "$LINK_FAILURE_EXIT" -ne 0
check "post-swap skill-link failure restores existing bundle" \
  test -f "$TEST_BUNDLE/post-swap-bundle-sentinel"
check "post-swap skill-link failure restores existing link" \
  test -f "$TEST_LINK/SKILL.md"

if [[ "$failures" -ne 0 ]]; then
  printf '\nInstaller log:\n'
  sed -n '1,240p' "$TEST_LOG"
  exit 1
fi
