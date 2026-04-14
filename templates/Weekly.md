---
type: worklog
week: <% tp.file.title %>
date-start: <% tp.date.weekday("YYYY-MM-DD", 0, tp.file.title, "YYYY-[W]WW") %>
date-end: <% tp.date.weekday("YYYY-MM-DD", 4, tp.file.title, "YYYY-[W]WW") %>
status: active
prev: "[[<% tp.date.now("YYYY-[W]WW", -7, tp.file.title, "YYYY-[W]WW") %>]]"
---

# Week of <% tp.date.weekday("MMM D", 0, tp.file.title, "YYYY-[W]WW") %>, <% tp.date.weekday("YYYY", 0, tp.file.title, "YYYY-[W]WW") %>
