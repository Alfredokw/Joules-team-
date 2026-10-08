# Data dictionary

The measured master file is `results/raw/executions.csv`; discarded warm-ups
are stored separately in `results/raw/warmups.csv`.

| Field | Meaning |
|---|---|
| `run_id` | Unique immutable execution identifier |
| `phase` | `warmup` or `measured` |
| `repetition`, `order`, `round_seed` | Round, randomized position, and predefined schedule seed |
| `subject_id` | Program Variant/block identifier |
| `workload`, `input_n` | Small/Large label and exact numeric workload |
| `configuration` | Baseline, ASan, MSan, TSan, or Memcheck |
| `build_seconds` | Compiler stage duration |
| `runtime_seconds` | Workload/tool process duration |
| `execution_time_seconds` | Build plus runtime duration used by the frozen paper protocol |
| `total_energy_consumption_joules` | Energy integrated from EnergiBridge system-power samples |
| `average_power_watts` | Total energy divided by the EnergiBridge measurement duration |
| `peak_power_watts` | Highest Turbostat interval-average package-plus-DRAM power |
| `power_variability_watts` | Population standard deviation of those Turbostat power samples |
| `peak_rss_bytes` | Maximum resident set size reported for runtime execution |
| `termination_status` | Completed, nonzero exit, compile failure, timeout, incomplete workload, or measurement failure |
| `workload_complete` | Whether the common useful workload printed its completion marker |
| `detected` | Whether the selected tool emitted a matching diagnostic |
| `valid` | Whether the run completed comparable work and all required measurements succeeded |

EnergiBridge CSVs, Turbostat logs, compiler output, runtime output, and per-run
metadata are retained separately and linked from the master row.
