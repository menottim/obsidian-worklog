# Dataview Queries

This page gives queries for the worklog vault. You can copy them into a note.

To use a query, copy the block into a note. Use the ` ```dataview ` fence for a Dataview Query Language (DQL) query. Use the ` ```dataviewjs ` fence for a JavaScript query. For the plugin settings, see [Obsidian Plugin Configuration Guide](obsidian-setup.md).

## Where the data comes from

The skill writes these frontmatter fields in each week file:

- `type`, `week`, `date-start`, `date-end`, `status`, `prev`
- `programs`, `people`, `tags`, `item-count`, `done-count`

The skill calculates the fields in the second line from the body of the week file. For the rules, see "Frontmatter Auto-generation" in `skills/worklog/SKILL.md`.

The current week file is in `Worklogs/`. At rollover, the skill moves the previous week file to `Archive/` and keeps its frontmatter. Thus the history queries read the two folders. The `WHERE week` filter excludes the files that have no `week` field, for example `Worklogs/Backlog.md`.

Other notes have frontmatter that some queries use:

- Thread notes in `Threads/`: `type: thread`, `title`, `opened`, `last-active`, `status` (`live`, `parked`, or `closed`), `week`, `programs`, `people`, `summary`, `compacted`. See `skills/worklog/references/threads.md`.
- People and program notes: `summary`. People notes can also have `team`. After `/worklog compact`, a note also has `compacted:` with the date of the compaction. See `skills/worklog/references/compact.md`.
- Operations log files in `Logs/YYYY-MM.md`: one `## [YYYY-MM-DD] <op> | <target>` heading for each operation. See "Operations Log" in `skills/worklog/SKILL.md`.

---

## 1. Weekly Overview Table

This query shows one row for each week. The row shows the total items, the completed items, the number of programs, and the completion rate. Use it to see the throughput over time.

```dataview
TABLE
  item-count AS "Items",
  done-count AS "Done",
  length(programs) AS "Programs",
  round((done-count / item-count) * 100) + "%" AS "Completion"
FROM "Worklogs" OR "Archive"
WHERE week AND item-count > 0
SORT file.name DESC
```

---

## 2. People Engagement Over Time

This query counts the number of weeks in which each person occurs. Use it to find collaboration patterns. Use it also to find contacts that stopped.

```dataviewjs
const pages = dv.pages('"Worklogs" or "Archive"').where(p => p.week && p.people && p.people.length > 0);
const counts = {};
for (const page of pages) {
  for (const person of page.people) {
    const name = typeof person === "object" ? person.path.split("/").pop().replace(".md", "") : person;
    counts[name] = (counts[name] || 0) + 1;
  }
}
const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]);
dv.table(["Person", "Weeks Mentioned"], rows);
```

---

## 3. Programs by Frequency

This query lists all programs in your week files. It sorts them by the number of active weeks. Use it to find the programs that get the most attention for a long time.

```dataviewjs
const pages = dv.pages('"Worklogs" or "Archive"').where(p => p.week && p.programs && p.programs.length > 0);
const counts = {};
for (const page of pages) {
  for (const prog of page.programs) {
    const name = typeof prog === "object" ? prog.path.split("/").pop().replace(".md", "") : prog;
    counts[name] = (counts[name] || 0) + 1;
  }
}
const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]);
dv.table(["Program", "Weeks Active"], rows);
```

---

## 4. Items Completed This Month

This query shows the weeks that start in the current calendar month. It shows the completed items for each week. Add it to a monthly review note or to a dashboard note.

```dataview
TABLE
  file.name AS "Week",
  done-count AS "Items Completed"
FROM "Worklogs" OR "Archive"
WHERE week AND done-count > 0
  AND date-start.year = date(today).year
  AND date-start.month = date(today).month
SORT file.name ASC
```

---

## 5. Open P0 Items (Current Week)

Put this query in the current week file. It lists the P0 items that are not done. It reads the body of the file, because the frontmatter has no list of P0 items.

```dataviewjs
const current = dv.current();
const content = await dv.io.load(current.file.path);
const p0lines = content.split("\n").filter(l => /^- \*\*P0\*\*/.test(l) && !l.includes("✅ Done"));
dv.list(p0lines.length > 0 ? p0lines : ["No open P0 items this week"]);
```

To show the number of open items in the text of a week file, type this inline query in the body. Do not put it in a code fence.

```
`= this["item-count"] - this["done-count"]`
```

---

## 6. Completion Rate Trend

This query shows the completion rate (done / total) for each week, with a text bar. Use it to find the weeks with low throughput, for example for a retrospective or a capacity discussion.

```dataviewjs
const pages = dv.pages('"Worklogs" or "Archive"')
  .where(p => p.week && p["item-count"] > 0)
  .sort(p => p.file.name, "asc");

const rows = pages.map(p => {
  const rate = Math.round((p["done-count"] / p["item-count"]) * 100);
  const bar = "█".repeat(Math.floor(rate / 10)) + "░".repeat(10 - Math.floor(rate / 10));
  return [p.file.name, p["item-count"], p["done-count"], rate + "% " + bar];
});

dv.table(["Week", "Total", "Done", "Rate"], rows);
```

---

## 7. Tags Distribution

This query counts each tag in your week files. The skill makes the tags from the bold subgroup labels of the week. Use the query to see the types of work that use most of your time.

```dataviewjs
const pages = dv.pages('"Worklogs" or "Archive"').where(p => p.week && p.tags && p.tags.length > 0);
const counts = {};
for (const page of pages) {
  const tagList = Array.isArray(page.tags) ? page.tags : [page.tags];
  for (const tag of tagList) {
    const t = String(tag).replace(/^#/, "");
    counts[t] = (counts[t] || 0) + 1;
  }
}
const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]);
dv.table(["Tag", "Occurrences"], rows);
```

---

## 8. Recent Activity

This query lists the 10 files in `Worklogs/` that changed most recently. Use it to continue your work from the last session.

```dataview
TABLE
  file.mtime AS "Last Modified",
  item-count AS "Items",
  done-count AS "Done"
FROM "Worklogs"
SORT file.mtime DESC
LIMIT 10
```

---

## 9. Open Threads

A Thread note keeps the dated history of one worklog item. The skill moves the history from the week file to the Thread note. This query lists the Threads that are not closed. It shows the most recently active Threads first. A `parked` Thread is an item in `Backlog.md`.

```dataview
TABLE
  status AS "Status",
  last-active AS "Last Active",
  week AS "Week",
  summary AS "Summary"
FROM "Threads"
WHERE type = "thread" AND status != "closed"
SORT last-active DESC
```

---

## 10. Compacted Notes

This query lists the notes that `/worklog compact` folded, with the date of the last compaction. Thread notes have `compacted: null` until the first compaction, so the `WHERE compacted` filter excludes them.

```dataview
TABLE
  compacted AS "Compacted",
  summary AS "Summary"
FROM "People" OR "Programs" OR "Threads"
WHERE compacted
SORT compacted DESC
```

---

## 11. Recent Operations

This query shows the last 15 entries of the operations log. The skill adds one entry for each operation that writes to the vault.

```dataviewjs
const files = dv.pages('"Logs"').sort(p => p.file.name, "asc");
const entries = [];
for (const f of files) {
  const content = await dv.io.load(f.file.path);
  for (const line of content.split("\n")) {
    const m = line.match(/^## \[(\d{4}-\d{2}-\d{2})\] (\S+) \| (.*)$/);
    if (m) entries.push([m[1], m[2], m[3]]);
  }
}
dv.table(["Date", "Operation", "Target"], entries.slice(-15).reverse());
```
