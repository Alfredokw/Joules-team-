#!/usr/bin/env python3
"""Fail-fast validation for the final Ubuntu measurement server."""

from __future__ import annotations

import argparse
import csv
import json
import os
import platform
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

from experimentlib import ROOT, configured_tool, load_json, load_manifest
from run_experiment import read_energibridge, read_turbostat


EXPECTED_SIZES = {
    "juliet_case": (1_000_000, 26_000_000),
    "bst": (10_000, 120_000),
    "hash_table": (50_000, 300_000),
    "parallel_matrix": (128, 608),
}


def command_version(command):
    try:
        result = subprocess.run(
            [*command, "--version"], text=True, capture_output=True, timeout=15, check=False
        )
        text = (result.stdout or result.stderr).strip()
        return text.splitlines()[0] if text else f"return_code={result.returncode}"
    except Exception as error:  # recorded in the report
        return f"unavailable: {error}"


def cpu_details():
    path = Path("/proc/cpuinfo")
    if not path.exists():
        return {"model": "unknown", "physical_packages": 0, "logical_cpus": os.cpu_count()}
    blocks = path.read_text(errors="replace").split("\n\n")
    models = []
    packages = set()
    for block in blocks:
        fields = {}
        for line in block.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                fields[key.strip()] = value.strip()
        if fields.get("model name"):
            models.append(fields["model name"])
        if fields.get("physical id"):
            packages.add(fields["physical id"])
    return {
        "model": models[0] if models else "unknown",
        "physical_packages": len(packages),
        "logical_cpus": os.cpu_count(),
    }


def memory_bytes():
    path = Path("/proc/meminfo")
    if not path.exists():
        return 0
    for line in path.read_text().splitlines():
        if line.startswith("MemTotal:"):
            return int(line.split()[1]) * 1024
    return 0


def os_release():
    result = {}
    path = Path("/etc/os-release")
    if path.exists():
        for line in path.read_text().splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                result[key] = value.strip().strip('"')
    return result


