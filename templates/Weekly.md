---
type: worklog
week: <% tp.file.title %>
date-start: <% tp.date.now("YYYY-MM-DD", 0, tp.file.title, "GGGG-[W]WW") %>
date-end: <% tp.date.now("YYYY-MM-DD", 4, tp.file.title, "GGGG-[W]WW") %>
status: active
prev: "[[<% tp.date.now("GGGG-[W]WW", -7, tp.file.title, "GGGG-[W]WW") %>]]"
---

# Week of <% tp.date.now("MMM D, YYYY", 0, tp.file.title, "GGGG-[W]WW") %>
