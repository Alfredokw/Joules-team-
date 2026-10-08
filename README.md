# Final Linux sanitizer-energy experiment

This is the server replication package for the experiment described in the
Green Lab report. It is not the macOS calibration package.

## Frozen design

* Server: Ubuntu 24.04, two Intel Xeon Silver 4208 packages, approximately
  384 GiB RAM.
* Blocks: 24 faulty Program Variants (12 Juliet-derived and 12 application
  variants).
* Factors: five Sanitizer Configurations and two Workload Sizes.
* Configurations: Baseline, ASan, MSan, TSan, and Valgrind Memcheck.
* One discarded warm-up for each of the 240 block-treatment combinations.
* Thirty randomized measured rounds, using a distinct predefined seed in each
  round: 7,200 measured executions.
* Four worker threads where the workload implementation uses threads.
* Cooldown after every run: one second for Juliet and two seconds for the
  application variants.

| Workload implementation | Small | Large |
|---|---:|---:|
| BST | 10,000 | 120,000 |
| Hash Table | 50,000 | 300,000 |
| Parallel Matrix Multiplication | 128 | 608 |
| Juliet | 1,000,000 | 26,000,000 |

The default `measurement_scope` is `build_and_run`, matching the supplied
paper: every scheduled condition compiles the selected configuration and then
executes it inside the same EnergiBridge/Turbostat measurement window. The
runner also records build time and runtime separately. Do not change this
setting after beginning the measured campaign.

## Metrics

The runner retains the raw EnergiBridge CSV and Turbostat interval log for every
run and records:

* total energy consumption in Joules;
* build, runtime, and complete build-and-run time in seconds;
* average power, highest interval-average power, and power variability in Watts;
* peak resident memory in bytes for the executed workload/tool process;
* termination status, workload-completion marker, and detection outcome;
* complete compiler and runtime commands.

Only runs containing `WORKLOAD_COMPLETE` are eligible for overhead analysis.
The injected error is triggered after the common useful workload so that a
sanitizer report cannot shorten that workload.

## Server workflow

Read `docs/SERVER_SETUP.md` first. Then, from the package directory:

```sh
make static-check
make preflight
python3 scripts/validate.py --repeats 3
make validate-detectors
make schedule
make smoke
make run
make audit
make process
```

If the campaign is interrupted, do not restart it from zero:

```sh
make resume
```

The runner appends and flushes one result row after every execution. Raw results
are stored under `results/raw/`, per-run logs under `results/runs/`, and paired
overhead factors under `results/processed/`.

## Important rules

1. Run only one copy of the experiment at a time on an otherwise reserved host.
2. Do not change source, flags, sizes, thread count, seeds, sampling intervals,
   or tool versions during the campaign.
3. Preserve invalid runs and their logs; never replace them silently.
4. Do not mix measurements from different hosts or compiler/tool versions.
5. Archive the complete package and `results/` directory after the campaign.

See `docs/EXPERIMENT_PROTOCOL.md`, `docs/RUN.md`,
`docs/DATA_DICTIONARY.md`, and `docs/VALIDATION.md` for details.
