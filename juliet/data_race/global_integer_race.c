#include "../juliet_driver.h"

static uint64_t shared_global;
typedef struct { size_t iterations; } race_arg;
static void *worker(void *opaque)
{
    race_arg *arg = opaque;
    for (size_t i = 0; i < arg->iterations; ++i) shared_global++;
    return NULL;
}

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE366_Race_Condition_Within_Thread__global_int_01.c.
 * CWE-366, unsynchronized updates to a global integer.
 * Expected detector: TSan.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    race_arg arg = {cfg->n < 10000 ? 10000 : cfg->n};
    pthread_t a, b;
    pthread_create(&a, NULL, worker, &arg);
    pthread_create(&b, NULL, worker, &arg);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    observable_sink ^= shared_global;
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_race_global", trigger); }
