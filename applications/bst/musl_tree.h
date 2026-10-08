#ifndef SEB_MUSL_TREE_H
#define SEB_MUSL_TREE_H

/*
 * Standalone adaptation of musl libc's AVL-backed tsearch implementation.
 * Upstream commit and MIT license are recorded under provenance/.
 */
void *bench_tsearch(const void *key, void **rootp,
                    int (*cmp)(const void *, const void *));
void *bench_tfind(const void *key, void *const *rootp,
                  int (*cmp)(const void *, const void *));
void bench_tdestroy(void *root, void (*free_key)(void *));

#endif
