---
type: program
summary: "Moving three legacy services onto the new mesh; Stage blocked on a routing fix, production June 3"
aliases:
  - platform migration
  - mesh migration
compacted: 2026-05-15
---

# Platform Migration

## Context

- Migrates three legacy services off the monolithic data plane to the new mesh. Target: production June 3.
- DRI: [[Marcus Williams]]. [[Priya Patel]] covers the [[Cloud Security Review]] checkpoint before production.
- Current blocker: data-plane routing regression. See [[Threads/platform-migration-stage-routing-regression|Stage routing regression]].

## Recent

## May 12, 2026 - fix in review

- Regression narrowed to BGP config drift. Fix PR is up; Stage promotion holds if it merges by May 13.

## May 7, 2026 - regression reproduced

- Pre-promotion smoke test reproduced the routing regression first seen Apr 30. Root cause still open.

## History

- Apr 2026: kickoff, Dev environment parity slip (one week, Stage date held), BGP topology doc approved (4 entries folded)
