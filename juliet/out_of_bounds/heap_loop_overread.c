#include "../juliet_driver.h"

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE126_Buffer_Overread__malloc_char_loop_01.c.
 * CWE-126, heap buffer over-read through a loop.
 * Change for scalability: execute a configurable workload first, then trigger
 * the original error class once. Expected detectors: ASan and Memcheck.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    (void)cfg;
    char *source = xmalloc(10);
    for (size_t i = 0; i < 10; ++i) source[i] = (char)i;
    volatile size_t limit = 11;
    for (size_t i = 0; i < limit; ++i) observable_sink ^= (unsigned char)source[i];
    free(source);
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_oob_heap_loop", trigger); }
