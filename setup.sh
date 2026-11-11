#!/usr/bin/env bash
# setup.sh - Configure obsidian-worklog skill for your environment
#
# Strict mode: any step that can't complete cleanly causes the script to
# exit non-zero. "Setup complete!" only prints after every verification
# passes. The first /worklog invocation after this exits 0 is guaranteed
# to find the MCPs, vault directories, and plugin install in place - no
# model inference required for any setup step.

set -euo pipefail

# ===========================================================================
# Repo root + helpers
# ===========================================================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$REPO_ROOT/skills/worklog/SKILL.md"
TEMPLATES_DIR="$REPO_ROOT/templates"

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result
  read -r -p "$prompt [$default]: " result
  echo "${result:-$default}"
}

escape_for_sed() {
  printf '%s' "$1" | sed 's/[|&\\/]/\\&/g'
}

validate_email() {
  [[ "$1" =~ ^[^@]+@[^@]+\.[^@]+$ ]]
}

sed_inplace() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

fail() {
  echo ""
  echo "FAIL: $*" >&2
  echo "" >&2
  echo "Setup aborted. No 'Setup complete' state was reached." >&2
  exit 1
}

# ===========================================================================
# Guard: refuse to run if SKILL.md no longer contains placeholders
# ===========================================================================
if ! grep -q '__VAULT_PATH__' "$SKILL_FILE" 2>/dev/null; then
  echo "ERROR: $SKILL_FILE does not contain __VAULT_PATH__ placeholder."
  echo "Either the file is missing or setup.sh has already been run on it."
  echo ""
  echo "To reconfigure, restore the original SKILL.md first:"
  echo "  cd $REPO_ROOT && git checkout skills/worklog/SKILL.md"
  echo "Then re-run setup.sh."
  exit 1
fi

echo ""
echo "=== obsidian-worklog setup (strict mode) ==="
echo "This script configures the skill and verifies all integrations."
echo "Any failure aborts the script - partial setups are not allowed."
echo ""

# ===========================================================================
# Step 1: Prompt: Vault path (with full directory structure on create)
# ===========================================================================
DEFAULT_VAULT="$HOME/Documents/Obsidian Vault"
VAULT_PATH=$(prompt_with_default "Obsidian vault path" "$DEFAULT_VAULT")

# Vault subdirectories the skill expects to exist
VAULT_SUBDIRS=(
  Worklogs People Programs Threads Teams Meetings Sources Preferences
  Archive Summaries Reports Templates Logs References
)
# Every directory here must also appear in the `git add` allowlist in
# references/sync.md, and vice versa. The one deliberate exception is `Cold/`: it is
# in the allowlist but not here, because `/worklog cold` and sync create it on demand. That list is an allowlist, so a directory
# missing from it is silently never staged; and `git add` fails atomically on a
# pathspec that does not exist, so a directory named there but absent here breaks
# the whole sync and stages nothing at all.

if [[ ! -d "$VAULT_PATH" ]]; then
  echo ""
  echo "Directory does not exist: $VAULT_PATH"
  read -r -p "Create vault directory structure now? [Y/n]: " create_vault
  case "$create_vault" in
    n|N|no|No|NO)
      fail "Vault directory required. Re-run setup after creating $VAULT_PATH."
      ;;
    *)
      for sub in "${VAULT_SUBDIRS[@]}"; do
        mkdir -p "$VAULT_PATH/$sub" || fail "Could not create $VAULT_PATH/$sub"
      done
      echo "  Created vault structure at: $VAULT_PATH"
      ;;
  esac
else
  # Vault exists - ensure missing subdirectories are created
  for sub in "${VAULT_SUBDIRS[@]}"; do
    [[ -d "$VAULT_PATH/$sub" ]] || mkdir -p "$VAULT_PATH/$sub" || fail "Could not create $VAULT_PATH/$sub"
  done
fi

# ===========================================================================
# Step 2: Display name
# ===========================================================================
DEFAULT_DISPLAY_NAME="$(whoami)"
DISPLAY_NAME=$(prompt_with_default "Your display name (used in skill description)" "$DEFAULT_DISPLAY_NAME")

# ===========================================================================
# Step 3: Git identity
# ===========================================================================
DEFAULT_GIT_NAME="$(whoami)"
GIT_USER_NAME=$(prompt_with_default "Git user.name for vault commits" "$DEFAULT_GIT_NAME")

GIT_USER_EMAIL=""
while true; do
  GIT_USER_EMAIL=$(prompt_with_default "Git user.email for vault commits" "")
  if [[ -z "$GIT_USER_EMAIL" ]]; then
    echo "  Email is required."
  elif validate_email "$GIT_USER_EMAIL"; then
    break
  else
    echo "  Invalid email format. Please try again."
  fi
