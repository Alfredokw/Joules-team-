#ifndef SEB_BST_CORE_H
#define SEB_BST_CORE_H

#include "musl_tree.h"

static int compare_u64(const void *left, const void *right)
{
    uint64_t a = *(const uint64_t *)left;
    uint64_t b = *(const uint64_t *)right;
    return (a > b) - (a < b);
}

typedef struct {
    void *root;
    uint64_t *queries;
    size_t begin;
    size_t end;
    uint64_t hits;
} bst_worker_args;

static void *bst_worker(void *opaque)
{
    bst_worker_args *args = opaque;
    uint64_t hits = 0;
    for (size_t i = args->begin; i < args->end; ++i) {
        hits += bench_tfind(&args->queries[i], &args->root, compare_u64) != NULL;
    }
    args->hits = hits;
    return NULL;
}

static int run_bst(int argc, char **argv, const char *variant,
                   void (*inject)(const bench_config *, uint64_t *, size_t))
{
    bench_config cfg = parse_config(argc, argv, 10000, 120000);
    void *root = NULL;
    for (size_t i = 0; i < cfg.n; ++i) {
        uint64_t *key = xmalloc(sizeof(*key));
        *key = mix64(cfg.seed + i + 1);
        if (bench_tsearch(key, &root, compare_u64) == NULL) die("tree insertion failed");
    }
    size_t query_count = cfg.n * 5;
    uint64_t *queries = xmalloc(query_count * sizeof(*queries));
    for (size_t i = 0; i < query_count; ++i) {
        queries[i] = (i & 1U) ? mix64(cfg.seed + (i % cfg.n) + 1)
                              : mix64(cfg.seed + cfg.n + i + 1);
    }
    int threads = cfg.threads;
    pthread_t *ids = xmalloc((size_t)threads * sizeof(*ids));
    bst_worker_args *args = xmalloc((size_t)threads * sizeof(*args));
    for (int t = 0; t < threads; ++t) {
        args[t] = (bst_worker_args){root, queries,
            query_count * (size_t)t / (size_t)threads,
            query_count * (size_t)(t + 1) / (size_t)threads, 0};
        if (pthread_create(&ids[t], NULL, bst_worker, &args[t]) != 0) die("pthread_create failed");
    }
    uint64_t checksum = 0;
    for (int t = 0; t < threads; ++t) {
        pthread_join(ids[t], NULL);
        checksum += args[t].hits;
    }
    report_workload("bst", variant, &cfg, checksum);
    inject(&cfg, queries, query_count);
    free(args);
    free(ids);
    free(queries);
    bench_tdestroy(root, free);
    return 0;
}

#endif
