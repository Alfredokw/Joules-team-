# Error mapping

The authoritative machine-readable mapping is `manifest.csv`. The design is
balanced: each family contains three Juliet cases and three derived variants.

| Family | Juliet mechanisms | Derived mapping | Expected primary tools |
|---|---|---|---|
| Out-of-bounds | heap loop over-read; heap memcpy over-read; stack loop over-read | BST heap read; hash memcpy read; matrix stack read | ASan; Memcheck for heap cases |
| Lifetime/deallocation | use-after-free; character leak; int64 leak | BST use-after-free; hash entry leak; matrix row leak | ASan or Memcheck |
| Uninitialized memory | uninitialized heap array; partial integer array; partial structure array | BST result; hash entry; matrix partial sum | MSan, Memcheck |
| Data race | global integer; control-flow global; referenced local | BST global counter; hash control counter; matrix referenced checksum | TSan |

“Expected detector” is a testable expectation, not a guarantee across all
toolchains. Final admission requires a report from the expected tool on the
measurement host.
