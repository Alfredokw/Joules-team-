# Results directory

`schedule.csv` and `round_seeds.json` are frozen inputs. During the campaign,
the runner creates:

* `raw/executions.csv` — 7,200 measured executions;
* `raw/warmups.csv` — 240 discarded warm-ups;
* `raw/energibridge/` and `raw/turbostat/` — interval measurements;
* `runs/` — compiler/runtime logs and per-run metadata;
* `preflight.json` — measurement-host and tool validation.
* `cooldown_events.csv` — one completed post-warm-up pause and 29 completed
  between-round pauses.

After the campaign, `make finalize` checks completeness and creates
`processed/executions_with_overheads.csv`. The raw, run-log, and processed
directories are intentionally not populated in a clean replication package.

Back up the entire directory without editing the raw files.
