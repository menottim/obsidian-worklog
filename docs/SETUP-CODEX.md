# Codex setup

The worklog skill runs in Claude Code and in Codex. The two hosts use the same vault schema, templates, scripts, and commands. Only these items are different:

- the installation procedure
- the command prefix (`$worklog` in Codex, `/worklog` in Claude Code)
- the names of the host tools
- model routing (see [Model routing in Codex](#model-routing-in-codex))

## Install

You must run the installer from a Git clone of this repository. The installer copies only the files that Git tracks.

1. Go to the root of the clone.
2. Run the installer:

   ```bash
   ./setup-codex.sh
   ```

3. Answer the prompts. Each prompt shows a default value in brackets. Push Enter to use the default.

| Prompt | Default | Notes |
|--------|---------|-------|
| Obsidian vault path | `~/Documents/Obsidian Vault` | If the directory does not exist, the installer asks for permission to create it. |
| Your display name | Your login name | |
| Git user.name for vault commits | Your global Git `user.name` (or your login name) | |
| Git user.email for vault commits | Your global Git `user.email` | The installer asks again until the value is a valid email address. |
| Backup repo URL | `NONE` | `NONE` means that the vault has no Git backup. |
| Sync the vault automatically after each change? | Yes | The installer asks this only in some conditions. See [Auto sync](#auto-sync). |
| Codex bundle install path | `~/.codex/plugins/obsidian-worklog` | The path must be below `~/.codex/plugins`. |
| Codex skill link path | `~/.agents/skills/worklog` | The path must be below `~/.agents/skills`. |
| Apply these settings? | Yes | The installer shows a preview of all values before this prompt. |

If the bundle path or the skill link already exists, the installer asks for permission to replace it.

### What the installer does

1. Right after the vault path prompt (before the preview), it creates these directories in the vault, if they do not exist: `Worklogs`, `People`, `Programs`, `Threads`, `Teams`, `Meetings`, `Sources`, `Preferences`, `Archive`, `Summaries`, `Reports`, `Templates`, `Logs`, and `References`. The skill creates `Cold/` later, when it first needs it.
2. It copies the tracked repository files to a staging directory next to the bundle path.
3. It replaces the configuration placeholders in the skill Markdown files of the staged copy. The clone does not change.
4. It copies `templates/Weekly.md` to `Templates/Weekly.md` in the vault. If that file already exists, the installer keeps it. To get template fixes, delete `Templates/Weekly.md` in the vault before you run the installer again.
5. It moves the staged copy to the bundle path.
6. It creates the skill link as a symlink to `skills/worklog` in the bundle. Codex finds user skills in `~/.agents/skills`.

If you ran the Claude Code setup (`setup.sh`) on the same clone before, the clone already contains your values in place of the placeholders. In this condition, the Codex installer reads the original files from Git `HEAD` for the installed copy. It does not reset or change the files in the clone. The Claude installation does not change.

The bundle also contains `.codex-plugin/plugin.json`. Thus you can also distribute the bundle through a Codex plugin marketplace. The symlink is the local installation path. It does not need a marketplace.

### Auto sync

The installer asks the auto sync question only when all of these conditions are true:

- The vault has no `Preferences/Auto Sync.md` note.
- You gave a backup repo URL.
- The `auto-sync.sh can-sync` check passes for the vault.

If `Preferences/Auto Sync.md` exists, the installer keeps its value. If the other conditions are not true, the installer sets auto sync to off. The installer writes the note only after you confirm "Apply these settings?".

### Start the skill

1. Start a new Codex session.
2. Use the `$worklog` prefix to call the skill:

   ```text
   $worklog status
   $worklog add P1 Draft the migration plan
   $worklog rollover
   ```

Codex can also select the skill without the prefix, for example for "What is on my plate?". The setting `allow_implicit_invocation: true` in `skills/worklog/agents/openai.yaml` permits this.

## Give Codex access to the vault

The vault must be in the writable workspace of the Codex session. Use one of these two procedures:

- Start Codex with the vault as the workspace.
- If the session also needs a different repository, add the vault as an additional writable root in your Codex permission profile.

Do not give Codex full access to the computer for the worklog. Write access to the workspace is sufficient for usual Markdown edits and for the bundled scanner scripts. Some operations can still ask for approval because they go outside the workspace:

- `git push` (network)
- the Slack helper scripts (network)
- `pbcopy` for `$worklog share`, `$worklog rollup`, and `$worklog summary` (clipboard)

Codex documentation:

- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [Build plugins](https://developers.openai.com/plugins/build/plugins)
- [Sandbox and writable roots](https://learn.chatgpt.com/docs/sandboxing)
- [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp)

## Codex and Claude Code command syntax

The skill files use `/worklog`, which is the Claude Code command. In Codex, `$worklog` selects the skill. The skill reads the remaining text in the same way on the two hosts.

| Claude Code | Codex |
|-------------|-------|
| `/worklog status` | `$worklog status` |
| `/worklog review` | `$worklog review` |
| `/worklog summary quarter` | `$worklog summary quarter` |
| `/worklog ingest <url>` | `$worklog ingest <url>` |
| `/worklog jira <key>` | `$worklog jira <key>` |

All other commands follow the same pattern. When Codex selects the skill without the prefix, requests in natural language also work.

## Model routing in Codex

In Claude Code, the skill sends some phases of a command to subagents on different models. Codex cannot select a model for each subagent. In Codex, the skill runs all phases in the main session. It uses the model and reasoning effort that you set in Codex. The source is `skills/worklog/references/model-routing.md`.

## Questions from the skill

Some steps ask you to make a choice, for example the first auto sync question or the approval of items during `pull`. In Codex, the skill asks these questions in plain text. It then waits for your answer.

## MCP integrations

MCP (Model Context Protocol) servers give Codex access to external tools. You configure MCP servers in Codex, not in the skill.

The file commands do not need an MCP server. These commands need MCP servers:

| Command | MCP server |
|---------|------------|
| `$worklog ingest <Slack permalink>` | Slack MCP (`slack_read_thread`) |
| `$worklog ingest <Confluence URL>` | Atlassian Rovo MCP (`getConfluenceContent`, or `getConfluencePage` on older servers) |
| `$worklog ingest <Google Docs URL>` | A Google Docs or Google Drive MCP |
| `$worklog jira <key>` | Atlassian Rovo MCP (`getJiraIssue`, `getAccessibleAtlassianResources`) |
| `$worklog pull` | A Slack connector with the four operations below |

The full tool name depends on the installation, for example `mcp__atlassian_rovo__getJiraIssue` in Codex. The skill uses the tool whose name ends with the name in the table. For the details, see [`integrations.md`](../skills/worklog/references/integrations.md).

If a necessary tool is not available, the skill stops before it changes the vault. It tells you which server is missing. It does not use a different tool, a web search, or `curl`.

### Pull preflight

Before `$worklog pull` reads or writes pull state, it makes sure that the Slack connector can do these four operations:

1. List the messages in a channel for a time window.
2. Read a full thread.
3. Find a channel by name.
4. Find a user by ID or handle.

If one operation is not available, the skill stops. It does not move the `last_scan_ts` cursor forward, and it tells you the missing operation. A search tool for semantic or RAG search is not a replacement, because it does not return all messages. For a single thread, use `$worklog ingest <slack-permalink>`. The source is [`pull-flow.md`](../skills/worklog/references/pull-flow.md).

## Upgrade

1. Pull the new version of the repository.
2. Run `./setup-codex.sh` again.
3. Confirm the replacement of the bundle.
4. Confirm the replacement of the skill link.
5. Start a new Codex session. The new session finds the skill and the MCP servers again.

The installer prepares and checks the new bundle in a staging directory before it replaces the old bundle. If a step fails, the installer restores the previous installation. The installer stops if a path goes outside `~/.codex/plugins` or `~/.agents/skills`, also through a symlink. It keeps the existing vault template and the existing `Preferences/Auto Sync.md` note. It does not change the Claude Code plugin directory.

## Troubleshooting

__`$worklog` does not show in `/skills`__

- Make sure that `~/.agents/skills/worklog/SKILL.md` resolves to a file.
- Restart Codex after you install or upgrade the skill.
- Make sure that no other installed skill has the name `worklog`.

__Codex can read the vault but cannot change it__

- Make the vault a writable workspace root. A change to the skill installation does not change file system permissions.

__`ingest` or `jira` reports a missing tool__

- Open `/mcp` and make sure that Codex loaded the necessary MCP server (Slack, Atlassian Rovo, or Google Docs).
- Restart Codex after you change the MCP configuration.

__`$worklog pull` reports that incremental Slack access is not available__

- Install or enable a Slack connector that can do the four operations in [Pull preflight](#pull-preflight).
- For a single thread, use `$worklog ingest <slack-permalink>`.
