#!/usr/bin/env python3
"""Run the frozen 24 x 5 x 2 Linux measurement campaign."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import shlex
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path

from experimentlib import ROOT, configured_tool, load_json, load_manifest
from generate_schedule import generate, write_schedule

DETECTION_PATTERNS = {
    "asan": re.compile(r"AddressSanitizer|LeakSanitizer", re.I),
    "msan": re.compile(r"MemorySanitizer|use-of-uninitialized-value", re.I),
    "tsan": re.compile(r"ThreadSanitizer|data race", re.I),
    "memcheck": re.compile(
        r"Invalid read|Invalid write|definitely lost|indirectly lost|"
        r"uninitialised|uninitialized|Conditional jump|Use of uninitialised",
        re.I,
    ),
}

RESULT_FIELDS = [
    "run_id",
    "phase",
    "repetition",
    "order",
    "round_seed",
    "protocol_version",
    "measurement_scope",
    "subject_id",
    "group",
    "base_application",
    "family",
    "cwe",
    "specific_error",
    "workload",
    "input_n",
    "configuration",
    "input_seed",
    "threads",
    "cooldown_seconds",
    "build_seconds",
    "runtime_seconds",
    "execution_time_seconds",
    "measurement_wall_seconds",
    "total_energy_consumption_joules",
    "average_power_watts",
    "peak_power_watts",
    "power_variability_watts",
    "power_sample_count",
    "peak_rss_bytes",
    "compile_return_code",
    "runtime_return_code",
    "measurement_return_code",
    "termination_status",
    "workload_complete",
    "detected",
    "expected_primary_detector",
    "valid",
    "compile_command",
    "runtime_command",
    "energibridge_csv",
    "turbostat_log",
    "artifact_dir",
]


def optional_float(value):
    try:
        number = float(value)
        return number if math.isfinite(number) else None
    except (TypeError, ValueError):
        return None


def read_energibridge(path: Path):
    result = {
        "energy_joules": None,
        "average_power_watts": None,
        "duration_seconds": None,
        "samples": [],
    }
    if not path.exists() or path.stat().st_size == 0:
        return result

    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))

    points = []
    previous = None

    for row in rows:
        values = [
            optional_float(row.get(key))
            for key in (
                "Time",
                "PACKAGE_ENERGY (J)",
                "DRAM_ENERGY (J)",
            )
        ]
        if any(value is None for value in values):
            return result

        t, package, dram = values

        if previous is not None:
            if any(value < old for value, old in zip(values, previous)):
                # Reject counter resets/wraps or reversed timestamps.
                return result
        previous = values

        if points and t == points[-1][0]:
            # Keep the first reading at a duplicated timestamp.
            continue

        points.append((t, package + dram))

    if len(points) < 2:
        return result

    duration = (points[-1][0] - points[0][0]) / 1000.0
    energy = points[-1][1] - points[0][1]

    powers = [
        (e1 - e0) / ((t1 - t0) / 1000.0)
        for (t0, e0), (t1, e1) in zip(points, points[1:])
    ]

    result.update(
        energy_joules=energy,
        average_power_watts=energy / duration,
        duration_seconds=duration,
        samples=powers,
    )
    return result


def read_turbostat(path: Path):
    samples = []
    if not path.exists():
        return samples
    header = None
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = raw_line.split()
        if not parts:
            continue
        if any("PkgWatt" == part or "Pkg_W" == part for part in parts):
            header = parts
            continue
        if header is None or len(parts) != len(header):
            continue
        row = dict(zip(header, parts))
        package = next(
            (optional_float(row.get(name)) for name in ("PkgWatt", "Pkg_W") if name in row),
            None,
        )
        dram = next(
            (optional_float(row.get(name)) for name in ("RAMWatt", "RAM_W") if name in row),
            None,
        )
        if package is not None:
            samples.append(package + (dram or 0.0))
    return samples


def read_peak_rss(path: Path):
    if not path.exists():
        return None
    pattern = re.compile(r"Maximum resident set size \(kbytes\):\s*(\d+)")
    match = pattern.search(path.read_text(encoding="utf-8", errors="replace"))
    return int(match.group(1)) * 1024 if match else None


def stop_process_group(process):
    if process is None or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGINT)
        process.wait(timeout=5)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def read_completed_run_ids(paths):
    completed = set()
    for path in paths:
        if not path.exists():
            continue
        with path.open(newline="", encoding="utf-8") as handle:
            completed.update(row["run_id"] for row in csv.DictReader(handle))
    return completed


def append_result(path: Path, result):
    path.parent.mkdir(parents=True, exist_ok=True)
    exists = path.exists() and path.stat().st_size > 0
    with path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=RESULT_FIELDS, extrasaction="ignore")
        if not exists:
            writer.writeheader()
        writer.writerow(result)
        handle.flush()
        os.fsync(handle.fileno())


def relative(path: Path):
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def run_one(row, subject, config, args, results_root):
    run_id = row["run_id"]
    artifact_dir = results_root / "runs" / run_id
    metadata_path = artifact_dir / "stage-metadata.json"
    energibridge_csv = results_root / "raw" / "energibridge" / f"{run_id}.csv"
    energibridge_stdout = artifact_dir / "energibridge.stdout.log"
    energibridge_stderr = artifact_dir / "energibridge.stderr.log"
    turbostat_log = results_root / "raw" / "turbostat" / f"{run_id}.txt"
    turbostat_stderr = artifact_dir / "turbostat.stderr.log"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    energibridge_csv.parent.mkdir(parents=True, exist_ok=True)
    turbostat_log.parent.mkdir(parents=True, exist_ok=True)

    stage_command = [
        sys.executable,
        str(ROOT / "scripts" / "run_stage.py"),
        "--run-id",
        run_id,
        "--subject-id",
        row["subject_id"],
        "--workload",
        row["workload"],
        "--configuration",
        row["configuration"],
        "--artifact-dir",
        str(artifact_dir),
        "--metadata",
        str(metadata_path),
        "--cc",
        args.cc,
    ]

    turbostat = None
    turbostat_error_handle = None
    timed_out = False
    measurement_return_code = None
    started = time.perf_counter()
    try:
        if not args.no_turbostat:
            turbostat_command = [
                *configured_tool(config, "turbostat_command", "TURBOSTAT_BIN"),
                "--quiet",
                "--Summary",
                "--interval",
                str(config["turbostat_interval_seconds"]),
                "--out",
                str(turbostat_log),
            ]
            turbostat_error_handle = turbostat_stderr.open("w", encoding="utf-8")
            turbostat = subprocess.Popen(
                turbostat_command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=turbostat_error_handle,
                start_new_session=True,
            )

        if args.no_energibridge:
            measurement_command = stage_command
        else:
            measurement_command = [
                *configured_tool(config, "energibridge_command", "ENERGIBRIDGE_BIN"),
                "--summary",
                "--output",
                str(energibridge_csv),
                "--interval",
                str(config["energibridge_interval_ms"]),
                "--max-execution",
                str(config["execution_timeout_seconds"]),
                "--",
                *stage_command,
            ]
        with energibridge_stdout.open("w", encoding="utf-8") as out, energibridge_stderr.open(
            "w", encoding="utf-8"
        ) as err:
            measured = subprocess.Popen(
                measurement_command,
                stdout=out,
                stderr=err,
                start_new_session=True,
            )
            try:
                measurement_return_code = measured.wait(
                    timeout=float(config["execution_timeout_seconds"]) + 30.0
                )
            except subprocess.TimeoutExpired:
                timed_out = True
                stop_process_group(measured)
                measurement_return_code = measured.poll()
    finally:
        stop_process_group(turbostat)
        if turbostat_error_handle is not None:
            turbostat_error_handle.close()
    wall_seconds = time.perf_counter() - started

    metadata = {}
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    runtime_stdout = artifact_dir / "runtime.stdout.log"
    runtime_stderr = artifact_dir / "runtime.stderr.log"
    stdout_text = runtime_stdout.read_text(errors="replace") if runtime_stdout.exists() else ""
    stderr_text = runtime_stderr.read_text(errors="replace") if runtime_stderr.exists() else ""
    detected = bool(
        DETECTION_PATTERNS.get(row["configuration"], re.compile(r"a^", re.I)).search(
            stderr_text
        )
    )
    workload_complete = "WORKLOAD_COMPLETE" in stdout_text

    energy = read_energibridge(energibridge_csv) if not args.no_energibridge else {
        "energy_joules": None,
        "average_power_watts": None,
        "duration_seconds": None,
        "samples": [],
    }
    power_samples = read_turbostat(turbostat_log) if not args.no_turbostat else []
    build_seconds = metadata.get("build_seconds")
    runtime_seconds = metadata.get("runtime_seconds")
    elapsed_parts = [value for value in (build_seconds, runtime_seconds) if value is not None]
    execution_seconds = sum(elapsed_parts) if elapsed_parts else None
    energy_joules = energy["energy_joules"]
    average_power = (
        energy_joules / energy["duration_seconds"]
        if energy_joules is not None
        and energy["duration_seconds"] is not None
        and energy["duration_seconds"] > 0
        else energy["average_power_watts"]
    )
    compile_rc = metadata.get("compile_return_code")
    runtime_rc = metadata.get("runtime_return_code")
    stage_status = metadata.get("stage_status", "measurement_failure")
    if timed_out:
        termination_status = "timeout"
    elif stage_status == "compile_failure":
        termination_status = "compile_failure"
    elif not workload_complete and runtime_rc is not None:
        termination_status = "workload_incomplete"
    elif runtime_rc == 0:
        termination_status = "completed"
    elif runtime_rc is not None:
        termination_status = "nonzero_exit"
    else:
        termination_status = "measurement_failure"

    measurement_ok = (
        not args.no_energibridge
        and not args.no_turbostat
        and energy_joules is not None
        and len(power_samples) >= 2
        and measurement_return_code == 0
    )
    comparable = (
        compile_rc == 0
        and workload_complete
        and not timed_out
        and (runtime_rc == 0 or row["configuration"] != "baseline")
    )
    valid = comparable and measurement_ok
    result = {
        **row,
        "protocol_version": config["protocol_version"],
        "measurement_scope": config["measurement_scope"],
        "cwe": subject["cwe"],
        "specific_error": subject["specific_error"],
        "input_seed": config["input_seed"],
        "threads": config["threads"],
        "build_seconds": "" if build_seconds is None else f"{build_seconds:.9f}",
        "runtime_seconds": "" if runtime_seconds is None else f"{runtime_seconds:.9f}",
        "execution_time_seconds": "" if execution_seconds is None else f"{execution_seconds:.9f}",
        "measurement_wall_seconds": f"{wall_seconds:.9f}",
        "total_energy_consumption_joules": "" if energy_joules is None else f"{energy_joules:.9f}",
        "average_power_watts": "" if average_power is None else f"{average_power:.9f}",
        "peak_power_watts": "" if not power_samples else f"{max(power_samples):.9f}",
        "power_variability_watts": "" if len(power_samples) < 2 else f"{statistics.pstdev(power_samples):.9f}",
        "power_sample_count": len(power_samples),
        "peak_rss_bytes": read_peak_rss(artifact_dir / "resource-usage.txt") or "",
        "compile_return_code": "" if compile_rc is None else compile_rc,
        "runtime_return_code": "" if runtime_rc is None else runtime_rc,
        "measurement_return_code": "" if measurement_return_code is None else measurement_return_code,
        "termination_status": termination_status,
        "workload_complete": int(workload_complete),
        "detected": int(detected),
        "expected_primary_detector": subject["primary_detector"],
        "valid": int(valid),
        "compile_command": shlex.join(metadata.get("compile_command", [])),
        "runtime_command": shlex.join(metadata.get("runtime_command", [])),
        "energibridge_csv": relative(energibridge_csv) if energibridge_csv.exists() else "",
        "turbostat_log": relative(turbostat_log) if turbostat_log.exists() else "",
        "artifact_dir": relative(artifact_dir),
    }
    binary = artifact_dir / "program"
    if binary.exists() and not args.keep_binaries:
        binary.unlink()
    return result


def select_rows(rows, args):
    selected = []
    for row in rows:
        repetition = int(row["repetition"])
        if args.no_warmup and row["phase"] == "warmup":
            continue
        if row["phase"] == "measured":
            if args.repetitions is not None and repetition > args.repetitions:
                continue
            if repetition < args.start_round or repetition > args.end_round:
                continue
        if args.configuration != "all" and row["configuration"] != args.configuration:
            continue
        if args.subject and row["subject_id"] != args.subject:
            continue
        if args.workload != "all" and row["workload"] != args.workload:
            continue
        selected.append(row)
    return selected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repetitions", type=int)
    parser.add_argument("--start-round", type=int, default=1)
    parser.add_argument("--end-round", type=int, default=30)
    parser.add_argument(
        "--configuration",
        choices=["all", "baseline", "asan", "msan", "tsan", "memcheck"],
        default="all",
    )
    parser.add_argument("--subject")
    parser.add_argument("--workload", choices=["all", "small", "large"], default="all")
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--generate-only", action="store_true")
    parser.add_argument("--no-warmup", action="store_true")
    parser.add_argument("--no-cooldown", action="store_true")
    parser.add_argument("--no-energibridge", action="store_true")
    parser.add_argument("--no-turbostat", action="store_true")
    parser.add_argument("--skip-preflight-check", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--keep-binaries", action="store_true")
    parser.add_argument("--results-root", default="results")
    args = parser.parse_args()

    config = load_json("configs/experiment.json")
    subjects = {row["id"]: row for row in load_manifest()}
    results_root = (ROOT / args.results_root).resolve()
    if results_root != ROOT and ROOT not in results_root.parents:
        raise SystemExit("--results-root must stay inside the package directory")
    rows = generate()
    schedule_path = results_root / "schedule.csv"
    write_schedule(schedule_path, rows)
    print("schedule: 240 warm-ups + 7,200 measured executions ->", schedule_path)
    if args.generate_only:
        return

    if not args.skip_preflight_check:
        preflight_path = ROOT / "results" / "preflight.json"
        if not preflight_path.exists():
            raise SystemExit("missing results/preflight.json; run: python3 scripts/preflight.py")
        preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
        if not preflight.get("passed"):
            raise SystemExit("preflight did not pass; inspect results/preflight.json")

    selected = select_rows(rows, args)
    warmup_path = results_root / "raw" / "warmups.csv"
    measured_path = results_root / "raw" / "executions.csv"
    completed = read_completed_run_ids([warmup_path, measured_path]) if args.resume else set()
    if not args.resume and (warmup_path.exists() or measured_path.exists()):
        raise SystemExit("result CSV already exists; use --resume or archive results first")
    pending = [row for row in selected if row["run_id"] not in completed]
    print(f"selected: {len(selected)}; already complete: {len(selected) - len(pending)}; pending: {len(pending)}")

    for index, row in enumerate(pending, 1):
        subject = subjects[row["subject_id"]]
        print(
            f"[{index}/{len(pending)}] {row['phase']} r={row['repetition']} "
            f"{row['subject_id']} {row['workload']} {row['configuration']}",
            flush=True,
        )
        result = run_one(row, subject, config, args, results_root)
        target = warmup_path if row["phase"] == "warmup" else measured_path
        append_result(target, result)
        if not args.no_cooldown:
            time.sleep(float(row["cooldown_seconds"]))


if __name__ == "__main__":
    main()
