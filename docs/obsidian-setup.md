# Obsidian Plugin Configuration Guide

This guide covers the exact settings required for the four plugins that power the worklog system. Configure them in the order listed to avoid dependency issues.

---

## Prerequisites

Install the following community plugins from the Obsidian plugin browser:

- Templater
- Periodic Notes
- Calendar
- Dataview

---

## 1. Templater

Templater processes template expressions (like `<% tp.date.now() %>`) when new files are created, so the weekly note is populated automatically on creation.

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

Click the `+` button under "Folder templates" to add the mapping above.

---

## 2. Periodic Notes

Periodic Notes handles the creation of weekly note files with the correct filename format. This is the plugin that Calendar delegates to when you click a week number.

__Settings > Community Plugins > Periodic Notes__

### Weekly Notes

| Setting | Value |
|---|---|
| Enable weekly notes | ON |
| Format | `YYYY-[W]WW` |
| Weekly note template | `Templates/Weekly.md` |
| Weekly note folder | `Worklogs` |

### All other periods

| Period | Status |
|---|---|
| Daily notes | Disabled |
| Monthly notes | Disabled |
| Quarterly notes | Disabled |
| Yearly notes | Disabled |

Turn off each period type individually using the toggle at the top of each section.

---

## 3. Calendar

Calendar provides the sidebar widget where you can click a week number to open or create that week's note. It does __not__ control note format or template — those come from Periodic Notes.

__Settings > Community Plugins > Calendar__

| Setting | Value |
|---|---|
| Show week numbers | ON |
| Start week on | Monday |
| Confirm before creating new note | ON |

> __Note:__ If you see a "Weekly note template" field in Calendar settings, leave it blank. Calendar defers to Periodic Notes for all file creation settings. Entering a template here will cause conflicts.

---

## 4. Dataview

Dataview enables the query blocks embedded in your vault views. Both JavaScript queries and inline queries are used by the included dashboard templates.

__Settings > Community Plugins > Dataview__

| Setting | Value |
|---|---|
| Enable JavaScript Queries | ON |
| Enable Inline Queries | ON |

Leave all other Dataview settings at their defaults.

---

## How They Work Together

The four plugins form a pipeline triggered by a single click:

1. __Calendar sidebar__ - You see the week grid in the left panel. Click a week number (e.g., W15).

2. __Periodic Notes__ - Calendar delegates the "open or create weekly note" action to Periodic Notes. Periodic Notes uses the configured format (`YYYY-[W]WW`) to compute the filename (e.g., `2026-W15.md`) and creates the file in the `Worklogs` folder using `Templates/Weekly.md` as the source.

3. __Templater__ - Because "Trigger Templater on new file creation" is ON and the folder template maps `Worklogs` to `Templates/Weekly.md`, Templater immediately processes the new file. It evaluates all template expressions in `Weekly.md` - date stamps, calculated fields, pre-filled frontmatter - and replaces them with their current values.

4. __Dataview__ - Any `dataview` code blocks in your notes are rendered live as tables or lists. Dataview reads the frontmatter fields (`programs`, `people`, `tags`, `item-count`, `done-count`) that Templater populated and aggregates them across all files in `Worklogs/`.

The result: one click in the Calendar sidebar produces a fully formatted, dated, frontmatter-complete weekly note with all template expressions resolved.
