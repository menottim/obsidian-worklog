#!/usr/bin/env bash
# Case 46: the DM candidate is about a topic that already has a parked Backlog entry
# and a Thread. The skill must offer to wake it instead of offering a new item.
set -eu
VAULT="${1:?usage: case-46.sh <vault>}"
cat >> "$VAULT/Worklogs/Backlog.md" <<'EOF'
- **P2** 🔁 Parked - On-call rotation restructure: tiering proposal
  - Priya raised splitting the rotation into tiers; no decision yet (Aug 12)
  - Parked from [[2026-W33]] (Aug 12). Full history: [[Threads/on-call-rotation-restructure-tiering-proposal]]
EOF
cat > "$VAULT/Threads/on-call-rotation-restructure-tiering-proposal.md" <<'EOF'
---
type: thread
title: "On-call rotation restructure: tiering proposal"
opened: 2026-08-05
last-active: 2026-08-12
status: parked
summary: "Proposal to split the on-call rotation into tiers; parked pending a decision"
compacted: null
---

# On-call rotation restructure: tiering proposal

## Context

- Priya raised splitting the on-call rotation into tiers; no decision yet.

## Aug 12, 2026 - proposal raised

- Priya raised splitting the rotation into tiers; no decision yet (Aug 12)
EOF
