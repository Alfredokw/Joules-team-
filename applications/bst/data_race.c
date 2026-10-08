#include "../../common/bench.h"
#include "bst_core.h"

static uint64_t successful_searches;
typedef struct { size_t iterations; } race_arg;

static void *race_worker(void *opaque)
{
    race_arg *arg = opaque;
    for (size_t i = 0; i < arg->iterations; ++i) successful_searches++;
    return NULL;
}

/* INJECTED ERROR
 * Family: Data race. CWE-366.
 * Change: two threads update a global search counter without synchronization.
 * Expected detector: TSan.
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    (void)queries;
    (void)count;
    race_arg arg = {cfg->n < 10000 ? 10000 : cfg->n};
    pthread_t a, b;
    pthread_create(&a, NULL, race_worker, &arg);
    pthread_create(&b, NULL, race_worker, &arg);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    observable_sink ^= successful_searches;
}

int main(int argc, char **argv) { return run_bst(argc, argv, "data_race", inject); }
