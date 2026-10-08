#!/usr/bin/env python3
"""Audit campaign completeness without modifying raw measurements."""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter

from experimentlib import ROOT


def read_csv(path):
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-root", default="results")
    parser.add_argument("--allow-invalid", action="store_true")
    args = parser.parse_args()
    results = (ROOT / args.results_root).resolve()
    schedule = read_csv(results / "schedule.csv")
    warmups = read_csv(results / "raw" / "warmups.csv")
    measured = read_csv(results / "raw" / "executions.csv")
    scheduled_warmups = {row["run_id"] for row in schedule if row["phase"] == "warmup"}
    scheduled_measured = {row["run_id"] for row in schedule if row["phase"] == "measured"}
    observed_warmups = [row["run_id"] for row in warmups]
    observed_measured = [row["run_id"] for row in measured]
    invalid = [row for row in measured if row.get("valid") != "1"]
    missing_metrics = [
        row["run_id"]
        for row in measured
        if any(
            not row.get(field)
            for field in (
                "execution_time_seconds",
                "total_energy_consumption_joules",
                "average_power_watts",
                "peak_power_watts",
                "power_variability_watts",
                "peak_rss_bytes",
            )
        )
    ]
    errors = []
    if len(schedule) != 7440:
        errors.append(f"expected 7,440 schedule rows, found {len(schedule)}")
    if len(warmups) != 240:
        errors.append(f"expected 240 warm-ups, found {len(warmups)}")
    if len(measured) != 7200:
        errors.append(f"expected 7,200 measured rows, found {len(measured)}")
    if len(observed_warmups) != len(set(observed_warmups)):
        errors.append("duplicate warm-up run_id values")
    if len(observed_measured) != len(set(observed_measured)):
        errors.append("duplicate measured run_id values")
    if set(observed_warmups) != scheduled_warmups:
        errors.append("observed warm-up identifiers do not match the schedule")
    if set(observed_measured) != scheduled_measured:
        errors.append("observed measured identifiers do not match the schedule")
    if missing_metrics:
        errors.append(f"{len(missing_metrics)} measured rows have missing required metrics")
    if invalid and not args.allow_invalid:
        errors.append(f"{len(invalid)} measured rows are marked invalid")
    report = {
        "passed": not errors,
        "scheduled_rows": len(schedule),
        "warmup_rows": len(warmups),
        "measured_rows": len(measured),
        "invalid_rows": len(invalid),
        "missing_metric_rows": len(missing_metrics),
        "termination_status": dict(Counter(row.get("termination_status", "") for row in measured)),
        "detections_by_configuration": dict(
            Counter(row["configuration"] for row in measured if row.get("detected") == "1")
        ),
        "errors": errors,
    }
    output = results / "audit.json"
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    print(f"report: {output}")
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
