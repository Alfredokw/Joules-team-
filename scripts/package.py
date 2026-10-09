#!/usr/bin/env python3
"""Create a clean, checksummed replication ZIP."""

from __future__ import annotations

import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT.parent / "Joules-team-linux-workload-precheck-full.zip"
EXCLUDED_PARTS = {"bin", "build", ".build", "__pycache__", "runs", "preflight-artifacts"}
ALLOWED_RESULTS = {
    "results/README.md",
    "results/schedule.csv",
    "results/round_seeds.json",
}


def included(path):
    if not path.is_file():
        return False
    relative = path.relative_to(ROOT)
    name = relative.as_posix()
    if any(part in EXCLUDED_PARTS for part in relative.parts):
        return False
    if name.startswith("results/") and name not in ALLOWED_RESULTS:
        return False
    if name.startswith("calibration/results/"):
        return False
    return name != "CHECKSUMS.sha256"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    files = [path for path in sorted(ROOT.rglob("*")) if included(path)]
    checksums = "".join(
        f"{sha256(path)}  {path.relative_to(ROOT).as_posix()}\n" for path in files
    )
    (ROOT / "CHECKSUMS.sha256").write_text(checksums, encoding="utf-8")
    files.append(ROOT / "CHECKSUMS.sha256")
    if TARGET.exists():
        TARGET.unlink()
    with zipfile.ZipFile(TARGET, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            archive.write(path, Path(ROOT.name) / path.relative_to(ROOT))
    digest = sha256(TARGET)
    TARGET.with_suffix(TARGET.suffix + ".sha256").write_text(
        f"{digest}  {TARGET.name}\n", encoding="utf-8"
    )
    print(f"created {TARGET}\nsha256 {digest}")


if __name__ == "__main__":
    main()
