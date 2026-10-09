# Frozen experiment protocol

1. Reserve the Ubuntu measurement host and stop unrelated user workloads.
2. Run `scripts/preflight.py` and preserve `results/preflight.json`.
3. Run baseline completion validation and detector validation.
4. Run `make workload-precheck` and preserve its timestamped output. Do not
   begin measured executions unless every frozen Small/Large pair passes.
5. Freeze the package, compiler/tool versions, flags, workload values, four
   worker threads, input seed, sampling intervals, timeouts, and cooldowns.
6. Generate and preserve the complete schedule. It contains 240 discarded
   warm-ups followed by 30 measured rounds of 240 conditions each.
7. Use the distinct predefined seed stored for each measured round.
8. For every scheduled condition, compile and then execute within the same
   EnergiBridge/Turbostat measurement window (`build_and_run`). Memcheck compiles
   the Baseline form and executes it through Valgrind.
9. Execute only one scheduled condition at a time.
10. Apply a one-second Juliet cooldown or two-second application cooldown after
   every execution, including warm-ups.
11. Retain raw EnergiBridge and Turbostat data, compiler/runtime logs,
    completion markers, detector outcomes, and invalid runs.
12. Resume an interrupted campaign with `--resume`; never duplicate or silently
    replace completed run identifiers.
13. Calculate overhead only from valid sanitizer/Baseline pairs belonging to
    the same Program Variant, Workload Size, and repetition round.

The 24 Program Variants are the experimental blocks. Sanitizer Configuration
and Workload Size are the two manipulated factors. Memory-error family is
retained as a comparison category for RQ4.
