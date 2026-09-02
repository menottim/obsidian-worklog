# `/worklog sync`

Loaded on demand from `SKILL.md`. Everything the command needs is here.


Back up the vault and skill to the private repo. First copies the current skill
source into the vault, then commits and pushes:

```bash
# Copy skill files into vault for backup
cp __SKILL_INSTALL_PATH__/skills/worklog/SKILL.md \
   "__VAULT_PATH__/.skills/worklog/SKILL.md"
cp __SKILL_INSTALL_PATH__/.claude-plugin/plugin.json \
   "__VAULT_PATH__/.skills/worklog/plugin.json"
# Keep the Codex manifest when this dual-host bundle contains one.
if [ -f __SKILL_INSTALL_PATH__/.codex-plugin/plugin.json ]; then
  cp __SKILL_INSTALL_PATH__/.codex-plugin/plugin.json \
     "__VAULT_PATH__/.skills/worklog/codex-plugin.json"
fi

cd "__VAULT_PATH__"

# Log before staging, so the entry lands in the same commit. This also creates
# Logs/ as a side effect on any vault that doesn't have it yet.
COMMIT_MSG="worklog sync $(date +%Y-%m-%d)"
__SKILL_INSTALL_PATH__/skills/worklog/scripts/log-append.sh '__VAULT_PATH__' sync vault "$COMMIT_MSG"

# Commit and push
git add Worklogs/ People/ Programs/ Teams/ Archive/ Summaries/ Reports/ References/ Templates/ Sources/ Meetings/ Logs/ Preferences/ .skills/
git -c user.name="__GIT_USER_NAME__" -c user.email="__GIT_USER_EMAIL__" \
    commit -m "$COMMIT_MSG"
git push
```

__The `git add` list must cover every directory in the Vault Layout above.__ It is an
explicit allowlist, so a directory missing from it is silently never staged: existing
tracked files there keep getting picked up by other commits, but any __new__ file is
skipped without warning and never reaches the backup. `Teams/`, `References/`, and `Preferences/` have each been missed this way, and `Logs/`
was added with this rule in mind. After running the sync, if
`git status --porcelain` still reports untracked files under the vault root, a
directory is missing from the list - add it here rather than staging it by hand.

Separately, `git add` fails atomically on a pathspec that does not exist on disk: if
any single directory named in the list above is absent, the whole command fails and
stages nothing at all, not even the directories that do exist. A listed-but-missing
directory is therefore worse than an unlisted one. This is why every directory in the
list must actually exist before this runs, whether created by `setup.sh` at install
time or by the flow that owns it (as above, `log-append.sh` creates `Logs/` on first
use).

Before the first sync, check if a `.gitignore` exists in the vault root. If not,
create one to prevent committing sensitive or unnecessary files:

```
.obsidian/plugins/*/data.json
.obsidian/workspace.json
.DS_Store
*.swp
.env
```

__Log it:__ the code block above already does this (op `sync`, target `vault`, body
the commit subject), appended before staging so the entry lands in the same commit.

Run this after any major update (review, rollover, batch adds). The user may also
ask to sync manually at any time.
