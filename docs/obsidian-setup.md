# Obsidian Plugin Configuration Guide

This guide gives the settings for the four community plugins that the worklog uses in Obsidian. Configure the plugins in the sequence that follows.

The skill reads and writes the vault files directly. It does not need these plugins. The plugins let you create week files by hand and see the worklog data in Obsidian.

---

## Prerequisites

1. Run `setup.sh` (Claude Code) or `setup-codex.sh` (Codex). The setup script creates the vault folders and copies `Templates/Weekly.md` into the vault.
2. Open the Obsidian plugin browser.
3. Install these community plugins:
   - Templater
   - Periodic Notes
   - Calendar
   - Dataview

### Vault folders

The setup scripts create these folders: `Worklogs`, `People`, `Programs`, `Threads`, `Teams`, `Meetings`, `Sources`, `Preferences`, `Archive`, `Summaries`, `Reports`, `Templates`, `Logs`, and `References`. The skill creates `Cold/` when it first moves old history into cold storage.

Only the `Worklogs` and `Templates` folders have plugin settings in this guide. `Worklogs` contains the current week file and `Backlog.md`. At rollover, the skill moves the previous week file to `Archive`.

---

## 1. Templater

Templater replaces the template expressions (for example `<% tp.file.title %>`) when you create a file. Thus a new week file gets its frontmatter immediately.

__Settings > Community Plugins > Templater__

| Setting | Value |
|---|---|
| Template folder location | `Templates` |
| Trigger Templater on new file creation | ON |
| Enable folder templates | ON |

__Folder templates mapping:__

| Folder | Template |
|---|---|
| `Worklogs` | `Templates/Weekly.md` |

To add the mapping, click the `+` button below "Folder templates".

---

## 2. Periodic Notes

Periodic Notes creates the weekly note files with the correct file name format. Calendar uses this plugin when you click a week number.

__Settings > Community Plugins > Periodic Notes__

### Weekly Notes

| Setting | Value |
|---|---|
| Enable weekly notes | ON |
| Format | `GGGG-[W]WW` |
| Weekly note template | `Templates/Weekly.md` |
| Weekly note folder | `Worklogs` |

The skill uses the same format for week files, for example `2026-W15.md`. The template also reads the week from the file name. If you use a different format, the template expressions fail.

### All other periods

| Period | Status |
|---|---|
| Daily notes | Disabled |
| Monthly notes | Disabled |
| Quarterly notes | Disabled |
| Yearly notes | Disabled |

Use the toggle at the top of each section to disable each period.

---

## 3. Calendar

Calendar shows a calendar in the sidebar. Click a week number to open or create the note for that week. Calendar does __not__ control the note format or the template. Periodic Notes controls them.

__Settings > Community Plugins > Calendar__

| Setting | Value |
|---|---|
| Show week numbers | ON |
| Start week on | Monday |
| Confirm before creating new note | ON |

> __Note:__ Calendar settings can show a "Weekly note template" field. Keep this field empty. Calendar uses the Periodic Notes settings to create files. A template in this field can cause conflicts.

---

## 4. Dataview

Dataview shows the results of query blocks in your notes. The queries in [Dataview Queries](dataview-queries.md) use JavaScript queries and inline queries.

__Settings > Community Plugins > Dataview__

| Setting | Value |
|---|---|
| Enable JavaScript Queries | ON |
| Enable Inline Queries | ON |

Keep the default value for all other Dataview settings.

---

## How the plugins work together

When you click a week number, the plugins do these steps:

1. __Calendar__ - The sidebar shows the week grid. You click a week number (for example W15).

2. __Periodic Notes__ - Calendar sends the "open or create weekly note" action to Periodic Notes. Periodic Notes uses the format `GGGG-[W]WW` to make the file name (for example `2026-W15.md`). It creates the file in the `Worklogs` folder from `Templates/Weekly.md`.

3. __Templater__ - Templater processes the new file, because "Trigger Templater on new file creation" is ON. It replaces each template expression in `Weekly.md` with its value. The result is this frontmatter: `type`, `week`, `date-start`, `date-end`, `status`, and `prev`. The result also has the `# Week of` title.

4. __Dataview__ - Dataview shows each `dataview` code block in your notes as a live table or list. It reads the frontmatter of the week files in `Worklogs/` and `Archive/`.

The template does not write `programs`, `people`, `tags`, `item-count`, or `done-count`. The skill calculates these fields from the body of the week file each time it changes the structure of the file. Thus the Dataview queries that use these fields show data only after the skill writes to the week file. The source is the "Frontmatter Auto-generation" section of `skills/worklog/SKILL.md`.
