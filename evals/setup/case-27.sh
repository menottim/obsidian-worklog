#!/usr/bin/env bash
# Lower max_results so the guardrail triggers cheaply, off two 1-item pages
# instead of a huge fixture.
set -eu
VAULT="${1:?usage: case-27.sh <vault>}"
sed -i.bak 's/max_results: 100/max_results: 2/' "$VAULT/Sources/_dms.md"
rm -f "$VAULT/Sources/_dms.md.bak"