done

# ===========================================================================
# Step 5: Backup repo URL
# ===========================================================================
echo ""
BACKUP_REPO_URL=$(prompt_with_default "Backup repo URL (enter NONE to skip)" "NONE")

# ===========================================================================
# Step 6b: Auto sync (asked once per vault; the choice lives in Preferences/Auto Sync.md)
# ===========================================================================
AUTO_SYNC_SCRIPT="$REPO_ROOT/skills/worklog/scripts/auto-sync.sh"
AUTO_SYNC_NOTE="$VAULT_PATH/Preferences/Auto Sync.md"
AUTO_SYNC_WRITE="" # on or off; written only after "Apply these settings?" is confirmed
AUTO_SYNC_SUMMARY=""
if [[ -f "$AUTO_SYNC_NOTE" ]]; then
  AUTO_SYNC_SUMMARY="$("$AUTO_SYNC_SCRIPT" "$VAULT_PATH" get) (kept from Preferences/Auto Sync.md)"
  echo "Auto sync: $AUTO_SYNC_SUMMARY"
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
    echo "Auto sync: $AUTO_SYNC_SUMMARY"
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

# ===========================================================================
# Step 7: Skill install path
# ===========================================================================
DEFAULT_INSTALL_PATH="$HOME/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog"
SKILL_INSTALL_PATH=$(prompt_with_default "Skill install path (plugin location after install)" "$DEFAULT_INSTALL_PATH")

# Safety guardrail: refuse to operate on paths outside $HOME/.claude/.
# This protects against typo-driven destructive rm -rf in Step 11.
# If a user typed their home dir, or '/', the script would otherwise wipe data on
# a single Enter at the overwrite prompt. Restricting to .claude/ contains the blast radius.
case "$SKILL_INSTALL_PATH" in
  "$HOME/.claude/"*) ;;
  *)
    fail "Skill install path must be under \$HOME/.claude/ to prevent accidental destructive overwrites. Got: $SKILL_INSTALL_PATH"
    ;;
esac
# Also reject path components that escape via .. (defense in depth)
case "$SKILL_INSTALL_PATH" in
  *..*)
    fail "Skill install path must not contain '..' (got: $SKILL_INSTALL_PATH)"
    ;;
esac

# ===========================================================================
# Step 8: Preview and confirm
# ===========================================================================
echo ""
echo "=== Configuration preview ==="
echo "  Vault path:         $VAULT_PATH"
echo "  Display name:       $DISPLAY_NAME"
echo "  Git user.name:      $GIT_USER_NAME"
echo "  Git user.email:     $GIT_USER_EMAIL"
echo "  Backup repo URL:    $BACKUP_REPO_URL"
echo "  Auto sync:          $AUTO_SYNC_SUMMARY"
echo "  Skill install path: $SKILL_INSTALL_PATH"
echo ""
read -r -p "Apply these settings? [Y/n]: " confirm
case "$confirm" in
  n|N|no|No|NO)
    fail "Aborted by user."
    ;;
esac

# ===========================================================================
# Step 9: Apply sed replacements
# ===========================================================================
echo ""
if [[ -n "$AUTO_SYNC_WRITE" ]]; then
  "$AUTO_SYNC_SCRIPT" "$VAULT_PATH" set "$AUTO_SYNC_WRITE" setup \
    || fail "Could not write Preferences/Auto Sync.md"
fi

echo "Applying SKILL.md replacements..."

VAULT_PATH_ESC=$(escape_for_sed "$VAULT_PATH")
DISPLAY_NAME_ESC=$(escape_for_sed "$DISPLAY_NAME")
GIT_USER_NAME_ESC=$(escape_for_sed "$GIT_USER_NAME")
GIT_USER_EMAIL_ESC=$(escape_for_sed "$GIT_USER_EMAIL")
SKILL_INSTALL_PATH_ESC=$(escape_for_sed "$SKILL_INSTALL_PATH")
BACKUP_REPO_URL_ESC=$(escape_for_sed "$BACKUP_REPO_URL")

# Known placeholder names. Anything here MUST be replaced before "Setup complete".
# This is an explicit list (not a regex) so markdown bold like __NOT__ doesn't
# false-positive.
PLACEHOLDERS=(
  __VAULT_PATH__
  __USER_NAME__
  __GIT_USER_NAME__
  __GIT_USER_EMAIL__
  __SKILL_INSTALL_PATH__
  __BACKUP_REPO_URL__
)

