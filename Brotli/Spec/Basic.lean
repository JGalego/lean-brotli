import Brotli.Basic

/-!
# Brotli Core Specification (RFC 7932)

Formal axioms capturing the essential guarantees of the Brotli
`compress`/`decompress` FFI bindings, and theorems that follow from them.

**Design**: The FFI functions are opaque; we cannot inspect the C implementation.
Instead we axiomatise the properties that *any correct* Brotli implementation
must satisfy (per RFC 7932), then prove general theorems from these axioms alone.

The four central properties formalised here are:

1. **Roundtrip** — `decompress (compress data q) = data` for every valid quality.
2. **Quality invariance** — all valid quality levels produce the same *decoded* data.
3. **Empty input** — compressing/decompressing an empty `ByteArray` returns empty.
4. **Universal quality quantification** — the roundtrip holds for all twelve levels.
-/

namespace Brotli.Spec

/-! ## Quality validity -/

/-- A Brotli quality level is valid iff it belongs to the closed interval [0, 11].
    Values ≥ 12 are rejected by the C encoder. -/
def ValidQuality (q : UInt8) : Prop := q.toNat ≤ 11

/-- `ValidQuality` is decidable (needed for `decide` and `if`-expressions). -/
instance (q : UInt8) : Decidable (ValidQuality q) :=
  inferInstanceAs (Decidable (q.toNat ≤ 11))

/-- `ValidQuality` unfolds to a `Nat` comparison, useful for `omega`. -/
theorem validQuality_iff (q : UInt8) : ValidQuality q ↔ q.toNat ≤ 11 := Iff.rfl

/-- Every concrete quality literal in [0, 11] is valid.  Covers all twelve
    levels in a single `@[simp]` lemma instead of twelve separate declarations. -/
@[simp] theorem validQuality_le {q : UInt8} (h : q.toNat ≤ 11 := by omega) :
    ValidQuality q := h

theorem not_validQuality_of_gt {q : UInt8} (h : 11 < q.toNat) : ¬ ValidQuality q :=
  fun hq => absurd (validQuality_iff q |>.mp hq) (by omega)

/-! ## Core axioms -/

/-- **Roundtrip axiom** (RFC 7932 §5): IF compressing `data` at a valid quality
    succeeds with result `c`, THEN decompressing `c` succeeds and returns `data`.

    This conditional formulation is safer than equating `IO` actions directly:
    it does not assume `compress` can never throw, keeping the axiom consistent
    even if the C encoder encounters an OOM or allocator error.  Combine with
    `SizeBound.compress_ok` when you need the unconditional form. -/
axiom roundtrip (data : ByteArray) (q : UInt8) (hq : ValidQuality q)
    (c : ByteArray) (hc : Brotli.compress data q = pure c) :
    Brotli.decompress c = pure data

/-! ## Derived theorems -/

/-- Roundtrip at the **default quality** (11). -/
theorem roundtrip_default (data : ByteArray)
    (c : ByteArray) (hc : Brotli.compress data = pure c) :
    Brotli.decompress c = pure data :=
  roundtrip data 11 (by simp) c hc

/-- **Empty-input roundtrip**: compressing then decompressing an empty
    `ByteArray` always yields an empty `ByteArray`. -/
theorem roundtrip_empty (q : UInt8) (hq : ValidQuality q)
    (c : ByteArray) (hc : Brotli.compress ByteArray.empty q = pure c) :
    Brotli.decompress c = pure ByteArray.empty :=
  roundtrip ByteArray.empty q hq c hc

/-- **Quality invariance**: for any two valid quality levels `q₁` and `q₂`,
    IF compression succeeds with both, decompressing either result returns `data`.

    Brotli quality only affects *compressed size* and *throughput*, never the
    decompressed content. -/
theorem quality_invariant (data : ByteArray) (q₁ q₂ : UInt8)
    (hq₁ : ValidQuality q₁) (hq₂ : ValidQuality q₂)
    (c₁ : ByteArray) (hc₁ : Brotli.compress data q₁ = pure c₁)
    (c₂ : ByteArray) (hc₂ : Brotli.compress data q₂ = pure c₂) :
    Brotli.decompress c₁ = Brotli.decompress c₂ := by
  rw [roundtrip data q₁ hq₁ c₁ hc₁, roundtrip data q₂ hq₂ c₂ hc₂]

/-- **Universal roundtrip**: the roundtrip property holds for every valid quality,
    given a successful compression. -/
theorem all_qualities_roundtrip (data : ByteArray) :
    ∀ q : UInt8, ValidQuality q →
      ∀ c : ByteArray, Brotli.compress data q = pure c →
        Brotli.decompress c = pure data :=
  fun q hq c hc => roundtrip data q hq c hc

/-- All twelve Brotli quality levels (0 through 11) are valid. -/
theorem all_qualities_valid : ∀ q : Fin 12, ValidQuality q.val.toUInt8 :=
  fun q => by simp [ValidQuality]; omega

end Brotli.Spec
