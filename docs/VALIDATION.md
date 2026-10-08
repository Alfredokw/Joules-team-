# Required validation on the measurement server

Development-host results are not accepted as final validation. Before starting
the measured campaign on Ubuntu, complete all of the following:

```sh
make static-check
make preflight
python3 scripts/validate.py --repeats 3
make validate-detectors
make smoke
```

The checks establish that:

* the manifest contains 24 balanced Program Variants and the frozen sizes;
* the host, compiler, Valgrind, EnergiBridge, Turbostat, MSR/RAPL access, and
  sampling interfaces are available;
* every Baseline subject completes both Small and Large workloads repeatedly;
* all Baseline, ASan, MSan, and TSan binaries compile on the final host;
* each primary detector reports the injected error after the common workload;
* a complete instrumented measurement row can be produced.

Inspect `results/preflight.json`, `results/validation.json`,
`results/detector_validation.json`, and `results/smoke/` manually. Do not start
the campaign if a required check fails. Preserve failures instead of changing
the source or flags during data collection.
