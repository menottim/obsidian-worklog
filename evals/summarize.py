#!/usr/bin/env python3
"""Roll up eval runs into a pass rate and a median cost per case and config.

Single runs are not decisive for this skill - repeat runs of the same config
disagree often enough that a one-shot verdict is a coin flip on some cases - so
the interesting numbers are the rate across repeats and the spread in cost.

    evals/summarize.py                 # every run under evals/runs
    evals/summarize.py runs/2026*      # just these
"""
import csv
import glob
import statistics
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
targets = sys.argv[1:] or [str(HERE / "runs")]
files = sorted({f for t in targets for f in glob.glob(f"{t}/**/results.csv", recursive=True)
                or glob.glob(f"{t}/results.csv")})
# Quarantined batches live under runs/_invalid-*/ because a harness defect makes
# their numbers incomparable. Pooling them silently is how a withdrawn result
# comes back to life, so skip them unless asked for by name.
if not any("_invalid" in t for t in targets):
    files = [f for f in files if "_invalid" not in f]
if not files:
    sys.exit("no results.csv found")

rows = defaultdict(list)
for f in files:
    for r in csv.DictReader(open(f)):
        rows[(int(r["case"]), r["model"], r["effort"])].append(r)

print(f"{'case':<5} {'model':<8} {'effort':<8} {'runs':<5} {'pass':<7} "
      f"{'median $':<10} {'range $':<17} {'median s':<9} checks")
for key in sorted(rows):
    case, model, effort = key
    rs = rows[key]
    costs = sorted(float(r["cost_usd"]) for r in rs)
    secs = [int(r["seconds"]) for r in rs]
    passes = sum(r["pass"] == "pass" for r in rs)
    w = min(rs, key=lambda r: int(r["checks_passed"]))
    worst = f"{w['checks_passed']}/{w['checks_total']}"
    # A group spanning two different check totals means the grader changed
    # between runs, so its pass rate is pooling incomparable results.
    if len({r["checks_total"] for r in rs}) > 1:
        worst += "  [MIXED GRADERS]"
    print(f"{case:<5} {model:<8} {effort:<8} {len(rs):<5} {passes}/{len(rs):<5} "
          f"{statistics.median(costs):<10.3f} "
          f"{costs[0]:.3f}-{costs[-1]:<11.3f} {statistics.median(secs):<9.0f} worst {worst}")

total = sum(float(r["cost_usd"]) for rs in rows.values() for r in rs)
n = sum(len(rs) for rs in rows.values())
print(f"\n{n} runs, ${total:.2f}")
