#!/usr/bin/env python3
"""Prebuild binaries for validation or execution-only pilot runs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess

from experimentlib import ROOT, compile_command, load_manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--configuration",
        choices=["all", "baseline", "asan", "msan", "tsan"],
        default="all",
    )
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--keep-going", action="store_true")
    args = parser.parse_args()
    if shutil.which(args.cc) is None:
        raise SystemExit(f"compiler not found: {args.cc}")

    configurations = (
        ["baseline", "asan", "msan", "tsan"]
        if args.configuration == "all"
        else [args.configuration]
    )
    failures = []
    commands = []
    for item in load_manifest():
        for configuration in configurations:
            out_dir = ROOT / "bin" / item["id"]
            out_dir.mkdir(parents=True, exist_ok=True)
            output = out_dir / configuration
            command = compile_command(item, configuration, output, args.cc)
            result = subprocess.run(command, text=True, capture_output=True, check=False)
            commands.append(
                {
                    "subject_id": item["id"],
                    "configuration": configuration,
                    "command": command,
                    "return_code": result.returncode,
                }
            )
            if result.returncode != 0:
                failures.append(
                    {
                        "subject_id": item["id"],
                        "configuration": configuration,
                        "error": result.stderr,
                    }
                )
                print(f"FAILED {item['id']} {configuration}")
                if not args.keep_going:
                    break
            else:
                print(f"built {item['id']} {configuration}")
        if failures and not args.keep_going:
            break

    compiler_version = subprocess.run(
        [args.cc, "--version"], text=True, capture_output=True, check=False
    ).stdout
    record = {
        "compiler": args.cc,
        "compiler_version": compiler_version.splitlines()[0] if compiler_version else "unknown",
        "platform": platform.platform(),
        "manifest_sha256": hashlib.sha256((ROOT / "manifest.csv").read_bytes()).hexdigest(),
        "commands": commands,
        "failures": failures,
    }
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "build/build_record.json").write_text(
        json.dumps(record, indent=2) + "\n", encoding="utf-8"
    )
    if failures:
        raise SystemExit(f"{len(failures)} builds failed; see build/build_record.json")


if __name__ == "__main__":
    main()
