# Codex setup

The same worklog skill can run in Claude Code or Codex. The vault schema, templates,
scripts, and command behavior are shared; only installation, explicit invocation, and
host tool names differ.

## Install

From a clean clone, run:

```bash
./setup-codex.sh
```

The installer:

1. Creates any missing worklog directories in the selected Obsidian vault.
2. Copies the tracked repository files to `~/.codex/plugins/obsidian-worklog` by default.
3. Replaces configuration placeholders only in that installed copy. The clone and any
   Claude installation remain unchanged. If Claude's setup already rendered the clone's
   `SKILL.md`, the Codex installer reads the committed template from Git without resetting
   or rewriting the Claude-configured file.
4. Creates `~/.agents/skills/worklog` as a symlink to the installed skill. This is the
   user-scope location discovered by Codex CLI, the IDE extension, and the desktop app.
5. Copies `templates/Weekly.md` into the vault only when that file is missing. Existing
   templates are preserved.

The bundle also contains `.codex-plugin/plugin.json`, so it is ready to be distributed
through a Codex plugin marketplace. The symlink is the direct local-development path and
does not require a marketplace.

Start a new Codex session after installation, then invoke the skill explicitly:

```text
$worklog status
$worklog add P1 Draft the migration plan
$worklog rollover
```

Codex can also select the skill implicitly for requests such as “What is on my plate?”

## Give Codex access to the vault

Codex needs the vault inside its writable workspace boundary. The simplest option is to
open or launch Codex with the vault as the workspace. If the session also needs another
repository, add the vault as an additional writable workspace root through your Codex
permission profile.

Do not use full-machine access just for the worklog. A workspace-scoped write grant is
enough for normal Markdown edits and the bundled scanners. Git push, the optional Slack
file helper, and clipboard access may still request approval because they cross separate
network or operating-system boundaries.

Official background:

- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [Build plugins](https://developers.openai.com/plugins/build/plugins)
- [Sandbox and writable roots](https://learn.chatgpt.com/docs/sandboxing)
- [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp)

## Codex and Claude command syntax

The skill documentation uses `/worklog` as its canonical internal spelling because that
is the existing Claude command. In Codex, `$worklog` selects the skill and the remaining
text is interpreted identically:

| Claude Code | Codex |
|-------------|-------|
| `/worklog status` | `$worklog status` |
| `/worklog review` | `$worklog review` |
| `/worklog summary quarter` | `$worklog summary quarter` |
| `/worklog ingest <url>` | `$worklog ingest <url>` |

When Codex invokes the skill implicitly, natural-language requests work too.

## Netflix integrations

Netflix MCP servers are configured for the Codex host separately from the skill. Codex
CLI, the IDE extension, and the desktop app share the same Codex MCP configuration.
Follow [SETUP-NETFLIX.md](SETUP-NETFLIX.md) for the internal prerequisites.

Core file-based commands work without Netflix MCPs. Netflix ingest, people lookup, Jira,
and Slack pull additionally require their named capabilities. If a required capability is
not available, the skill stops and identifies what is missing instead of silently choosing
an unrelated tool. Full incremental `pull` requires a Slack connector that can list channel
messages, read threads, find channels, and resolve users.

## Upgrade

Pull the new repository version and rerun `./setup-codex.sh`. Confirm replacement of the
existing bundle and skill link. The installer stages and validates the replacement before
swapping it into place, rejects paths whose resolved parents escape the guarded Codex
directories, and preserves an existing vault template. It does not change the Claude plugin
directory.

Start a new Codex session after upgrading so skill and MCP discovery run again.

## Troubleshooting

__`$worklog` is not listed by `/skills`__

- Check that `~/.agents/skills/worklog/SKILL.md` resolves to a file.
- Restart Codex after installing or upgrading.
- Check for another installed skill also named `worklog`.

__Codex can read the vault but cannot update it__

- Make the vault a writable workspace root; changing the skill installation does not
  expand filesystem permissions.

__A Netflix command reports a missing tool__

- Open `/mcp` and confirm the required Netflix profile or connector loaded for this Codex
  host. Restart Codex after changing MCP configuration.

__`$worklog pull` reports that incremental Slack access is unavailable__

- Install or enable a Slack connector with channel-listing and thread-reading tools, or
  use `$worklog ingest <slack-permalink>` for one-off thread ingestion.