def validate_static(report, errors):
    config = load_json("configs/experiment.json")
    subjects = load_manifest()
    groups = Counter(item["group"] for item in subjects)
    families = Counter(item["family"] for item in subjects)
    report["subject_count"] = len(subjects)
    report["groups"] = dict(groups)
    report["families"] = dict(families)
    if len(subjects) != 24:
        errors.append(f"expected 24 subjects, found {len(subjects)}")
    if groups != {"juliet": 12, "derived": 12}:
        errors.append(f"subject groups are not 12/12: {dict(groups)}")
    if len(families) != 4 or any(value != 6 for value in families.values()):
        errors.append(f"memory-error families are not balanced: {dict(families)}")
    for subject in subjects:
        expected = EXPECTED_SIZES.get(subject["base_application"])
        actual = (int(subject["small_n"]), int(subject["large_n"]))
        if actual != expected:
            errors.append(f"wrong workload sizes for {subject['id']}: {actual} != {expected}")
    if config["repetitions"] != 30:
        errors.append("the frozen protocol requires 30 repetitions")
    if len(config["round_seeds"]) != 30 or len(set(config["round_seeds"])) != 30:
        errors.append("round_seeds must contain 30 distinct predefined seeds")
    if config["configurations"] != ["baseline", "asan", "msan", "tsan", "memcheck"]:
        errors.append("unexpected sanitizer configuration list")
    if config["workloads"] != ["small", "large"]:
        errors.append("unexpected workload list")
    report["protocol_version"] = config["protocol_version"]
    report["measurement_scope"] = config["measurement_scope"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--static-only", action="store_true")
    parser.add_argument("--allow-hardware-mismatch", action="store_true")
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    args = parser.parse_args()

    report = {"platform": platform.platform(), "checks": []}
    errors = []
    warnings = []
    validate_static(report, errors)
    if args.static_only:
        report.update({"passed": not errors, "errors": errors, "warnings": warnings})
        print(json.dumps(report, indent=2))
        raise SystemExit(1 if errors else 0)

    if platform.system() != "Linux":
        errors.append("final measurements require Linux")
    release = os_release()
    report["os_release"] = release
    if release.get("ID") != "ubuntu" or release.get("VERSION_ID") != "24.04":
        errors.append(f"expected Ubuntu 24.04, found {release.get('PRETTY_NAME', 'unknown')}")
    cpu = cpu_details()
    report["cpu"] = cpu
    memory = memory_bytes()
    report["memory_bytes"] = memory
    hardware_issues = []
    if "Xeon Silver 4208" not in cpu["model"].replace("(R)", ""):
        hardware_issues.append(f"unexpected CPU model: {cpu['model']}")
    if cpu["physical_packages"] != 2:
        hardware_issues.append(f"expected 2 physical CPU packages, found {cpu['physical_packages']}")
    if memory < 350 * 1024**3:
        hardware_issues.append(f"expected approximately 384 GiB RAM, found {memory / 1024**3:.1f} GiB")
    if args.allow_hardware_mismatch:
        warnings.extend(hardware_issues)
    else:
        errors.extend(hardware_issues)

    config = load_json("configs/experiment.json")
    energibridge = configured_tool(config, "energibridge_command", "ENERGIBRIDGE_BIN")
    turbostat = configured_tool(config, "turbostat_command", "TURBOSTAT_BIN")
    required = {
        "clang": [args.cc],
        "valgrind": ["valgrind"],
        "energibridge": energibridge,
        "turbostat": turbostat,
        "gnu_time": ["/usr/bin/time"],
    }
    versions = {}
    for name, command in required.items():
        executable = command[0]
        available = Path(executable).exists() if "/" in executable else shutil.which(executable)
        if not available:
            errors.append(f"missing required tool: {name} ({executable})")
            versions[name] = "missing"
        else:
            versions[name] = command_version(command)
    report["tool_versions"] = versions

    if not any(Path("/sys/class/powercap").glob("intel-rapl*")):
        warnings.append("no intel-rapl entries found under /sys/class/powercap")
    msr_files = list(Path("/dev/cpu").glob("*/msr")) if Path("/dev/cpu").exists() else []
    if not msr_files or not all(os.access(path, os.R_OK) for path in msr_files):
        errors.append("MSR files are missing or unreadable; configure EnergiBridge/turbostat permissions")

    if not errors:
        check_dir = ROOT / "results" / "preflight-artifacts"
        check_dir.mkdir(parents=True, exist_ok=True)
        energy_csv = check_dir / "energibridge.csv"
        energy_run = subprocess.run(
            [
                *energibridge,
                "--output",
                str(energy_csv),
                "--interval",
                str(config["energibridge_interval_ms"]),
                "--max-execution",
                "10",
                "--",
                "/bin/sleep",
                "0.1",
            ],
            text=True,
            capture_output=True,
            timeout=20,
            check=False,
        )
        energy_data = read_energibridge(energy_csv)
        energy_ok = (
            energy_run.returncode == 0
            and energy_data["energy_joules"] is not None
            and len(energy_data["samples"]) >= 2
        )
        report["checks"].append({"name": "energibridge_live", "passed": energy_ok})
        if not energy_ok:
            errors.append("EnergiBridge live measurement failed")

        turbo_log = check_dir / "turbostat.txt"
        turbo_run = subprocess.run(
            [
                *turbostat,
                "--quiet",
                "--Summary",
                "--interval",
                str(config["turbostat_interval_seconds"]),
                "--num_iterations",
                "2",
                "--out",
                str(turbo_log),
            ],
            text=True,
            capture_output=True,
            timeout=20,
            check=False,
        )
        turbo_ok = turbo_run.returncode == 0 and len(read_turbostat(turbo_log)) >= 2
        report["checks"].append({"name": "turbostat_live", "passed": turbo_ok})
        if not turbo_ok:
            errors.append("turbostat live measurement failed")

    if not errors:
        build = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "build.py"),
                "--configuration",
                "all",
                "--keep-going",
                "--cc",
                args.cc,
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        report["checks"].append({"name": "all_sanitizer_builds", "passed": build.returncode == 0})
        if build.returncode != 0:
            errors.append("one or more Baseline/ASan/MSan/TSan builds failed")

    report.update({"passed": not errors, "errors": errors, "warnings": warnings})
    output = ROOT / "results" / "preflight.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    print(f"report: {output}")
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
