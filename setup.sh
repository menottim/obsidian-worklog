#!/usr/bin/env bash
# setup.sh - Configure obsidian-worklog skill for your environment
# Replaces placeholder tokens in SKILL.md with your actual values.
# Run once after cloning. Safe to re-inspect but will refuse to run twice.

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate repo root (script's own directory)
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$REPO_ROOT/skills/worklog/SKILL.md"
TEMPLATES_DIR="$REPO_ROOT/templates"

# ---------------------------------------------------------------------------
# Guard: refuse to run if SKILL.md no longer contains placeholders
# ---------------------------------------------------------------------------
if ! grep -q '__VAULT_PATH__' "$SKILL_FILE" 2>/dev/null; then
  echo "ERROR: $SKILL_FILE does not contain __VAULT_PATH__ placeholder."
  echo "Either the file is missing or setup.sh has already been run on it."
  echo "To re-run setup, restore the original SKILL.md from the repo first."
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result
  read -r -p "$prompt [$default]: " result
  echo "${result:-$default}"
}

# Escape characters that are special in sed replacement strings (| & \ /)
escape_for_sed() {
  printf '%s' "$1" | sed 's/[|&\\/]/\\&/g'
}

validate_email() {
  local email="$1"
  if [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    return 0
  fi
  return 1
}

# Detect sed -i syntax: macOS requires '' argument, Linux does not
sed_inplace() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

echo ""
echo "=== obsidian-worklog setup ==="
echo "This script configures SKILL.md with your local paths and identity."
echo ""

# ---------------------------------------------------------------------------
# Prompt: Vault path
# ---------------------------------------------------------------------------
DEFAULT_VAULT="$HOME/Documents/Obsidian Vault"
VAULT_PATH=$(prompt_with_default "Obsidian vault path" "$DEFAULT_VAULT")

# Validate / offer to create
if [[ ! -d "$VAULT_PATH" ]]; then
  echo ""
  echo "WARNING: Directory does not exist: $VAULT_PATH"
  read -r -p "Create vault directory structure now? [y/N]: " create_vault
  if [[ "${create_vault,,}" == "y" ]]; then
    mkdir -p \
      "$VAULT_PATH/Worklogs" \
      "$VAULT_PATH/People" \
      "$VAULT_PATH/Programs" \
      "$VAULT_PATH/Archive" \
      "$VAULT_PATH/Summaries" \
      "$VAULT_PATH/Reports" \
      "$VAULT_PATH/Templates"
    echo "Created vault directory structure at: $VAULT_PATH"
  else
    echo "Proceeding without creating the directory. You can create it later."
  fi
fi

# ---------------------------------------------------------------------------
# Prompt: Display name (used in SKILL.md description and intro)
# ---------------------------------------------------------------------------
DEFAULT_DISPLAY_NAME="$(whoami)"
DISPLAY_NAME=$(prompt_with_default "Your display name (used in skill description)" "$DEFAULT_DISPLAY_NAME")

# ---------------------------------------------------------------------------
# Prompt: Git identity
# ---------------------------------------------------------------------------
DEFAULT_GIT_NAME="$(whoami)"
GIT_USER_NAME=$(prompt_with_default "Git user.name for vault commits" "$DEFAULT_GIT_NAME")

GIT_USER_EMAIL=""
while true; do
  GIT_USER_EMAIL=$(prompt_with_default "Git user.email for vault commits" "")
  if [[ -z "$GIT_USER_EMAIL" ]]; then
    echo "  Email is required. Enter your git email address."
  elif validate_email "$GIT_USER_EMAIL"; then
    break
  else
    echo "  Invalid email format. Please try again."
  fi
done

# ---------------------------------------------------------------------------
# Prompt: Backup repo URL
# ---------------------------------------------------------------------------
BACKUP_REPO_URL=$(prompt_with_default "Backup repo URL (enter NONE to skip)" "NONE")

# ---------------------------------------------------------------------------
# Prompt: Skill install path
# ---------------------------------------------------------------------------
DEFAULT_INSTALL_PATH="$HOME/.claude/plugins/marketplaces/personal/plugins/obsidian-worklog"
SKILL_INSTALL_PATH=$(prompt_with_default "Skill install path (where this plugin lives after installation)" "$DEFAULT_INSTALL_PATH")

# ---------------------------------------------------------------------------
# Preview and confirm
# ---------------------------------------------------------------------------
echo ""
echo "=== Configuration preview ==="
echo "  Vault path:         $VAULT_PATH"
echo "  Display name:       $DISPLAY_NAME"
echo "  Git user.name:      $GIT_USER_NAME"
echo "  Git user.email:     $GIT_USER_EMAIL"
echo "  Backup repo URL:    $BACKUP_REPO_URL"
echo "  Skill install path: $SKILL_INSTALL_PATH"
echo ""
read -r -p "Apply these settings? [y/N]: " confirm
if [[ "${confirm,,}" != "y" ]]; then
  echo "Aborted. No changes made."
  exit 0
fi

# ---------------------------------------------------------------------------
# Apply sed replacements
# Use | as delimiter to handle paths with slashes and spaces safely.
# ---------------------------------------------------------------------------
echo ""
echo "Applying replacements to $SKILL_FILE ..."

# Escape all user inputs for safe sed substitution
VAULT_PATH_ESC="$(escape_for_sed "$VAULT_PATH")"
DISPLAY_NAME_ESC="$(escape_for_sed "$DISPLAY_NAME")"
GIT_USER_NAME_ESC="$(escape_for_sed "$GIT_USER_NAME")"
GIT_USER_EMAIL_ESC="$(escape_for_sed "$GIT_USER_EMAIL")"
SKILL_INSTALL_PATH_ESC="$(escape_for_sed "$SKILL_INSTALL_PATH")"
BACKUP_REPO_URL_ESC="$(escape_for_sed "$BACKUP_REPO_URL")"

# 1. Vault path (all occurrences)
sed_inplace "s|__VAULT_PATH__|${VAULT_PATH_ESC}|g" "$SKILL_FILE"

# 2. Display name
sed_inplace "s|__USER_NAME__|${DISPLAY_NAME_ESC}|g" "$SKILL_FILE"

# 3. Git identity
sed_inplace "s|__GIT_USER_NAME__|${GIT_USER_NAME_ESC}|g" "$SKILL_FILE"
sed_inplace "s|__GIT_USER_EMAIL__|${GIT_USER_EMAIL_ESC}|g" "$SKILL_FILE"

# 4. Skill install path
sed_inplace "s|__SKILL_INSTALL_PATH__|${SKILL_INSTALL_PATH_ESC}|g" "$SKILL_FILE"

# 5. Backup repo URL (or disable git push if NONE)
if [[ "$BACKUP_REPO_URL" == "NONE" ]]; then
  sed_inplace "s|__BACKUP_REPO_URL__|NONE|g" "$SKILL_FILE"
  # Comment out git push in the /worklog sync block
  sed_inplace "s|^git push$|# git push  # configure a backup repo to enable|g" "$SKILL_FILE"
  echo "  Note: git push disabled in /worklog sync (no backup repo configured)."
else
  sed_inplace "s|__BACKUP_REPO_URL__|${BACKUP_REPO_URL_ESC}|g" "$SKILL_FILE"
fi

echo "  Done."

# ---------------------------------------------------------------------------
# Copy Weekly.md template to vault if vault exists
# ---------------------------------------------------------------------------
WEEKLY_TEMPLATE="$TEMPLATES_DIR/Weekly.md"
if [[ -d "$VAULT_PATH" && -f "$WEEKLY_TEMPLATE" ]]; then
  VAULT_TEMPLATES_DIR="$VAULT_PATH/Templates"
  mkdir -p "$VAULT_TEMPLATES_DIR"
  cp "$WEEKLY_TEMPLATE" "$VAULT_TEMPLATES_DIR/Weekly.md"
  echo "Copied Weekly.md template to: $VAULT_TEMPLATES_DIR/Weekly.md"
fi

# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------
echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Install the plugin: copy this directory to $SKILL_INSTALL_PATH"
echo "     or use your Claude Code plugin manager to point at this repo."
echo "  2. Open your Obsidian vault in the app and enable Templater plugin"
echo "     if you want to use the Weekly.md template for new week files."
echo "  3. In Claude Code, try: /worklog status"
echo "  4. Run /worklog sync after your first review to back up to your repo."
echo ""
