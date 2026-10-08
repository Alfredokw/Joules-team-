# Build configuration

The frozen compiler is Clang/LLVM. Common flags are:

```text
-std=c11 -O1 -g -Wall -Wextra -Wpedantic
-fno-omit-frame-pointer -fno-strict-aliasing -pthread
```

Sanitizer-specific flags and runtime variables are stored in
`configs/detectors.json`. Memcheck uses the uninstrumented Baseline build.

The final protocol measures compilation followed by execution for every
scheduled condition. `scripts/build.py` exists only for preflight, detector
validation, and execution-only diagnostics; its prebuilt binaries are not used
by the default measured campaign.

```sh
python3 scripts/build.py --configuration all --keep-going
```

MSan is validated only on the Ubuntu x86-64 measurement host. All build
commands and return codes are preserved in the corresponding run records.
