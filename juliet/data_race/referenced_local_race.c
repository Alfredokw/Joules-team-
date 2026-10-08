#include "../juliet_driver.h"

typedef struct { uint64_t *shared; size_t iterations; } race_arg;
static void *worker(void *opaque)
{
    race_arg *arg = opaque;
    for (size_t i = 0; i < arg->iterations; ++i) (*arg->shared)++;
    return NULL;
}

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE366_Race_Condition_Within_Thread__int_byref_01.c.
 * CWE-366, race on a referenced local integer.
 * Expected detector: TSan.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    uint64_t local = 0;
    race_arg arg = {&local, cfg->n < 10000 ? 10000 : cfg->n};
    pthread_t a, b;
    pthread_create(&a, NULL, worker, &arg);
    pthread_create(&b, NULL, worker, &arg);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    observable_sink ^= local;
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_race_byref", trigger); }
