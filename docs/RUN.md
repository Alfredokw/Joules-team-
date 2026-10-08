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

Resume safely after an interruption:

```sh
python3 scripts/run_experiment.py --resume
```

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
python3 scripts/audit_results.py
python3 scripts/process_results.py
```

Raw measurements remain authoritative. The processed CSV only adds overhead
factors to valid Baseline/sanitizer pairs.
