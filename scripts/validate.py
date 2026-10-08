#!/usr/bin/env python3
import argparse
import csv
import json
import platform
import re
import subprocess
from collections import Counter
from pathlib import Path

from experimentlib import load_json

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeats", type=int, default=1)
    args = parser.parse_args()
    with (ROOT / "manifest.csv").open(newline="", encoding="utf-8") as handle:
        subjects = list(csv.DictReader(handle))
    config = load_json("configs/experiment.json")
    errors = []
    if len(subjects) != 24: errors.append(f"expected 24 subjects, found {len(subjects)}")
    groups = Counter(item["group"] for item in subjects)
    families = Counter(item["family"] for item in subjects)
    if groups != {"juliet": 12, "derived": 12}: errors.append(f"unbalanced groups: {groups}")
    if any(count != 6 for count in families.values()) or len(families) != 4: errors.append(f"unbalanced families: {families}")
    subprocess.run(["python3", str(ROOT / "scripts/build.py"), "--configuration", "baseline"], check=True)
    checks = []
    for subject in subjects:
        binary = ROOT / "bin" / subject["id"] / "baseline"
        for workload in ("small", "large"):
            for repetition in range(1, args.repeats + 1):
                result = subprocess.run(
                    [
                        str(binary),
                        "--size",
                        workload,
                        "--threads",
                        str(config["threads"]),
                        "--seed",
                        str(config["input_seed"]),
                    ],
                    text=True,
                    capture_output=True,
                )
                complete = "WORKLOAD_COMPLETE" in result.stdout
                passed = result.returncode == 0 and complete
                checks.append({"subject_id": subject["id"], "check": f"plain_{workload}_completes",
                               "repetition": repetition, "passed": passed,
                               "return_code": result.returncode, "detail": result.stderr[-500:]})
                if not passed: errors.append(f"plain {workload} repetition {repetition} failed: {subject['id']}")
    report = {
        "platform": platform.platform(),
        "subject_count": len(subjects),
        "plain_repetitions_per_workload": args.repeats,
        "groups": groups,
        "families": families,
        "checks": checks,
        "limitations": [
            "MSan and Valgrind Memcheck require final validation on the Ubuntu measurement host.",
            "Large workloads must be pilot-calibrated and revalidated on the measurement host.",
            "Undefined behavior can vary by compiler and allocator; admission requires successful host-specific pilot runs."
        ],
        "errors": errors
    }
    (ROOT / "results").mkdir(exist_ok=True)
    (ROOT / "results/validation.json").write_text(json.dumps(report, indent=2, default=dict) + "\n")
    if errors:
        raise SystemExit("validation failed:\n" + "\n".join(errors))
    print("validation passed: all 24 plain subjects completed Small and Large workloads")


if __name__ == "__main__":
    main()
