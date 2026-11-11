# `/worklog sync`

Loaded on demand from `SKILL.md`. Everything the command needs is here.

Back up the vault and skill to the private repo. `scripts/sync.sh` does the work: it copies
the skill files into `.skills/worklog/`, runs the overwrite guard, writes the `sync` log entry,
stages the allowlisted directories, commits, and pushes. Do not copy files, write the log
entry, or run `git` yourself.

`sync.sh` writes a default root `.gitignore` when the vault has none, so there is no separate step.

Then run:

```bash
__SKILL_INSTALL_PATH__/skills/worklog/scripts/sync.sh '__VAULT_PATH__' '__SKILL_INSTALL_PATH__' "__GIT_USER_NAME__" "__GIT_USER_EMAIL__"
```

Print its one line. The exit codes and what to do with each are in `## Auto Sync` in
`SKILL.md`. Manual sync prints the same lines with `Sync` in place of `Auto-sync`.

On exit 1 (shrink check flagged), show the flagged lines and stop. The user confirms each line or
restores it with `git checkout -- <path>`. For confirmed lines, re-run the same sync command with
`WORKLOG_SHRINK_CONFIRM` set to exactly those paths, one per line, for example
`WORKLOG_SHRINK_CONFIRM='<path>'`. Use `$'...'` or a heredoc for more than one path. Never set the
variable without the user confirming each path.

The `git add` allowlist and its rules (every Vault Layout directory must be on it) are in
the header comment of `scripts/sync.sh`.
