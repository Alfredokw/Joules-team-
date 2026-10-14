# Running the campaign

Generate the frozen schedule without executing anything:

```sh
python3 scripts/generate_schedule.py
```

The schedule must contain 240 warm-ups and 7,200 measured rows. Run the full
campaign only after preflight and validation have passed:

```sh
python3 scripts/run_experiment.py
```

Each condition is compiled and executed inside the same measurement window, so
compilation contributes to both elapsed time and energy.

The runner keeps the existing one-second Juliet and two-second application
cooldowns after every execution. It then waits an additional 120 seconds after
all warm-ups and 300 seconds between consecutive measured rounds. Completed
long pauses are logged to `results/cooldown_events.csv`.

Resume safely after an interruption:

```sh
python3 scripts/run_experiment.py --resume
```

On resume, a completed long pause is not repeated. If interruption occurs
during a long pause, the entire pause is conservatively restarted.

Useful diagnostic subsets write to a separate results directory. For example:

```sh
python3 scripts/run_experiment.py \
  --repetitions 1 --no-warmup --no-cooldown \
  --subject bst_oob --workload small --configuration baseline \
  --results-root results/smoke
```

Round ranges can be run separately with `--start-round` and `--end-round`, but
never run two ranges concurrently on the same host. Use the same package and
default results directory for every part of the measured campaign.

After completion:

```sh
make finalize
```

Raw measurements remain authoritative. The processed CSV only adds overhead
factors to valid Baseline/sanitizer pairs. In a new package, `results/raw/`,
`results/runs/`, and `results/processed/` contain no experiment output yet:
the runner creates and populates the first two during execution, and
`make finalize` creates the processed CSV after all runs are present.