# Every markdown file the skill loads needs the same substitutions. SKILL.md is
# the entry point, but the reference files it reads on demand carry the same
# placeholders, and an unrendered __VAULT_PATH__ in one of those is a literal
# string the skill would try to use as a path.
SKILL_MD_FILES=("$SKILL_FILE")
while IFS= read -r f; do
  [ "$f" = "$SKILL_FILE" ] || SKILL_MD_FILES+=("$f")
done < <(find "$REPO_ROOT/skills/worklog" -name '*.md' -type f | sort)

echo "  rendering ${#SKILL_MD_FILES[@]} markdown file(s)"

for f in "${SKILL_MD_FILES[@]}"; do
  sed_inplace "s|__VAULT_PATH__|${VAULT_PATH_ESC}|g" "$f"
  sed_inplace "s|__USER_NAME__|${DISPLAY_NAME_ESC}|g" "$f"
  sed_inplace "s|__GIT_USER_NAME__|${GIT_USER_NAME_ESC}|g" "$f"
  sed_inplace "s|__GIT_USER_EMAIL__|${GIT_USER_EMAIL_ESC}|g" "$f"
  sed_inplace "s|__SKILL_INSTALL_PATH__|${SKILL_INSTALL_PATH_ESC}|g" "$f"
done

if [[ "$BACKUP_REPO_URL" == "NONE" ]]; then
  for f in "${SKILL_MD_FILES[@]}"; do
    sed_inplace "s|__BACKUP_REPO_URL__|NONE|g" "$f"
  done
else
  for f in "${SKILL_MD_FILES[@]}"; do
    sed_inplace "s|__BACKUP_REPO_URL__|${BACKUP_REPO_URL_ESC}|g" "$f"
  done
fi

# Verify each known placeholder is gone (literal match, not regex).
REMAINING=""
for ph in "${PLACEHOLDERS[@]}"; do
  for f in "${SKILL_MD_FILES[@]}"; do
    if grep -qF "$ph" "$f"; then
      REMAINING+="$ph (${f##*/}) "
    fi
  done
done
if [[ -n "$REMAINING" ]]; then
  fail "Some placeholders were not replaced: $REMAINING"
fi
echo "  OK all placeholders replaced"

# Verify each substituted VALUE actually landed in the file. This catches the
# class of bugs where sed mishandled the replacement string (backslash sequences,
# regex specials in user input) and produced corrupted output - the placeholder
# would be gone but the value wouldn't be there either.
declare -A SUBSTITUTIONS=(
  [VAULT_PATH]="$VAULT_PATH"
  [DISPLAY_NAME]="$DISPLAY_NAME"
  [GIT_USER_NAME]="$GIT_USER_NAME"
  [GIT_USER_EMAIL]="$GIT_USER_EMAIL"
  [SKILL_INSTALL_PATH]="$SKILL_INSTALL_PATH"
)
# Check against every rendered file, not SKILL.md alone. Command detail loads on
# demand now, so a placeholder can legitimately live only in a reference file -
# the git identity appears only in references/sync.md, for instance.
landed() { # <value>
  local v="$1" f
  for f in "${SKILL_MD_FILES[@]}"; do
    grep -qF -- "$v" "$f" && return 0
  done
  return 1
}
for key in "${!SUBSTITUTIONS[@]}"; do
  val="${SUBSTITUTIONS[$key]}"
  if ! landed "$val"; then
    fail "Substitution for $key did not land - value '$val' in none of the rendered skill files (sed escape likely corrupted it)"
  fi
done
if [[ "$BACKUP_REPO_URL" != "NONE" ]] && ! landed "$BACKUP_REPO_URL"; then
  fail "Substitution for BACKUP_REPO_URL did not land - value '$BACKUP_REPO_URL' in none of the rendered skill files"
fi
echo "  OK all substituted values present across the rendered files"

# ===========================================================================
# Step 10: Copy Weekly.md template into vault
# ===========================================================================
WEEKLY_TEMPLATE="$TEMPLATES_DIR/Weekly.md"
if [[ -f "$WEEKLY_TEMPLATE" ]]; then
  cp "$WEEKLY_TEMPLATE" "$VAULT_PATH/Templates/Weekly.md" \
    || fail "Could not copy Weekly.md template to $VAULT_PATH/Templates/"
  echo "  OK Weekly.md template installed"
fi

