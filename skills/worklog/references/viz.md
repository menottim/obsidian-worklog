# /worklog viz — full detail

(Loaded on demand by SKILL.md.)

### `/worklog viz [period]`

Generate standalone HTML files with D3.js charts for visual analysis. Period
parsing uses the same logic as `/worklog summary`.

**Syntax:**

```
/worklog viz month        # current calendar month
/worklog viz quarter      # current quarter
/worklog viz W11-W16      # custom week range
```

**Output:**

Create the `Reports/` directory if it doesn't exist. Generate:
- `Reports/2026-April-viz.html`
- `Reports/2026-Q2-viz.html`
- `Reports/2026-W11-W16-viz.html`

**How to generate:**

1. Read all weekly files in the range (same as `/worklog summary`)
2. Collect data from enriched frontmatter (`item-count`, `done-count`, `programs[]`)
   and body parsing (subgroup item counts, P0/P1/P2 counts per week)
3. Read the HTML template from `references/viz-template.html` (bundled with this skill)
4. Replace `{{TITLE}}` with the period name (e.g., "April 2026")
5. Replace `{{SUBTITLE}}` with the source info (e.g., "Sourced from W15, W16 (as of Apr 13)")
6. Replace the `// DATA_PLACEHOLDER` line with `const data = { ... };` containing
   the aggregated data as a JSON object matching the schema described in the template
7. Write the completed HTML file to `Reports/`

The template includes four charts: time allocation pie, program activity heatmap,
P0 trend line, and completion rate stacked bars. Using the template ensures
consistent styling and layout across invocations.

After writing, tell the user: "Visualization saved to Reports/<filename>.html -
open in a browser to view."
