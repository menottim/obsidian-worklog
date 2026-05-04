---
type: meeting-notes-via-email
channel_name: "#example-meeting-notes"
channel_id: C0EXAMPLE0
nudge_threshold_days: 5
last_scan_ts: "2026-05-04T09:14:32Z"
first_scan_lookback_days: 14
---

# #example-meeting-notes

Channel where weekly leadership-team meeting notes are forwarded from a Google
Group as email attachments. Each new meeting becomes a top-of-thread post; the
team responds in-thread with follow-ups, decisions, and action items.

This source is ingested via `/worklog pull` into `Meetings/YYYY-MM-DD-<slug>.md`.
Stale-channel nudge fires on `/worklog rollover` / `tidy` / `audit` if
`last_scan_ts` is older than 5 days.
