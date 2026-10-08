#!/usr/bin/env python3
"""Generate the frozen warm-up and measured schedules."""

from __future__ import annotations

import argparse
import csv
import random

from experimentlib import ROOT, load_json, load_manifest, workload_n

FIELDS = [
    "run_id",
    "phase",
    "repetition",
    "order",
    "round_seed",
    "subject_id",
    "group",
    "base_application",
    "family",
    "workload",
    "input_n",
    "configuration",
    "cooldown_seconds",
]


def condition_rows(subjects, config):
    return [
        (subject, workload, configuration)
        for subject in subjects
        for workload in config["workloads"]
        for configuration in config["configurations"]
    ]


def materialize(phase, repetition, seed, conditions):
    current = list(conditions)
    random.Random(seed).shuffle(current)
    rows = []
    for order, (subject, workload, configuration) in enumerate(current, 1):
        prefix = "W" if phase == "warmup" else f"r{repetition:02d}"
        rows.append(
            {
                "run_id": f"{prefix}_o{order:03d}_{subject['id']}_{workload}_{configuration}",
                "phase": phase,
                "repetition": repetition,
                "order": order,
                "round_seed": seed,
                "subject_id": subject["id"],
                "group": subject["group"],
                "base_application": subject["base_application"],
                "family": subject["family"],
                "workload": workload,
                "input_n": workload_n(subject, workload),
                "configuration": configuration,
                "cooldown_seconds": subject["cooldown_seconds"],
            }
        )
    return rows


def generate(repetitions=None):
    config = load_json("configs/experiment.json")
    subjects = load_manifest()
    repetitions = config["repetitions"] if repetitions is None else repetitions
    if repetitions < 1 or repetitions > len(config["round_seeds"]):
        raise ValueError("repetitions must fit the predefined round_seeds list")
    conditions = condition_rows(subjects, config)
    rows = []
    if config["warmups_per_combination"] != 1:
        raise ValueError("the frozen protocol requires exactly one warm-up per condition")
    rows.extend(materialize("warmup", 0, config["warmup_seed"], conditions))
    for repetition, seed in enumerate(config["round_seeds"][:repetitions], 1):
        rows.extend(materialize("measured", repetition, seed, conditions))
    return rows


def write_schedule(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repetitions", type=int)
    parser.add_argument("--output", default="results/schedule.csv")
    args = parser.parse_args()
    rows = generate(args.repetitions)
    output = ROOT / args.output
    write_schedule(output, rows)
    warmups = sum(row["phase"] == "warmup" for row in rows)
    measured = sum(row["phase"] == "measured" for row in rows)
    print(f"wrote {warmups} warm-ups and {measured} measured executions to {output}")


if __name__ == "__main__":
    main()
