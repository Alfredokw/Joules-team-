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
| `execution_time_seconds` | Build plus runtime duration used by the frozen protocol |
| `total_energy_consumption_joules` | Package-plus-DRAM energy derived from EnergiBridge cumulative RAPL counters, including overflow correction |
| `energy_counter_wrap_count` | Total package and DRAM counter overflows corrected in this execution |
| `package_energy_counter_wrap_count` | Package-energy counter overflows corrected in this execution |
| `dram_energy_counter_wrap_count` | DRAM-energy counter overflows corrected in this execution |
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

RAPL counters are finite cumulative counters. If an EnergiBridge counter value
decreases between consecutive samples, the parser treats the decrease as an
overflow and adds the configured 262,144 J counter range before calculating the
interval energy. The three wrap-count fields preserve an explicit audit trail.

`results/cooldown_events.csv` records the completed two-minute post-warm-up
pause and the 29 completed five-minute between-round pauses. These pauses occur
outside the measurement windows and therefore do not contribute to runtime or
energy metrics.