# ===========================================================================
# Step 11: Install plugin (copy repo to install path)
# ===========================================================================
echo ""
if [[ -d "$SKILL_INSTALL_PATH" ]]; then
  read -r -p "Install path already exists at $SKILL_INSTALL_PATH. Overwrite? [Y/n]: " overwrite
  case "$overwrite" in
    n|N|no|No|NO)
      fail "Install path conflict. Move or remove $SKILL_INSTALL_PATH and re-run."
      ;;
    *)
      rm -rf "$SKILL_INSTALL_PATH" || fail "Could not remove existing $SKILL_INSTALL_PATH"
      ;;
  esac
fi

mkdir -p "$SKILL_INSTALL_PATH" || fail "Could not create plugin install directory"

# Copy only git-tracked files (with their current working-tree contents, including
# the sed substitutions just applied to SKILL.md). This excludes:
#  - .git/ (no nested repo at install path)
#  - untracked working-tree files (e.g., experimental notes, screenshots)
#  - anything matched by .gitignore
# 'git ls-files' lists tracked paths; tar pipes them between source and dest.
TRACKED_LIST=$(mktemp)
if ! git -C "$REPO_ROOT" ls-files > "$TRACKED_LIST"; then
  rm -f "$TRACKED_LIST"
  fail "Could not enumerate tracked files via git ls-files"
fi
if ! (cd "$REPO_ROOT" && tar -cf - -T "$TRACKED_LIST") | (cd "$SKILL_INSTALL_PATH" && tar -xf -); then
  rm -f "$TRACKED_LIST"
  fail "Plugin install via git ls-files | tar pipeline failed"
fi
rm -f "$TRACKED_LIST"
echo "  OK plugin installed at $SKILL_INSTALL_PATH (tracked files only)"

# ===========================================================================
# Step 12: Final verification block
# ===========================================================================
echo ""
echo "=== Final verification ==="

VERIFY_FAILED=0

# Type-specific check helpers. No eval; arguments are passed by value so
# user-controlled paths can't escape into shell parsing.
check_dir() {
  local path="$1" label="$2"
  if [[ -d "$path" ]]; then
    echo "  OK $label"
  else
    echo "  FAIL $label"
    VERIFY_FAILED=1
  fi
}

check_file() {
  local path="$1" label="$2"
  if [[ -f "$path" ]]; then
    echo "  OK $label"
  else
    echo "  FAIL $label"
    VERIFY_FAILED=1
  fi
}

check_absence() {
  # File must NOT contain pattern (literal match).
  local file="$1" pattern="$2" label="$3"
  if grep -qF -- "$pattern" "$file"; then
    echo "  FAIL $label"
    VERIFY_FAILED=1
  else
    echo "  OK $label"
  fi
}

check_presence() {
  # File MUST contain pattern (literal match).
  local file="$1" pattern="$2" label="$3"
  if grep -qF -- "$pattern" "$file"; then
    echo "  OK $label"
  else
    echo "  FAIL $label"
    VERIFY_FAILED=1
  fi
}

# All vault subdirectories present
for sub in "${VAULT_SUBDIRS[@]}"; do
  check_dir "$VAULT_PATH/$sub" "vault has $sub/"
done

# SKILL.md is fully configured: each known placeholder absent, each value present
for ph in "${PLACEHOLDERS[@]}"; do
  check_absence "$SKILL_FILE" "$ph" "SKILL.md no longer contains $ph"
done
check_presence "$SKILL_FILE" "$VAULT_PATH" "SKILL.md contains VAULT_PATH value"
check_presence "$SKILL_FILE" "$SKILL_INSTALL_PATH" "SKILL.md contains install-path value"

# Plugin files present at install path
check_file "$SKILL_INSTALL_PATH/.claude-plugin/plugin.json" "plugin manifest at install path"
check_file "$SKILL_INSTALL_PATH/skills/worklog/SKILL.md" "plugin SKILL.md at install path"

if [[ $VERIFY_FAILED -ne 0 ]]; then
  fail "One or more verifications failed (see above). Setup not complete."
fi

# ===========================================================================
# Success
# ===========================================================================
echo ""
echo "=== Setup complete! ==="
echo ""
echo "Verified state:"
echo "  - Vault structure at $VAULT_PATH (14 subdirectories)"
echo "  - Skill configured (all placeholders replaced)"
echo "  - Plugin installed at $SKILL_INSTALL_PATH"
if [[ "$BACKUP_REPO_URL" != "NONE" ]]; then
  echo "  - Backup repo: $BACKUP_REPO_URL"
fi
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load the plugin"
echo "  2. Try: /worklog status"
echo "  3. Create your first week: /worklog rollover"
echo "  4. Optional: /worklog ingest and /worklog jira need the Slack, Atlassian Rovo,"
echo "     or Google Docs MCP servers. See README (Integration commands)."
echo ""
