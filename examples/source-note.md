---
type: meeting-notes-via-email
channel_name: "#example-meeting-notes"
channel_id: C0EXAMPLE0
nudge_threshold_days: 5
last_scan_ts: "2026-05-11T19:22:00Z"
first_scan_lookback_days: 14
---

# #example-meeting-notes

Weekly leadership meeting notes arrive here as forwarded email from a Google Group.
Each meeting is one top-of-thread post. The team replies in the thread with
follow-ups, decisions, and action items.

`/worklog pull` writes one `Meetings/YYYY-MM-DD-<slug>.md` note per thread.
`/worklog rollover`, `tidy`, and `audit` show a reminder when `last_scan_ts` is
more than 5 days old.
