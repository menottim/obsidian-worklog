---
type: thread
title: "Platform Migration Stage routing regression"
opened: 2026-04-30
last-active: 2026-05-06
status: live
week: "[[2026-W20]]"
programs:
  - "[[Platform Migration]]"
people:
  - "[[Marcus Williams]]"
  - "[[Lisa Park]]"
summary: "data-plane routing regression blocks Stage promotion; fix PR in review, May 13 merge target"
compacted: null
---

# Platform Migration Stage routing regression

## Context

- Regression in data-plane routing found before Stage promotion. [[Marcus Williams]] owns the root cause and the fix.
- Stage promotion target is May 15. Production target is June 3.

## May 6, 2026 - outage pulled Marcus off the investigation

- Paused for the May 6 outage; [[Marcus Williams|Marcus]] back on it May 7 (May 6)

## May 5, 2026 - suspected W17 infra change

- Config drift from the W17 infrastructure change is the lead suspect; [[Lisa Park]] confirmed the change window (May 5)

## Apr 30, 2026 - first report

- Smoke test failure on two of three migrated services; promotion on hold (Apr 30)
