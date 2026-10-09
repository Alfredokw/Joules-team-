#!/usr/bin/env python3
"""Verify frozen Small/Large workload sizes on the measurement server."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import platform
import random
import re
import shutil
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from experimentlib import (  # noqa: E402
    compile_command,
    runtime_command,
    runtime_environment,
    subject_by_id,
    workload_n,
)

CONFIG_PATH = ROOT / "calibration/server_precheck.json"
FIELDS = [
    "run_id", "phase", "application", "subject_id", "configuration",
    "workload", "input_n", "repetition", "elapsed_seconds", "return_code",
    "workload_complete", "reported_n", "input_matches_manifest", "status",
]


def command_version(command):
    if not command or shutil.which(command[0]) is None:
        return "unavailable"
    result = subprocess.run(
        [*command, "--version"], text=True, capture_output=True, check=False
    )
    text = (result.stdout or result.stderr).strip()
    return text.splitlines()[0] if text else f"return_code={result.returncode}"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_binaries(configurations, representatives, compiler, build_root):
    records = []
    binaries = {}
    for application, subject_id in representatives.items():
        subject = subject_by_id(subject_id)
        for configuration in configurations:
            compiled_as = "baseline" if configuration == "memcheck" else configuration
            compiled_key = (subject_id, compiled_as)
            if compiled_key not in binaries:
                output = build_root / subject_id / compiled_as
                output.parent.mkdir(parents=True, exist_ok=True)
                command = compile_command(subject, compiled_as, output, compiler)
                result = subprocess.run(command, text=True, capture_output=True, check=False)
                records.append({
                    "application": application,
                    "subject_id": subject_id,
                    "configuration": compiled_as,
                    "command": command,
                    "return_code": result.returncode,
                    "stderr": result.stderr,
                })
                if result.returncode != 0:
                    raise RuntimeError(
                        f"build failed for {subject_id} {compiled_as}: {result.stderr.strip()}"
                    )
                binaries[compiled_key] = output
            binaries[(subject_id, configuration)] = binaries[compiled_key]
    return binaries, records


def execute_job(job, binary, timeout, output_dir):
    subject = subject_by_id(job["subject_id"])
    expected_n = workload_n(subject, job["workload"])
    command = runtime_command(subject, job["configuration"], job["workload"], binary)
    environment = runtime_environment(job["configuration"])
    started = time.perf_counter()
    try:
        result = subprocess.run(
            command, text=True, capture_output=True, timeout=timeout,
            env=environment, check=False,
        )
        elapsed = time.perf_counter() - started
        complete = "WORKLOAD_COMPLETE" in result.stdout
        reported_values = re.findall(r"\bn=(\d+)\b", result.stdout)
        reported_n = int(reported_values[-1]) if reported_values else None
        input_matches = reported_n == expected_n
        return_code = result.returncode
        status = "ok" if complete and input_matches else (
            "input_mismatch" if complete else "incomplete"
        )
        stdout, stderr = result.stdout, result.stderr
    except subprocess.TimeoutExpired as error:
        elapsed = float(timeout)
        complete = False
        reported_n = None
        input_matches = False
        return_code = None
        status = "timeout"
        stdout, stderr = error.stdout or "", error.stderr or ""

    logs = output_dir / "logs"
    logs.mkdir(exist_ok=True)
    (logs / f"{job['run_id']}.stdout.log").write_text(stdout, encoding="utf-8")
    (logs / f"{job['run_id']}.stderr.log").write_text(stderr, encoding="utf-8")
    return {
        **job,
        "input_n": expected_n,
        "elapsed_seconds": f"{elapsed:.9f}",
        "return_code": "" if return_code is None else return_code,
        "workload_complete": int(complete),
        "reported_n": "" if reported_n is None else reported_n,
        "input_matches_manifest": int(input_matches),
        "status": status,
    }


def make_jobs(config):
    warmups = []
    measured = {index: [] for index in range(1, config["repetitions"] + 1)}
    for application, subject_id in config["representatives"].items():
        for configuration in config["configurations"]:
            for workload in ("small", "large"):
                warmups.append({
                    "phase": "warmup", "application": application,
                    "subject_id": subject_id, "configuration": configuration,
                    "workload": workload, "repetition": 0,
                })
                for repetition in measured:
                    measured[repetition].append({
                        "phase": "measured", "application": application,
                        "subject_id": subject_id, "configuration": configuration,
                        "workload": workload, "repetition": repetition,
                    })
    rng = random.Random(config["schedule_seed"])
    rng.shuffle(warmups)
    jobs = warmups
    for repetition in measured:
        rng.shuffle(measured[repetition])
        jobs.extend(measured[repetition])
    for index, job in enumerate(jobs, 1):
        job["run_id"] = f"precheck_{index:04d}"
    return jobs


def summarize(rows, config):
    grouped = {}
    for row in rows:
        if (
            row["phase"] != "measured"
            or not int(row["workload_complete"])
            or not int(row["input_matches_manifest"])
        ):
            continue
        key = (row["application"], row["configuration"], row["workload"])
        grouped.setdefault(key, []).append(float(row["elapsed_seconds"]))

    summaries, failures = [], []
    for application, subject_id in config["representatives"].items():
        subject = subject_by_id(subject_id)
        for configuration in config["configurations"]:
            small = grouped.get((application, configuration, "small"), [])
            large = grouped.get((application, configuration, "large"), [])
            complete = len(small) == config["repetitions"] and len(large) == config["repetitions"]
            small_median = statistics.median(small) if small else None
            large_median = statistics.median(large) if large else None
            ratio = (
                large_median / small_median
                if small_median is not None and large_median is not None and small_median > 0
                else None
            )
            ordered = ratio is not None and ratio > 1.0
            reference_ok = (
                configuration != config["reference_configuration"]
                or (ratio is not None and ratio >= config["minimum_reference_ratio"])
            )
            passed = complete and ordered and reference_ok
            item = {
                "application": application,
                "subject_id": subject_id,
                "configuration": configuration,
                "small_n": workload_n(subject, "small"),
                "large_n": workload_n(subject, "large"),
                "small_median_seconds": small_median,
                "large_median_seconds": large_median,
                "large_to_small_median_ratio": ratio,
                "complete_repetitions_per_size": min(len(small), len(large)),
                "passed": passed,
            }
            summaries.append(item)
            if not passed:
                failures.append(item)
    return summaries, failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--repetitions", type=int)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--results-dir")
    args = parser.parse_args()

    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    if args.repetitions is not None:
        if args.repetitions < 1:
            raise SystemExit("--repetitions must be positive")
        config["repetitions"] = args.repetitions
    if shutil.which(args.cc) is None:
        raise SystemExit(f"compiler not found: {args.cc}")
    jobs = make_jobs(config)
    if args.dry_run:
        print(json.dumps({"config": config, "run_count": len(jobs)}, indent=2))
        return

    if platform.system() != "Linux":
        raise SystemExit("the official workload precheck must run on the Linux measurement server")
    if "memcheck" in config["configurations"] and shutil.which("valgrind") is None:
        raise SystemExit("valgrind is required for the Memcheck precheck")

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_dir = (
        Path(args.results_dir).resolve()
        if args.results_dir
        else ROOT / "calibration/results" / f"server-{timestamp}"
    )
    output_dir.mkdir(parents=True, exist_ok=False)
    try:
        binaries, build_records = build_binaries(
            config["configurations"], config["representatives"], args.cc,
            ROOT / "calibration/.build",
        )
    except RuntimeError as error:
        raise SystemExit(str(error)) from error

    (output_dir / "build_record.json").write_text(
        json.dumps(build_records, indent=2) + "\n", encoding="utf-8"
    )
    environment = {
        "timestamp_utc": timestamp,
        "platform": platform.platform(),
        "python": sys.version,
        "compiler": args.cc,
        "compiler_version": command_version([args.cc]),
        "valgrind_version": command_version(["valgrind"]),
        "manifest_sha256": sha256(ROOT / "manifest.csv"),
        "experiment_config_sha256": sha256(ROOT / "configs/experiment.json"),
        "precheck_config": config,
        "mode": "official_server_precheck",
    }
    (output_dir / "environment.json").write_text(
        json.dumps(environment, indent=2) + "\n", encoding="utf-8"
    )

    rows = []
    with (output_dir / "workload_precheck.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        for index, job in enumerate(jobs, 1):
            binary = binaries[(job["subject_id"], job["configuration"])]
            row = execute_job(job, binary, config["timeout_seconds"], output_dir)
            rows.append(row)
            writer.writerow({key: row[key] for key in FIELDS})
            handle.flush()
            print(
                f"[{index}/{len(jobs)}] {row['application']} {row['configuration']} "
                f"{row['workload']} {row['elapsed_seconds']}s {row['status']}"
            )

    summaries, failures = summarize(rows, config)
    summary = {
        "passed": not failures,
        "official_server_precheck": True,
        "criteria": {
            "large_slower_than_small_all_configurations": True,
            "reference_configuration": config["reference_configuration"],
            "minimum_reference_ratio": config["minimum_reference_ratio"],
        },
        "conditions": summaries,
        "failures": failures,
    }
    (output_dir / "workload_precheck_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    print(f"results: {output_dir}")
    print(f"passed: {summary['passed']}")
    if failures:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
