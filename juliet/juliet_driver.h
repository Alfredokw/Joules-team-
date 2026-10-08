#ifndef SEB_JULIET_DRIVER_H
#define SEB_JULIET_DRIVER_H

#include "../common/bench.h"

typedef void (*juliet_trigger)(const bench_config *cfg);

static int run_juliet_case(int argc, char **argv, const char *case_id,
                           juliet_trigger trigger)
{
    bench_config cfg = parse_config(argc, argv, 1000000, 26000000);
    uint64_t *values = xmalloc(cfg.n * sizeof(*values));
    for (size_t i = 0; i < cfg.n; ++i) values[i] = mix64(cfg.seed + i);
    uint64_t checksum = 0;
    for (size_t pass = 0; pass < 4; ++pass) {
        for (size_t i = 0; i < cfg.n; ++i) {
            values[i] = mix64(values[i] + pass);
            checksum ^= values[i];
        }
    }
    report_workload(case_id, "faulty", &cfg, checksum);
    trigger(&cfg);
    free(values);
    return 0;
}

#endif
