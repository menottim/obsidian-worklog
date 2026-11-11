#!/usr/bin/env bash
# setup-codex.sh - Configure a Codex installation without modifying the source tree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SKILL="$REPO_ROOT/skills/worklog/SKILL.md"
TEMPLATES_DIR="$REPO_ROOT/templates"

prompt_with_default() {
  local prompt="$1" default="$2" result
  read -r -p "$prompt [$default]: " result
  printf '%s\n' "${result:-$default}"
}

escape_for_sed() {
  printf '%s' "$1" | sed 's/[|&\\/]/\\&/g'
}

sed_inplace() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

fail() {
  printf '\nFAIL: %s\n' "$*" >&2
  exit 1
}

validate_email() {
  [[ "$1" =~ ^[^@]+@[^@]+\.[^@]+$ ]]
}

validate_child_path() {
  local path="$1" root="$2" label="$3"
  case "$path" in
    "$root"/*) ;;
    *) fail "$label must be under $root (got: $path)" ;;
  esac
  case "$path" in
    *..*) fail "$label must not contain '..' (got: $path)" ;;
  esac
}

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

validate_resolved_parent() {
  local path="$1" root="$2" label="$3"
  local parent resolved_parent resolved_root

  parent="$(dirname "$path")"
  while [[ ! -d "$parent" ]]; do
    [[ "$parent" != "/" ]] || fail "Could not resolve parent for $label: $path"
    parent="$(dirname "$parent")"
  done

  resolved_root="$(canonical_dir "$root")" \
    || fail "Could not resolve guarded root for $label: $root"
  resolved_parent="$(canonical_dir "$parent")" \
    || fail "Could not resolve parent for $label: $parent"

  case "$resolved_parent" in
    "$resolved_root"|"$resolved_root"/*) ;;
    *) fail "$label resolves outside $root through a symlink (got: $path)" ;;
  esac
}

[[ -f "$SOURCE_SKILL" ]] || fail "Source skill is missing: $SOURCE_SKILL"
[[ -f "$TEMPLATES_DIR/Weekly.md" ]] || fail "Weekly template is missing"

printf '\n=== obsidian-worklog setup for Codex ===\n\n'
printf 'This installs a rendered bundle under ~/.codex and exposes its skill through ~/.agents.\n'
printf 'The repository source and Claude installation are not modified.\n\n'

DEFAULT_VAULT="$HOME/Documents/Obsidian Vault"
VAULT_PATH="$(prompt_with_default "Obsidian vault path" "$DEFAULT_VAULT")"
VAULT_SUBDIRS=(
  Worklogs People Programs Threads Teams Meetings Sources Preferences
  Archive Summaries Reports Templates Logs References
)

if [[ ! -d "$VAULT_PATH" ]]; then
  printf '\nDirectory does not exist: %s\n' "$VAULT_PATH"
  read -r -p "Create vault directory structure now? [Y/n]: " create_vault
  case "$create_vault" in
    n|N|no|No|NO) fail "Vault directory is required" ;;
  esac
fi
for sub in "${VAULT_SUBDIRS[@]}"; do
  mkdir -p "$VAULT_PATH/$sub" || fail "Could not create $VAULT_PATH/$sub"
done

DEFAULT_DISPLAY_NAME="$(whoami)"
DISPLAY_NAME="$(prompt_with_default "Your display name" "$DEFAULT_DISPLAY_NAME")"

DEFAULT_GIT_NAME="$(git config --global --get user.name 2>/dev/null || whoami)"
GIT_USER_NAME="$(prompt_with_default "Git user.name for vault commits" "$DEFAULT_GIT_NAME")"

DEFAULT_GIT_EMAIL="$(git config --global --get user.email 2>/dev/null || true)"
while true; do
  GIT_USER_EMAIL="$(prompt_with_default "Git user.email for vault commits" "$DEFAULT_GIT_EMAIL")"
  validate_email "$GIT_USER_EMAIL" && break
  printf '  Enter a valid email address.\n'
done

BACKUP_REPO_URL="$(prompt_with_default "Backup repo URL (enter NONE to skip)" "NONE")"

AUTO_SYNC_SCRIPT="$REPO_ROOT/skills/worklog/scripts/auto-sync.sh"
AUTO_SYNC_NOTE="$VAULT_PATH/Preferences/Auto Sync.md"
AUTO_SYNC_WRITE="" # on or off; written only after "Apply these settings?" is confirmed
AUTO_SYNC_SUMMARY=""
if [[ -f "$AUTO_SYNC_NOTE" ]]; then
  AUTO_SYNC_SUMMARY="$("$AUTO_SYNC_SCRIPT" "$VAULT_PATH" get) (kept from Preferences/Auto Sync.md)"
  printf 'Auto sync: %s\n' "$AUTO_SYNC_SUMMARY"
else
  AUTO_SYNC_REASON=""
  if [[ "$BACKUP_REPO_URL" == "NONE" ]]; then
    AUTO_SYNC_REASON="no backup repo"
  elif ! SYNC_CHECK="$("$AUTO_SYNC_SCRIPT" "$VAULT_PATH" can-sync)"; then
    AUTO_SYNC_REASON="$SYNC_CHECK"
  fi
  if [[ -n "$AUTO_SYNC_REASON" ]]; then
    AUTO_SYNC_WRITE="off"
    AUTO_SYNC_SUMMARY="off ($AUTO_SYNC_REASON)"
    printf 'Auto sync: %s\n' "$AUTO_SYNC_SUMMARY"
  else
    # printf, not read -p: bash shows the -p prompt only on a terminal, so piped runs would not log the question
    printf '%s' "Sync the vault automatically after each change? [Y/n]: "
    read -r auto_sync_answer
    case "$auto_sync_answer" in
      n|N|no|No|NO) AUTO_SYNC_WRITE="off" ;;
      *)            AUTO_SYNC_WRITE="on" ;;
    esac
    AUTO_SYNC_SUMMARY="$AUTO_SYNC_WRITE"
  fi
fi
DEFAULT_BUNDLE_PATH="$HOME/.codex/plugins/obsidian-worklog"
DEFAULT_SKILL_LINK="$HOME/.agents/skills/worklog"
BUNDLE_PATH="$(prompt_with_default "Codex bundle install path" "$DEFAULT_BUNDLE_PATH")"
SKILL_LINK="$(prompt_with_default "Codex skill link path" "$DEFAULT_SKILL_LINK")"

validate_child_path "$BUNDLE_PATH" "$HOME/.codex/plugins" "Bundle install path"
validate_child_path "$SKILL_LINK" "$HOME/.agents/skills" "Skill link path"

printf '\n=== Configuration preview ===\n'
printf '  Vault path:       %s\n' "$VAULT_PATH"
printf '  Display name:     %s\n' "$DISPLAY_NAME"
printf '  Git identity:     %s <%s>\n' "$GIT_USER_NAME" "$GIT_USER_EMAIL"
printf '  Backup repo:      %s\n' "$BACKUP_REPO_URL"
printf '  Auto sync:        %s\n' "$AUTO_SYNC_SUMMARY"
printf '  Bundle path:      %s\n' "$BUNDLE_PATH"
printf '  Skill link:       %s\n' "$SKILL_LINK"
printf '\n'
read -r -p "Apply these settings? [Y/n]: " confirm
case "$confirm" in
  n|N|no|No|NO) fail "Aborted by user" ;;
esac

if [[ -n "$AUTO_SYNC_WRITE" ]]; then
  "$AUTO_SYNC_SCRIPT" "$VAULT_PATH" set "$AUTO_SYNC_WRITE" setup \
    || fail "Could not write Preferences/Auto Sync.md"
fi

mkdir -p "$HOME/.codex/plugins" "$HOME/.agents/skills" \
  || fail "Could not create Codex installation roots"
validate_resolved_parent "$BUNDLE_PATH" "$HOME/.codex/plugins" "Bundle install path"
validate_resolved_parent "$SKILL_LINK" "$HOME/.agents/skills" "Skill link path"

BUNDLE_PARENT="$(dirname "$BUNDLE_PATH")"
SKILL_LINK_PARENT="$(dirname "$SKILL_LINK")"
mkdir -p "$BUNDLE_PARENT" "$SKILL_LINK_PARENT" \
  || fail "Could not create installation parent directories"
validate_resolved_parent "$BUNDLE_PATH" "$HOME/.codex/plugins" "Bundle install path"
validate_resolved_parent "$SKILL_LINK" "$HOME/.agents/skills" "Skill link path"

if [[ -e "$BUNDLE_PATH" || -L "$BUNDLE_PATH" ]]; then
  read -r -p "Bundle path already exists. Replace it? [Y/n]: " replace_bundle
  case "$replace_bundle" in
    n|N|no|No|NO) fail "Bundle path conflict" ;;
  esac
fi
if [[ -e "$SKILL_LINK" || -L "$SKILL_LINK" ]]; then
  read -r -p "Skill link already exists. Replace it? [Y/n]: " replace_link
  case "$replace_link" in
    n|N|no|No|NO) fail "Skill link conflict" ;;
  esac
fi

STAGING_BUNDLE="$(mktemp -d "$BUNDLE_PARENT/.obsidian-worklog-stage.XXXXXX")" \
  || fail "Could not create a staging bundle"
TRACKED_LIST="$(mktemp)"
cleanup_install_temp() {
  rm -f "$TRACKED_LIST"
  if [[ -n "${STAGING_BUNDLE:-}" && -e "$STAGING_BUNDLE" ]]; then
    rm -rf "$STAGING_BUNDLE"
  fi
}
trap cleanup_install_temp EXIT
git -C "$REPO_ROOT" ls-files > "$TRACKED_LIST" || fail "Could not enumerate tracked files"
if ! (cd "$REPO_ROOT" && tar -cf - -T "$TRACKED_LIST") | (cd "$STAGING_BUNDLE" && tar -xf -); then
  fail "Could not copy the tracked plugin bundle"
fi
rm -f "$TRACKED_LIST"

INSTALLED_SKILL="$STAGING_BUNDLE/skills/worklog/SKILL.md"
[[ -f "$INSTALLED_SKILL" ]] || fail "Installed SKILL.md is missing"

# Claude's existing setup.sh renders every working-tree skill .md in place. If that has
# already happened, recover the placeholder template from HEAD for the installed copy only.
# Never reset or rewrite the Claude-configured source files.
INSTALLED_MD_FILES=()
while IFS= read -r f; do INSTALLED_MD_FILES+=("$f"); done < <(find "$STAGING_BUNDLE/skills/worklog" -name '*.md' -type f | sort)
for f in "${INSTALLED_MD_FILES[@]}"; do
  rel="${f#"$STAGING_BUNDLE"/}"
  if [[ -f "$REPO_ROOT/$rel" ]] && ! grep -qF '__VAULT_PATH__' "$REPO_ROOT/$rel" \
    && git -C "$REPO_ROOT" grep -qF '__VAULT_PATH__' HEAD -- "$rel"; then
    git -C "$REPO_ROOT" show "HEAD:$rel" > "$f" || fail "Could not recover $rel from git HEAD"
  fi
done
grep -qF '__VAULT_PATH__' "$INSTALLED_SKILL" \
  || fail "Installed skill template does not contain configuration placeholders"

VAULT_PATH_ESC="$(escape_for_sed "$VAULT_PATH")"
DISPLAY_NAME_ESC="$(escape_for_sed "$DISPLAY_NAME")"
GIT_USER_NAME_ESC="$(escape_for_sed "$GIT_USER_NAME")"
GIT_USER_EMAIL_ESC="$(escape_for_sed "$GIT_USER_EMAIL")"
BUNDLE_PATH_ESC="$(escape_for_sed "$BUNDLE_PATH")"
BACKUP_REPO_URL_ESC="$(escape_for_sed "$BACKUP_REPO_URL")"

for f in "${INSTALLED_MD_FILES[@]}"; do
  sed_inplace "s|__VAULT_PATH__|${VAULT_PATH_ESC}|g" "$f"
  sed_inplace "s|__USER_NAME__|${DISPLAY_NAME_ESC}|g" "$f"
  sed_inplace "s|__GIT_USER_NAME__|${GIT_USER_NAME_ESC}|g" "$f"
  sed_inplace "s|__GIT_USER_EMAIL__|${GIT_USER_EMAIL_ESC}|g" "$f"
  sed_inplace "s|__SKILL_INSTALL_PATH__|${BUNDLE_PATH_ESC}|g" "$f"
  sed_inplace "s|__BACKUP_REPO_URL__|${BACKUP_REPO_URL_ESC}|g" "$f"
done

if grep -qE '__VAULT_PATH__|__USER_NAME__|__GIT_USER_NAME__|__GIT_USER_EMAIL__|__SKILL_INSTALL_PATH__|__BACKUP_REPO_URL__' "${INSTALLED_MD_FILES[@]}"; then
  fail "Installed skill still contains configuration placeholders"
fi

[[ -f "$STAGING_BUNDLE/.codex-plugin/plugin.json" ]] \
  || fail "Staged Codex plugin manifest is missing"
[[ -f "$STAGING_BUNDLE/.claude-plugin/plugin.json" ]] \
  || fail "Staged Claude plugin manifest is missing"

VAULT_TEMPLATE="$VAULT_PATH/Templates/Weekly.md"
if [[ -e "$VAULT_TEMPLATE" || -L "$VAULT_TEMPLATE" ]]; then
  if cmp -s "$TEMPLATES_DIR/Weekly.md" "$VAULT_TEMPLATE"; then
    printf 'Weekly template already matches; leaving it unchanged.\n'
  else
    printf 'Existing weekly template preserved: %s\n' "$VAULT_TEMPLATE"
  fi
else
  cp "$TEMPLATES_DIR/Weekly.md" "$VAULT_TEMPLATE" \
    || fail "Could not install the weekly template"
fi

BUNDLE_BACKUP=""
SKILL_LINK_BACKUP=""
BUNDLE_INSTALLED=false
SKILL_LINK_MOVED=false
SKILL_LINK_CREATED=false
rollback_install() {
  local reason="$1" rollback_failed=0

  if [[ "$SKILL_LINK_CREATED" == true && ( -e "$SKILL_LINK" || -L "$SKILL_LINK" ) ]]; then
    rm -rf "$SKILL_LINK" || rollback_failed=1
  fi
  if [[ "$SKILL_LINK_MOVED" == true && -n "$SKILL_LINK_BACKUP" && ( -e "$SKILL_LINK_BACKUP" || -L "$SKILL_LINK_BACKUP" ) ]]; then
    if [[ -e "$SKILL_LINK" || -L "$SKILL_LINK" ]]; then
      rollback_failed=1
    else
      mv "$SKILL_LINK_BACKUP" "$SKILL_LINK" || rollback_failed=1
    fi
  elif [[ -n "$SKILL_LINK_BACKUP" && -d "$SKILL_LINK_BACKUP" ]]; then
    rmdir "$SKILL_LINK_BACKUP" || rollback_failed=1
  fi

  if [[ "$BUNDLE_INSTALLED" == true && ( -e "$BUNDLE_PATH" || -L "$BUNDLE_PATH" ) ]]; then
    rm -rf "$BUNDLE_PATH" || rollback_failed=1
  fi
  if [[ -n "$BUNDLE_BACKUP" && ( -e "$BUNDLE_BACKUP" || -L "$BUNDLE_BACKUP" ) ]]; then
    if [[ -e "$BUNDLE_PATH" || -L "$BUNDLE_PATH" ]]; then
      rollback_failed=1
    else
      mv "$BUNDLE_BACKUP" "$BUNDLE_PATH" || rollback_failed=1
    fi
  fi

  if [[ "$rollback_failed" -ne 0 ]]; then
    fail "$reason; rollback was incomplete (bundle backup: ${BUNDLE_BACKUP:-none}, skill-link backup: ${SKILL_LINK_BACKUP:-none})"
  fi
  fail "$reason; previous installation state restored"
}

if [[ -e "$BUNDLE_PATH" || -L "$BUNDLE_PATH" ]]; then
  BUNDLE_BACKUP="$(mktemp -d "$BUNDLE_PARENT/.obsidian-worklog-backup.XXXXXX")" \
    || fail "Could not reserve a backup path for the existing bundle"
  rmdir "$BUNDLE_BACKUP" || fail "Could not prepare the bundle backup path"
  mv "$BUNDLE_PATH" "$BUNDLE_BACKUP" \
    || fail "Could not preserve the existing bundle before replacement"
fi

if ! mv "$STAGING_BUNDLE" "$BUNDLE_PATH"; then
  if [[ -n "$BUNDLE_BACKUP" ]]; then
    mv "$BUNDLE_BACKUP" "$BUNDLE_PATH" \
      || fail "Bundle install failed; previous bundle remains at $BUNDLE_BACKUP"
  fi
  fail "Could not move the staged bundle into place"
fi
STAGING_BUNDLE=""
BUNDLE_INSTALLED=true

if [[ -e "$SKILL_LINK" || -L "$SKILL_LINK" ]]; then
  SKILL_LINK_BACKUP="$(mktemp -d "$SKILL_LINK_PARENT/.obsidian-worklog-link-backup.XXXXXX")" \
    || rollback_install "Could not reserve a backup path for the existing skill link"
  rmdir "$SKILL_LINK_BACKUP" \
    || rollback_install "Could not prepare the skill-link backup path"
  mv "$SKILL_LINK" "$SKILL_LINK_BACKUP" \
    || rollback_install "Could not preserve the existing skill link before replacement"
  SKILL_LINK_MOVED=true
fi
ln -s "$BUNDLE_PATH/skills/worklog" "$SKILL_LINK" \
  || rollback_install "Could not create skill link"
SKILL_LINK_CREATED=true

[[ -f "$BUNDLE_PATH/.codex-plugin/plugin.json" ]] \
  || rollback_install "Codex plugin manifest is missing"
[[ -f "$BUNDLE_PATH/.claude-plugin/plugin.json" ]] \
  || rollback_install "Claude plugin manifest is missing"
[[ -f "$SKILL_LINK/SKILL.md" ]] \
  || rollback_install "Codex skill discovery link is invalid"

if [[ -n "$SKILL_LINK_BACKUP" ]]; then
  rm -rf "$SKILL_LINK_BACKUP" || fail "Could not remove the previous skill-link backup"
  SKILL_LINK_BACKUP=""
fi
if [[ -n "$BUNDLE_BACKUP" ]]; then
  rm -rf "$BUNDLE_BACKUP" || fail "Could not remove the previous bundle backup"
  BUNDLE_BACKUP=""
fi

trap - EXIT

printf '\n=== Setup complete ===\n\n'
printf 'Codex skill: %s\n' "$SKILL_LINK"
printf 'Plugin bundle: %s\n' "$BUNDLE_PATH"
printf 'Vault: %s\n\n' "$VAULT_PATH"
printf 'Start a new Codex session with the vault available as a writable workspace, then try:\n'
printf '  $worklog status\n'
printf '  $worklog rollover\n'
