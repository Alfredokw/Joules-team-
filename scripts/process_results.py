#!/usr/bin/env python3
"""Create paired runtime and energy overhead factors."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from experimentlib import ROOT

SOURCE = ROOT / "results/raw/executions.csv"
TARGET = ROOT / "results/processed/executions_with_overheads.csv"


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=str(SOURCE.relative_to(ROOT)))
    parser.add_argument("--target", default=str(TARGET.relative_to(ROOT)))
    args = parser.parse_args()
    source = ROOT / args.source
    target = ROOT / args.target
    with source.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit("no measured rows found")

    baselines = {
        (row["subject_id"], row["workload"], row["repetition"]): row
        for row in rows
        if row["configuration"] == "baseline" and row["phase"] == "measured"
    }
    output = []
    for original in rows:
        row = dict(original)
        key = (row["subject_id"], row["workload"], row["repetition"])
        baseline = baselines.get(key)
        row["runtime_overhead_factor"] = ""
        row["energy_overhead_factor"] = ""
        row["pair_valid"] = "0"
        if baseline is not None and row.get("valid") == "1" and baseline.get("valid") == "1":
            t0 = number(baseline.get("execution_time_seconds"))
            t1 = number(row.get("execution_time_seconds"))
            e0 = number(baseline.get("total_energy_consumption_joules"))
            e1 = number(row.get("total_energy_consumption_joules"))
            if t0 is not None and t0 > 0 and t1 is not None and e0 is not None and e0 > 0 and e1 is not None:
                row["runtime_overhead_factor"] = f"{t1 / t0:.9f}"
                row["energy_overhead_factor"] = f"{e1 / e0:.9f}"
                row["pair_valid"] = "1"
        output.append(row)

    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(output[0]))
        writer.writeheader()
        writer.writerows(output)
    valid_pairs = sum(row["pair_valid"] == "1" for row in output)
    print(f"wrote {len(output)} rows ({valid_pairs} valid paired values) to {target}")


if __name__ == "__main__":
    main()
