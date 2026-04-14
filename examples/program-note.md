---
type: program
name: Platform Migration
status: in-flight
owner: Marcus Williams
stakeholders:
  - Jordan
  - SRE Lead
  - AppSec
quarter: Q2 2026
---

# Platform Migration

## Context

- **2026-W14** · Program kicked off — [[Marcus Williams]] established as DRI; initial scope is migrating three legacy services off the monolithic data plane to the new mesh architecture; target completion Q3 2026
- **2026-W16** · First milestone slipped one week: environment parity issues in Dev blocked early integration testing; [[Marcus Williams]] flagged early, adjusted timeline, no impact to Stage target date — good signal on proactive communication
- **2026-W18** · [[Marcus Williams]] published BGP topology doc; Jordan reviewed and approved; SRE sign-off pending; Stage environment promotion criteria drafted and under review — program back on track after W16 slip
- **2026-W19** · Stage promotion criteria approved; BGP topology doc cleared; regression in data-plane routing discovered during pre-promotion smoke test — root cause under investigation by [[Marcus Williams]], attributed to config drift introduced in W17 infrastructure change
- **2026-W20** · Routing regression narrowed to BGP config drift; PR up for review (May 12); traffic-shaping RFC from [[Marcus Williams]] teed up for Thursday all-hands review; [[Priya Patel]] looped in for [[Cloud Security Review]] integration checkpoint ahead of production promotion
- **2026-W20** · Stage environment still blocked pending regression fix; if PR merges by May 13, Stage promotion stays on schedule; production target remains June 3
