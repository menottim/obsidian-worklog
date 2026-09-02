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
  Worklogs People Programs Teams Meetings Sources Preferences
  Archive Summaries Reports Templates Logs References
)

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
# Step 4: Netflix identity detection + MCP profile setup
# ===========================================================================
IS_NETFLIX="no"
GHE_LOGIN=""
DEFAULT_BACKUP_REPO="NONE"

if [[ "$GIT_USER_EMAIL" == *"@netflix.com" ]]; then
  IS_NETFLIX="yes"
  echo ""
  echo "=== Netflix identity detected ==="

  # 4a. Verify newt is on PATH
  if ! command -v newt >/dev/null 2>&1; then
    fail "'newt' is not on PATH. Install from https://manuals.netflix.net/view/newt, then re-run setup.sh."
  fi
  echo "  OK newt installed at $(command -v newt)"

  # 4b. Check / install genai-core-tools profile
  # JUST_JOINED_NEWT tracks whether we joined during this run. If yes, we skip
  # the final-block re-verify because 'newt resolve' has a propagation delay
  # after 'newt join' (newt itself prints "You may need to restart your IDE...
  # to pick up the latest configuration"). The join exit code is authoritative.
  JUST_JOINED_NEWT="no"
  if newt --app-type=dev-profiles resolve 2>/dev/null | grep -q "genai-core-tools"; then
    echo "  OK genai-core-tools profile already joined"
  else
    echo "  - genai-core-tools profile not joined. Joining now..."
    if ! newt --app-type=dev-profiles join --profile=genai-core-tools; then
      fail "'newt join --profile=genai-core-tools' failed. Resolve the error above and re-run setup.sh."
    fi
    JUST_JOINED_NEWT="yes"
    echo "  OK newt join succeeded (visibility in 'newt resolve' may lag until Claude Code restart)"
  fi

  # 4d. Verify gh is on PATH and authed against github.netflix.net
  if ! command -v gh >/dev/null 2>&1; then
    fail "'gh' is not on PATH. Install Netflix gh CLI from https://github.netflix.net/dleen/cli/releases"
  fi
  if ! GH_HOST=github.netflix.net gh auth status >/dev/null 2>&1; then
    fail "'gh' is not authenticated for github.netflix.net. Run: gh auth login -p https -h github.netflix.net"
  fi
  echo "  OK gh authenticated for github.netflix.net"

  # 4e. Resolve GHE login (authoritative - don't guess from $(whoami))
  GHE_LOGIN=$(GH_HOST=github.netflix.net gh api user --jq .login 2>/dev/null) \
    || fail "Could not resolve GHE login via 'gh api user'."
  if [[ -z "$GHE_LOGIN" ]]; then
    fail "GHE login resolved to empty string."
  fi
  echo "  OK GHE login: $GHE_LOGIN"

  # 4f. Compute default backup repo URL (HTTPS - port 22 SSH is blocked on many Netflix networks)
  VAULT_BASENAME=$(basename "$VAULT_PATH" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  DEFAULT_BACKUP_REPO="https://github.netflix.net/${GHE_LOGIN}/${VAULT_BASENAME}.git"
fi

# ===========================================================================
# Step 5: Backup repo URL (with Netflix-aware default)
# ===========================================================================
echo ""
if [[ "$IS_NETFLIX" == "yes" ]]; then
  echo "Default backup repo points to GHE under your account ($GHE_LOGIN)."
  echo "If the repo does not yet exist, setup will offer to create it."
fi
BACKUP_REPO_URL=$(prompt_with_default "Backup repo URL (enter NONE to skip)" "$DEFAULT_BACKUP_REPO")

# ===========================================================================
# Step 6: Backup repo verification / creation (only if a real URL was given)
# ===========================================================================
if [[ "$BACKUP_REPO_URL" != "NONE" && "$IS_NETFLIX" == "yes" ]]; then
  # Only auto-verify github.netflix.net URLs - leave other hosts alone
  if [[ "$BACKUP_REPO_URL" == https://github.netflix.net/* || "$BACKUP_REPO_URL" == https://git.netflix.net/* ]]; then
    # Extract <owner>/<repo> from URL
    REPO_PATH=$(echo "$BACKUP_REPO_URL" | sed -E 's|https://[^/]+/||; s|\.git$||')
    if GH_HOST=github.netflix.net gh repo view "$REPO_PATH" >/dev/null 2>&1; then
      echo "  OK backup repo exists: $REPO_PATH"
    else
      echo "  Backup repo $REPO_PATH does not exist."
      read -r -p "  Create it now (private)? [Y/n]: " create_repo
      case "$create_repo" in
        n|N|no|No|NO)
          fail "Backup repo must exist before setup completes. Either create it manually or re-run with Y."
          ;;
        *)
          if ! GH_HOST=github.netflix.net gh repo create "$REPO_PATH" --private --description "Obsidian worklog vault backup" >/dev/null; then
            fail "'gh repo create $REPO_PATH' failed. Check the error above and re-run setup."
          fi
          echo "  OK backup repo created: https://github.netflix.net/$REPO_PATH"
          ;;
      esac
    fi
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
echo "  Skill install path: $SKILL_INSTALL_PATH"
if [[ "$IS_NETFLIX" == "yes" ]]; then
  echo "  GHE login:          $GHE_LOGIN"
  echo "  MCP profile:        genai-core-tools (joined and verified)"
fi
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
  sed_inplace "s|^git push$|# git push  # configure a backup repo to enable|g" "$SKILL_FILE"
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

check_profile_joined() {
  local profile="$1" label="$2"
  if newt --app-type=dev-profiles resolve 2>/dev/null | grep -q "$profile"; then
    echo "  OK $label"
  else
    echo "  FAIL $label"
    VERIFY_FAILED=1
  fi
}

check_ghe_repo() {
  local repo_path="$1" label="$2"
  if GH_HOST=github.netflix.net gh repo view "$repo_path" >/dev/null 2>&1; then
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

# Netflix-only verifications
if [[ "$IS_NETFLIX" == "yes" ]]; then
  # Skip the profile-joined re-check if we just joined this run - newt has a
  # cache propagation delay, so the re-check would falsely report "not joined"
  # even though 'newt join' succeeded.
  if [[ "${JUST_JOINED_NEWT:-no}" == "yes" ]]; then
    echo "  SKIP genai-core-tools profile re-verify (just joined; will appear after Claude Code restart)"
  else
    check_profile_joined "genai-core-tools" "genai-core-tools profile joined"
  fi
  if [[ "$BACKUP_REPO_URL" != "NONE" && ( "$BACKUP_REPO_URL" == https://github.netflix.net/* || "$BACKUP_REPO_URL" == https://git.netflix.net/* ) ]]; then
    REPO_PATH=$(echo "$BACKUP_REPO_URL" | sed -E 's|https://[^/]+/||; s|\.git$||')
    check_ghe_repo "$REPO_PATH" "GHE backup repo accessible: $REPO_PATH"
  fi
fi

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
echo "  - Vault structure at $VAULT_PATH (10 subdirectories)"
echo "  - Skill configured (all placeholders replaced)"
echo "  - Plugin installed at $SKILL_INSTALL_PATH"
if [[ "$IS_NETFLIX" == "yes" ]]; then
  echo "  - Netflix MCP profile (genai-core-tools) joined"
  if [[ "$BACKUP_REPO_URL" != "NONE" ]]; then
    echo "  - Backup repo: $BACKUP_REPO_URL"
  fi
fi
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load the plugin and Netflix MCPs"
echo "  2. Try: /worklog status"
echo "  3. Create your first week: /worklog rollover"
if [[ "$IS_NETFLIX" == "yes" ]]; then
  echo "  4. Netflix commands available: /worklog ingest, /worklog whois, /worklog jira"
  echo "     See docs/NETFLIX-COMMANDS.md for the reference."
fi
echo ""
