# Linux workload compatibility precheck

Run this precheck on the final Linux measurement server before starting the
measured experiment. It uses the benchmark sources, `manifest.csv`, compiler
flags, runtime environments, thread count, and input seed already defined by
the repository. No benchmark source is duplicated in this directory.

The four representatives are `bst_oob`, `hash_oob`, `matrix_oob`, and
`juliet_oob_heap_loop`. Their frozen values are read from the manifest:

| Implementation | Small | Large |
|---|---:|---:|
| BST | 10,000 | 120,000 |
| Hash Table | 50,000 | 300,000 |
| Parallel Matrix Multiplication | 128 | 608 |
| Juliet | 1,000,000 | 26,000,000 |

Baseline, ASan, MSan, TSan, and Memcheck are checked. Compilation occurs before
timing. For each implementation, configuration, and size, the script discards
one warm-up and measures five executions using `time.perf_counter()`.

The precheck also compares the `n` printed by each program with the value read
from the manifest. It passes only when every measured execution reaches
`WORKLOAD_COMPLETE`, every printed input matches the manifest, Large is slower
than Small under all configurations, and every ASan Large/Small median ratio is
at least 2.0.

From the repository root:

```sh
make workload-precheck
```

The 240 pilot executions are written to a timestamped directory under
`calibration/results/`. They are separate from the 7,200 measured executions.
Proceed only when `workload_precheck_summary.json` contains:

```json
{
  "passed": true,
  "official_server_precheck": true
}
```

Preserve the CSV, summary, environment record, build record, and logs with the
replication archive. The full precheck intentionally refuses to run outside
Linux. A read-only plan can be inspected with:

```sh
python3 calibration/verify_workload_sizes.py --dry-run
```
