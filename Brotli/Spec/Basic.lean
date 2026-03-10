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

@[simp] theorem validQuality_zero  : ValidQuality 0  := by decide
@[simp] theorem validQuality_one   : ValidQuality 1  := by decide
@[simp] theorem validQuality_two   : ValidQuality 2  := by decide
@[simp] theorem validQuality_three : ValidQuality 3  := by decide
@[simp] theorem validQuality_four  : ValidQuality 4  := by decide
@[simp] theorem validQuality_five  : ValidQuality 5  := by decide
@[simp] theorem validQuality_six   : ValidQuality 6  := by decide
@[simp] theorem validQuality_seven : ValidQuality 7  := by decide
@[simp] theorem validQuality_eight : ValidQuality 8  := by decide
@[simp] theorem validQuality_nine  : ValidQuality 9  := by decide
@[simp] theorem validQuality_ten   : ValidQuality 10 := by decide
@[simp] theorem validQuality_eleven: ValidQuality 11 := by decide

theorem not_validQuality_twelve : ¬ ValidQuality 12 := by decide
theorem not_validQuality_of_gt {q : UInt8} (h : 11 < q.toNat) : ¬ ValidQuality q :=
  fun hq => absurd (validQuality_iff q |>.mp hq) (by omega)

/-! ## Core axioms -/

/-- **Roundtrip axiom** (RFC 7932 §5): Compressing `data` at any valid quality
    and decompressing the result recovers exactly `data`.

    Formally: the composite `IO` action `compress data q >>= decompress`
    is propositionally equal to `pure data`, i.e. it *always* returns `data`
    without performing any visible side effects beyond the internal allocation. -/
axiom roundtrip (data : ByteArray) (q : UInt8) (hq : ValidQuality q) :
    (Brotli.compress data q >>= Brotli.decompress) = pure data

/-! ## Derived theorems -/

/-- Roundtrip at the **default quality** (11).
    Uses the implicit default argument of `Brotli.compress`. -/
theorem roundtrip_default (data : ByteArray) :
    (Brotli.compress data >>= Brotli.decompress) = pure data :=
  roundtrip data 11 (by decide)

/-- **Empty-input roundtrip**: compressing then decompressing an empty
    `ByteArray` always yields an empty `ByteArray`. -/
theorem roundtrip_empty (q : UInt8) (hq : ValidQuality q) :
    (Brotli.compress ByteArray.empty q >>= Brotli.decompress) =
    pure ByteArray.empty :=
  roundtrip ByteArray.empty q hq

/-- Empty-input roundtrip at the default quality. -/
theorem roundtrip_empty_default :
    (Brotli.compress ByteArray.empty >>= Brotli.decompress) =
    pure ByteArray.empty :=
  roundtrip_default ByteArray.empty

/-- **Quality invariance**: for any two valid quality levels `q₁` and `q₂`,
    decompressing the output of compression at either level returns the same data.

    This is the formal statement that Brotli quality only affects *compressed size*
    and *throughput*, never the decompressed content. -/
theorem quality_invariant (data : ByteArray) (q₁ q₂ : UInt8)
    (hq₁ : ValidQuality q₁) (hq₂ : ValidQuality q₂) :
    (Brotli.compress data q₁ >>= Brotli.decompress) =
    (Brotli.compress data q₂ >>= Brotli.decompress) := by
  rw [roundtrip data q₁ hq₁, roundtrip data q₂ hq₂]

/-- Any valid quality roundtrip has the same result as the default quality. -/
theorem quality_eq_default (data : ByteArray) (q : UInt8) (hq : ValidQuality q) :
    (Brotli.compress data q >>= Brotli.decompress) =
    (Brotli.compress data >>= Brotli.decompress) :=
  quality_invariant data q 11 hq (by decide)

/-- **Universal roundtrip**: the roundtrip property holds for every valid quality. -/
theorem all_qualities_roundtrip (data : ByteArray) :
    ∀ q : UInt8, ValidQuality q →
      (Brotli.compress data q >>= Brotli.decompress) = pure data :=
  fun q hq => roundtrip data q hq

/-- All twelve quality levels (0 through 11) are valid. -/
theorem twelve_valid_qualities :
    ∀ n ∈ List.range 12, ValidQuality n.toUInt8 := by
  decide

end Brotli.Spec
