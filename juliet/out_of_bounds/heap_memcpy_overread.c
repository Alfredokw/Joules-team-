#include "../juliet_driver.h"

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE126_Buffer_Overread__malloc_char_memcpy_01.c.
 * CWE-126, heap buffer over-read through memcpy.
 * Change for scalability: configurable workload plus one controlled trigger.
 * Expected detectors: ASan and Memcheck.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    (void)cfg;
    char *source = xmalloc(10);
    memset(source, 'A', 10);
    char destination[11];
    volatile size_t bytes = 11;
    memcpy(destination, source, bytes);
    observable_sink ^= (unsigned char)destination[0];
    free(source);
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_oob_heap_memcpy", trigger); }
