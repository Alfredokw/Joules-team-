#!/usr/bin/env python3
"""Shared helpers for the frozen Linux experiment protocol."""

from __future__ import annotations

import csv
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_FLAGS = [
    "-std=c11",
    "-O1",
    "-g",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-fno-omit-frame-pointer",
    "-fno-strict-aliasing",
    "-pthread",
]


def load_json(relative_path: str):
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def load_manifest():
    with (ROOT / "manifest.csv").open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def subject_by_id(subject_id: str):
    subjects = {row["id"]: row for row in load_manifest()}
    try:
        return subjects[subject_id]
    except KeyError as error:
        raise ValueError(f"unknown subject: {subject_id}") from error


def workload_n(subject, workload: str) -> int:
    if workload not in {"small", "large"}:
        raise ValueError(f"unsupported workload: {workload}")
    return int(subject[f"{workload}_n"])


def compile_command(subject, configuration: str, output: Path, cc: str):
    detectors = load_json("configs/detectors.json")
    compile_configuration = "baseline" if configuration == "memcheck" else configuration
    command = [cc, *BASE_FLAGS]
    if compile_configuration != "baseline":
        command.extend(detectors[compile_configuration]["compile_flags"])
    command.append(str(ROOT / subject["source"]))
    if subject["extra_sources"]:
        command.extend(str(ROOT / value) for value in subject["extra_sources"].split(";"))
    command.extend(["-o", str(output)])
    return command


def runtime_command(subject, configuration: str, workload: str, binary: Path):
    config = load_json("configs/experiment.json")
    detectors = load_json("configs/detectors.json")
    command = [
        str(binary),
        "--size",
        workload,
        "--threads",
        str(config["threads"]),
        "--seed",
        str(config["input_seed"]),
    ]
    if configuration == "memcheck":
        command = [*detectors["memcheck"]["command_prefix"], *command]
    return command


def runtime_environment(configuration: str):
    detectors = load_json("configs/detectors.json")
    environment = os.environ.copy()
    environment.update(detectors.get(configuration, {}).get("environment", {}))
    return environment


def configured_tool(config, key: str, environment_variable: str):
    override = os.environ.get(environment_variable)
    if override:
        return [override]
    value = config[key]
    if not isinstance(value, list) or not value:
        raise ValueError(f"{key} must be a non-empty JSON array")
    return [str(part) for part in value]
