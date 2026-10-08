#ifndef SEB_BENCH_H
#define SEB_BENCH_H

#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__GNUC__) || defined(__clang__)
#define NOINLINE __attribute__((noinline))
#else
#define NOINLINE
#endif

typedef struct {
    const char *size_name;
    size_t n;
    int threads;
    uint64_t seed;
} bench_config;

static volatile uint64_t observable_sink;

static void die(const char *message)
{
    fprintf(stderr, "error: %s\n", message);
    exit(EXIT_FAILURE);
}

static void *xmalloc(size_t size)
{
    void *p = malloc(size);
    if (p == NULL) {
        die("allocation failed");
    }
    return p;
}

static uint64_t mix64(uint64_t x)
{
    x += UINT64_C(0x9e3779b97f4a7c15);
    x = (x ^ (x >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    x = (x ^ (x >> 27)) * UINT64_C(0x94d049bb133111eb);
    return x ^ (x >> 31);
}

static size_t parse_size_value(const char *text)
{
    char *end = NULL;
    errno = 0;
    unsigned long long value = strtoull(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || value == 0 || value > SIZE_MAX) {
        die("invalid numeric argument");
    }
    return (size_t)value;
}

static bench_config parse_config(int argc, char **argv, size_t small_n, size_t large_n)
{
    bench_config cfg = {"small", small_n, 4, UINT64_C(20261002)};
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--size") == 0 && i + 1 < argc) {
            cfg.size_name = argv[++i];
            if (strcmp(cfg.size_name, "small") == 0) {
                cfg.n = small_n;
            } else if (strcmp(cfg.size_name, "large") == 0) {
                cfg.n = large_n;
            } else {
                die("--size must be small or large");
            }
        } else if (strcmp(argv[i], "--n") == 0 && i + 1 < argc) {
            cfg.n = parse_size_value(argv[++i]);
            cfg.size_name = "custom";
        } else if (strcmp(argv[i], "--threads") == 0 && i + 1 < argc) {
            cfg.threads = (int)parse_size_value(argv[++i]);
            if (cfg.threads > 64) {
                die("--threads must not exceed 64");
            }
        } else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) {
            cfg.seed = (uint64_t)parse_size_value(argv[++i]);
        } else if (strcmp(argv[i], "--help") == 0) {
            puts("Options: --size small|large [--n N] [--threads N] [--seed N]");
            exit(EXIT_SUCCESS);
        } else {
            die("unknown or incomplete argument; use --help");
        }
    }
    return cfg;
}

static void report_workload(const char *program, const char *variant,
                            const bench_config *cfg, uint64_t checksum)
{
    printf("WORKLOAD_COMPLETE program=%s variant=%s size=%s n=%zu threads=%d "
           "seed=%" PRIu64 " checksum=%" PRIu64 "\n",
           program, variant, cfg->size_name, cfg->n, cfg->threads,
           cfg->seed, checksum);
    fflush(stdout);
    observable_sink ^= checksum;
}

#endif
