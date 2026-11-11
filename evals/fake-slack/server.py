#!/usr/bin/env python3
"""Deterministic stand-in for the Slack MCP server, for eval runs only.

The pull flow is the largest untested surface in evals.json and it cannot be
exercised against real Slack: results would depend on whatever happened to be in
a channel that day. This serves a fixture instead, so a pull case means the same
thing on every run and on every machine.

Scenario JSON is read from $FAKE_SLACK_SCENARIO. Message timestamps are stored as
`hours_ago` and converted to Slack `ts` strings at startup, which keeps a fixture
inside the source's lookback window no matter when it runs.
"""
import json
import os
import sys
import time

SCENARIO = json.load(open(os.environ["FAKE_SLACK_SCENARIO"]))
NOW = time.time()


def ts_of(unit):
    return f"{NOW - unit['hours_ago'] * 3600:.6f}"


CHANNEL = SCENARIO["channel"]
USERS = SCENARIO.get("users", {})

# Flatten the fixture into Slack-shaped messages once, so every tool call that
# refers to a thread_ts sees the same value.
MESSAGES = []
THREADS = {}
for unit in SCENARIO["units"]:
    ts = ts_of(unit)
    replies = unit.get("replies", [])
    MESSAGES.append({
        "ts": ts,
        "user": unit["user"],
        "user_name": USERS.get(unit["user"], {}).get("real_name", unit["user"]),
        "text": unit["text"],
        "reply_count": len(replies),
        "thread_ts": ts if replies else None,
        "permalink": f"https://example.slack.com/archives/{CHANNEL['id']}/p{ts.replace('.', '')}",
    })
    if replies:
        THREADS[ts] = [{
            "ts": f"{float(ts) + 60 * (i + 1):.6f}",
            "user": r["user"],
            "user_name": USERS.get(r["user"], {}).get("real_name", r["user"]),
            "text": r["text"],
        } for i, r in enumerate(replies)]

TOOLS = [
    {"name": "slack_read_channel",
     "description": "List top-level messages in a channel.",
     "inputSchema": {"type": "object",
                     "properties": {"channel_id": {"type": "string"},
                                    "oldest": {"type": "string"},
                                    "limit": {"type": "integer"},
                                    "include_bots": {"type": "boolean"}},
                     "required": ["channel_id"]}},
    {"name": "slack_read_thread",
     "description": "Fetch a thread: parent message plus all replies.",
     "inputSchema": {"type": "object",
                     "properties": {"channel_id": {"type": "string"},
                                    "thread_ts": {"type": "string"}},
                     "required": ["channel_id", "thread_ts"]}},
    {"name": "slack_search_channels",
     "description": "Resolve a channel name to a channel ID.",
     "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}},
                     "required": ["query"]}},
    {"name": "slack_search_users",
     "description": "Resolve a handle or user ID to a display name.",
     "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}},
                     "required": ["query"]}},
]


def call(name, args):
    if name == "slack_read_channel":
        oldest = float(args.get("oldest") or 0)
        return {"channel": CHANNEL,
                "messages": [m for m in MESSAGES if float(m["ts"]) > oldest]}
    if name == "slack_read_thread":
        ts = args.get("thread_ts", "")
        parent = next((m for m in MESSAGES if m["ts"] == ts), None)
        if parent is None:
            return {"error": f"no thread at {ts}"}
        return {"parent": parent, "replies": THREADS.get(ts, [])}
    if name == "slack_search_channels":
        q = args.get("query", "").lstrip("#")
        return {"channels": [CHANNEL] if q in CHANNEL["name"] else []}
    if name == "slack_search_users":
        q = args.get("query", "")
        hits = [{"id": uid, **u} for uid, u in USERS.items()
                if q.lower() in uid.lower() or q.lower() in json.dumps(u).lower()]
        return {"users": hits}
    return {"error": f"unknown tool {name}"}


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
    except json.JSONDecodeError:
        continue
    method, rid = req.get("method"), req.get("id")
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": rid, "result": {
            "protocolVersion": req.get("params", {}).get("protocolVersion", "2024-11-05"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "fake-slack", "version": "1.0.0"}}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": rid, "result": {"tools": TOOLS}})
    elif method == "tools/call":
        p = req.get("params", {})
        out = call(p.get("name", ""), p.get("arguments", {}))
        send({"jsonrpc": "2.0", "id": rid, "result": {
            "content": [{"type": "text", "text": json.dumps(out, indent=1)}]}})
    elif rid is not None:
        send({"jsonrpc": "2.0", "id": rid, "result": {}})
