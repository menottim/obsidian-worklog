# Dataview Queries

Ready-to-paste queries for the worklog vault. Each query reads from the frontmatter fields populated by the weekly template: `programs`, `people`, `tags`, `item-count`, `done-count`.

Copy any block into a note using the ` ```dataview ` fence (or ` ```dataviewjs ` for JavaScript queries).

---

## 1. Weekly Overview Table

Shows a summary row per week with total items, completed items, and how many distinct programs were active. Use this as a dashboard view of throughput over time.

```dataview
TABLE
  item-count AS "Items",
  done-count AS "Done",
  length(programs) AS "Programs",
  round((done-count / item-count) * 100) + "%" AS "Completion"
FROM "Worklogs"
WHERE item-count > 0
SORT file.name DESC
```

---

## 2. People Engagement Over Time

Flattens the `people` array across all weekly notes so you can see how often each person appears in your worklog. Useful for spotting collaboration patterns or relationships that have gone quiet.

```dataviewjs
const pages = dv.pages('"Worklogs"').where(p => p.people && p.people.length > 0);
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

Lists all programs that appear in your worklogs, ranked by how many weeks they were active. Helps identify which programs are consuming the most sustained attention.

```dataviewjs
const pages = dv.pages('"Worklogs"').where(p => p.programs && p.programs.length > 0);
const counts = {};
for (const page of pages) {
  for (const prog of page.programs) {
    counts[prog] = (counts[prog] || 0) + 1;
  }
}
const rows = Object.entries(counts).sort((a, b) => b[1] - a[1]);
dv.table(["Program", "Weeks Active"], rows);
```

---

## 4. Items Completed This Month

Filters weekly notes to the current calendar month and sums up completed items. Add this to a monthly review note or a dashboard page.

```dataview
TABLE
  file.name AS "Week",
  done-count AS "Items Completed"
FROM "Worklogs"
WHERE done-count > 0
  AND dateformat(file.mtime, "yyyy-MM") = dateformat(date(today), "yyyy-MM")
SORT file.name ASC
```

---

## 5. Active P0 Items (Inline - Current Week)

Use this as an __inline query__ inside your current week's note to surface any items still marked P0. Paste the line below directly into the note body (not inside a code fence).

```
`$= dv.pages('"Worklogs"').where(p => p.file.name === dv.current().file.name).flatMap(p => p.p0_items ?? []).join(", ") || "None"`
```

> __Note:__ This requires your weekly template to populate a `p0_items` frontmatter list. If you track P0s inline in note body rather than frontmatter, use the Dataview JS approach below instead:

```dataviewjs
const current = dv.current();
const content = await dv.io.load(current.file.path);
const p0lines = content.split("\n").filter(l => l.match(/P0/i));
dv.list(p0lines.length > 0 ? p0lines : ["No P0 items this week"]);
```

---

## 6. Completion Rate Trend

Charts completion rate (done / total) as a table across all weeks. Use this to spot weeks where throughput dropped - useful for retrospectives or capacity conversations.

```dataviewjs
const pages = dv.pages('"Worklogs"')
  .where(p => p["item-count"] > 0)
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

Shows how often each tag appears across your worklog history. Useful for understanding what categories of work dominate your time.

```dataviewjs
const pages = dv.pages('"Worklogs"').where(p => p.tags && p.tags.length > 0);
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

Lists the 10 most recently modified files in your Worklogs folder. Useful for quickly resuming where you left off or finding notes you touched this week across sessions.

```dataview
TABLE
  file.mtime AS "Last Modified",
  item-count AS "Items",
  done-count AS "Done"
FROM "Worklogs"
SORT file.mtime DESC
LIMIT 10
```
