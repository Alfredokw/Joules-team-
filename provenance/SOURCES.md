# Source provenance

All upstream snapshots are included for traceability. They are not additional
experimental subjects.

## Juliet C/C++ Test Suite

* Repository: https://github.com/arichardson/juliet-test-suite-c
* Commit: `f88433e3443648a17671398797a04ea1f8e1a274`
* Use: twelve original bad-case patterns, adapted to add deterministic Small
  and Large workloads and a single controlled post-workload trigger.
* License: `licenses/Juliet-LICENSE.txt`

## musl libc

* Repository: https://git.musl-libc.org/git/musl
* Commit: `9b2d8a1646391d5217f9a358555aebcaab5b8aaf`
* Use: standalone adaptation of the AVL-backed `tsearch` implementation for
  the BST workload.
* License: MIT, `licenses/musl-COPYRIGHT.txt`

## uthash

* Repository: https://github.com/troydhanson/uthash
* Commit: `a49bed0b4abb7dff16c73906dcdc8a9718d582d2`
* Use: official `uthash.h` and example-derived hash operations.
* License: revised BSD, `licenses/uthash-LICENSE.txt`

## PolyBench/C 4.2.1

* Repository: https://github.com/MatthiasJReisinger/PolyBenchC-4.2.1
* Commit: `3e872547cef7e5c9909422ef1e6af03cf4e56072`
* Use: dynamically sized, pthread-parallel adaptation of the GEMM kernel.
* License: Ohio State University Software Distribution License,
  `licenses/PolyBenchC-LICENSE.txt`

## Sanitizer documentation

* AddressSanitizer examples: https://github.com/google/sanitizers/wiki/AddressSanitizer
* MemorySanitizer: https://clang.llvm.org/docs/MemorySanitizer.html
* ThreadSanitizer: https://clang.llvm.org/docs/ThreadSanitizer.html
* Valgrind Memcheck manual: https://valgrind.org/docs/manual/mc-manual.html
