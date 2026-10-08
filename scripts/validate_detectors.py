#!/usr/bin/env python3
import csv
import json
import os
import platform
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "asan": re.compile(r"AddressSanitizer|LeakSanitizer", re.I),
    "msan": re.compile(r"MemorySanitizer|use-of-uninitialized-value", re.I),
    "tsan": re.compile(r"ThreadSanitizer|data race", re.I),
    "memcheck": re.compile(r"Invalid read|definitely lost|uninitialised|uninitialized|Conditional jump", re.I),
}


def main():
    with (ROOT / "manifest.csv").open(newline="", encoding="utf-8") as handle:
        subjects = list(csv.DictReader(handle))
    detectors = json.loads((ROOT / "configs/detectors.json").read_text())
    config = json.loads((ROOT / "configs/experiment.json").read_text())
    results = []
    for detector in ("asan", "msan", "tsan", "memcheck"):
        if detector == "memcheck":
            if shutil.which("valgrind") is None:
                results.append({"detector": detector, "status": "unavailable", "detail": "valgrind not found"})
                continue
        else:
            build = subprocess.run(["python3", str(ROOT / "scripts/build.py"), "--configuration", detector, "--keep-going"], text=True, capture_output=True)
            if build.returncode != 0:
                results.append({"detector": detector, "status": "unavailable", "detail": build.stderr[-2000:]})
                continue
        for subject in subjects:
            if subject["primary_detector"] != detector: continue
            binary_configuration = "baseline" if detector == "memcheck" else detector
            binary = ROOT / "bin" / subject["id"] / binary_configuration
            command = [
                str(binary),
                "--size",
                "small",
                "--threads",
                str(config["threads"]),
                "--seed",
                str(config["input_seed"]),
            ]
            environment = os.environ.copy()
            if detector == "memcheck": command = detectors[detector]["command_prefix"] + command
            else: environment.update(detectors[detector].get("environment", {}))
            if detector == "asan" and platform.system() == "Darwin":
                environment["ASAN_OPTIONS"] = "halt_on_error=0:detect_leaks=0"
            run = subprocess.run(command, text=True, capture_output=True, env=environment)
            detected = bool(PATTERNS[detector].search(run.stderr))
            completed = "WORKLOAD_COMPLETE" in run.stdout
            results.append({"detector": detector, "subject_id": subject["id"],
                            "status": "passed" if detected and completed else "failed",
                            "detected": detected, "workload_complete": completed,
                            "return_code": run.returncode, "detail": run.stderr[-1000:]})
    output = {"platform": platform.platform(), "results": results}
    (ROOT / "results/detector_validation.json").write_text(json.dumps(output, indent=2) + "\n")
    failed = [item for item in results if item["status"] == "failed"]
    for item in results:
        print(item.get("detector"), item.get("subject_id", ""), item["status"])
    if failed: raise SystemExit(f"{len(failed)} detector checks failed")


if __name__ == "__main__":
    main()
