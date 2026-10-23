# Results directory

`schedule.csv` and `round_seeds.json` are frozen inputs. The runner creates:

* `raw/executions.csv` — 7,200 measured executions;
* `raw/warmups.csv` — 240 discarded warm-ups;
* `raw/energibridge/` and `raw/turbostat/` — interval measurements;
* `runs/` — compiler/runtime logs and per-run metadata;
* `processed/` — paired overhead factors;
* `preflight.json` — measurement-host and tool validation.

Back up the entire directory without editing the raw files.
