import Brotli.Spec.Basic
import Brotli.Spec.Streaming
import Brotli.Spec.SizeBound

/-!
# Brotli Formal Specification

This module collects all formal axioms and theorems about the Brotli
compression library (`lean-brotli`), mirroring the approach used in `lean-zip`.

## Modules

- `Brotli.Spec.Basic` — Core roundtrip axiom, quality validity, and derived
  theorems (quality invariance, empty-input roundtrip, universal quantification).
- `Brotli.Spec.Streaming` — Streaming ↔ batch equivalence axioms and the
  streaming roundtrip theorem.
- `Brotli.Spec.SizeBound` — Compressed-size upper bound, success axiom, and
  why quality monotone is NOT a theorem.

## Design philosophy

The FFI functions (`Brotli.compress`, `Brotli.decompress`, and the streaming
variants) are opaque Lean declarations backed by C code.  We cannot inspect
the implementation, so we **axiomatise** the properties that any correct
Brotli implementation must satisfy per RFC 7932, then prove derived theorems
from those axioms alone.

This means:
- Axioms require external validation (tests, fuzzing, or reading the C source).
- Theorems above the axioms are fully machine-checked by Lean's kernel.
- Zero `sorry` in derived theorems — proofs are complete.
-/
