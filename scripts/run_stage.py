#!/usr/bin/env python3
"""Compile and execute one scheduled condition inside the measurement window."""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
import time
from pathlib import Path

from experimentlib import (
    ROOT,
    compile_command,
    load_json,
    runtime_command,
    runtime_environment,
    subject_by_id,
    workload_n,
)


def write_metadata(path: Path, metadata):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--subject-id", required=True)
    parser.add_argument("--workload", choices=["small", "large"], required=True)
    parser.add_argument(
        "--configuration",
        choices=["baseline", "asan", "msan", "tsan", "memcheck"],
        required=True,
    )
    parser.add_argument("--artifact-dir", required=True)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--cc", default="clang")
    args = parser.parse_args()

    subject = subject_by_id(args.subject_id)
    config = load_json("configs/experiment.json")
    artifact_dir = Path(args.artifact_dir).resolve()
    metadata_path = Path(args.metadata).resolve()
    artifact_dir.mkdir(parents=True, exist_ok=True)
    binary = artifact_dir / "program"
    compile_stdout = artifact_dir / "compile.stdout.log"
    compile_stderr = artifact_dir / "compile.stderr.log"
    runtime_stdout = artifact_dir / "runtime.stdout.log"
    runtime_stderr = artifact_dir / "runtime.stderr.log"
    resource_log = artifact_dir / "resource-usage.txt"

    metadata = {
        "run_id": args.run_id,
        "measurement_scope": config["measurement_scope"],
        "subject_id": args.subject_id,
        "workload": args.workload,
        "input_n": workload_n(subject, args.workload),
        "configuration": args.configuration,
        "compile_command": [],
        "runtime_command": [],
        "compile_return_code": None,
        "runtime_return_code": None,
        "build_seconds": None,
        "runtime_seconds": None,
    }

    if config["measurement_scope"] == "build_and_run":
        build_command = compile_command(subject, args.configuration, binary, args.cc)
        metadata["compile_command"] = build_command
        started = time.perf_counter()
        with compile_stdout.open("w", encoding="utf-8") as out, compile_stderr.open(
            "w", encoding="utf-8"
        ) as err:
            build = subprocess.run(build_command, stdout=out, stderr=err, check=False)
        metadata["build_seconds"] = time.perf_counter() - started
        metadata["compile_return_code"] = build.returncode
        if build.returncode != 0:
            metadata["stage_status"] = "compile_failure"
            write_metadata(metadata_path, metadata)
            return
    elif config["measurement_scope"] == "execution_only":
        binary_configuration = "baseline" if args.configuration == "memcheck" else args.configuration
        binary = ROOT / "bin" / args.subject_id / binary_configuration
        if not binary.exists():
            metadata["stage_status"] = "missing_prebuilt_binary"
            write_metadata(metadata_path, metadata)
            return
        metadata["compile_return_code"] = 0
        metadata["build_seconds"] = 0.0
    else:
        raise SystemExit(f"unsupported measurement_scope: {config['measurement_scope']}")

    target_command = runtime_command(subject, args.configuration, args.workload, binary)
    metadata["runtime_command"] = target_command
    time_binary = shutil.which("time")
    if (
        platform.system() == "Linux"
        and time_binary
        and Path(time_binary).resolve() == Path("/usr/bin/time")
    ):
        measured_command = [time_binary, "-v", "-o", str(resource_log), *target_command]
    elif platform.system() == "Linux" and Path("/usr/bin/time").exists():
        measured_command = ["/usr/bin/time", "-v", "-o", str(resource_log), *target_command]
    else:
        measured_command = target_command

    started = time.perf_counter()
    with runtime_stdout.open("w", encoding="utf-8") as out, runtime_stderr.open(
        "w", encoding="utf-8"
    ) as err:
        runtime = subprocess.run(
            measured_command,
            stdout=out,
            stderr=err,
            env=runtime_environment(args.configuration),
            check=False,
        )
    metadata["runtime_seconds"] = time.perf_counter() - started
    metadata["runtime_return_code"] = runtime.returncode
    metadata["stage_status"] = "completed" if runtime.returncode == 0 else "nonzero_exit"
    write_metadata(metadata_path, metadata)


if __name__ == "__main__":
    main()
