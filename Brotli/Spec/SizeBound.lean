import Brotli.Basic
import Brotli.Spec.Basic

/-!
# Brotli Compression Size Bounds

Formal bounds on the size of Brotli-compressed output, derived from RFC 7932
and the reference encoder's `BrotliEncoderMaxCompressedSize` formula.

## Key points

- **Upper bound**: `maxCompressedSize n` is an absolute upper bound on the
  compressed output of any `n`-byte input (at any valid quality).
- **Size monotone is NOT an axiom**: quality does not monotonically determine
  compressed size.  The reference encoder *usually* produces larger output at
  lower quality (less effort), but for certain degenerate inputs the relationship
  can be reversed.  The test suite acknowledges this explicitly.
- **Guaranteed success**: `compress` never throws for valid quality; `compress_ok`
  provides the existential witness.
-/

namespace Brotli.Spec.SizeBound

/-! ## Compressed-size upper bound -/

/-- The maximum possible compressed size for an `n`-byte input, following the
    reference encoder's formula in `BrotliEncoderMaxCompressedSize`.

    The formula handles empty input specially (Brotli always emits ≥ 2 bytes for
    the stream header).  For non-empty input the encoder may need up to 4 extra
    bytes per 16 MB chunk for meta-block headers, plus 6 bytes of fixed overhead.

    ```
    maxCompressedSize 0 = 2
    maxCompressedSize n = n + 6 + 4 * (n / 16777216)    for n ≥ 1
    ``` -/
def maxCompressedSize : Nat → Nat
  | 0 => 2
  | n => n + 6 + 4 * (n / 16777216)

/-- The bound is always at least 2 (accounting for the stream header). -/
theorem maxCompressedSize_pos (n : Nat) : 0 < maxCompressedSize n := by
  unfold maxCompressedSize; split <;> omega

/-- `maxCompressedSize` is monotone: larger inputs have a larger bound. -/
theorem maxCompressedSize_mono {m n : Nat} (h : m ≤ n) :
    maxCompressedSize m ≤ maxCompressedSize n := by
  have hdiv : m / 16777216 ≤ n / 16777216 := Nat.div_le_div_right h
  cases m <;> cases n <;> simp [maxCompressedSize] <;> omega

/-- For small inputs (< 16 MB) the overhead is exactly 6 bytes. -/
theorem maxCompressedSize_small {n : Nat} (hn : 0 < n) (hsmall : n < 16777216) :
    maxCompressedSize n = n + 6 := by
  have hd : n / 16777216 = 0 := Nat.div_eq_zero_iff.mpr (Or.inr hsmall)
  unfold maxCompressedSize
  split <;> omega

/-! ## Success axiom -/

/-- **Compress-succeeds axiom**: for any valid quality, `Brotli.compress` always
    returns a `ByteArray` (never throws an `IO.Error`).

    This formalises the contract that the C encoder only fails on out-of-memory
    conditions, which we treat as fatal (unmeasured) events outside our model. -/
axiom compress_ok (data : ByteArray) (q : UInt8) (hq : ValidQuality q) :
    ∃ c : ByteArray, Brotli.compress data q = pure c

/-! ## Size bound axiom -/

/-- **Output-size axiom**: the `ByteArray` returned by `Brotli.compress` never
    exceeds `maxCompressedSize data.size` bytes.

    Formally: IF compression returns `c` (which is always, by `compress_ok`),
    THEN `c.size ≤ maxCompressedSize data.size`. -/
axiom compress_size_le (data : ByteArray) (q : UInt8) (hq : ValidQuality q)
    (c : ByteArray) (hc : Brotli.compress data q = pure c) :
    c.size ≤ maxCompressedSize data.size

/-! ## Derived theorems -/

/-- The compressed size bound holds for the *default* quality (11). -/
theorem compress_size_le_default (data : ByteArray) (c : ByteArray)
    (hc : Brotli.compress data = pure c) :
    c.size ≤ maxCompressedSize data.size :=
  compress_size_le data 11 (by decide) c hc

/-- Compressing empty data produces at most 2 bytes. -/
theorem compress_empty_size_le (q : UInt8) (hq : ValidQuality q)
    (c : ByteArray) (hc : Brotli.compress ByteArray.empty q = pure c) :
    c.size ≤ 2 :=
  compress_size_le ByteArray.empty q hq c hc

/-- Given `compress_ok`, we can always extract a concrete result. -/
theorem compress_result (data : ByteArray) (q : UInt8) (hq : ValidQuality q) :
    ∃ c : ByteArray, Brotli.compress data q = pure c ∧
      c.size ≤ maxCompressedSize data.size := by
  obtain ⟨c, hc⟩ := compress_ok data q hq
  exact ⟨c, hc, compress_size_le data q hq c hc⟩

-- Quality size monotone is NOT a theorem: higher quality typically yields
-- smaller compressed output, but this is not guaranteed for all inputs.
-- (BrotliTest.Roundtrip handles this case with a non-fatal warning.)
-- Use `compress_size_le` for quality-independent size bounds.

/-- Both quality extremes (0 and 11) satisfy the same upper bound. -/
theorem compress_both_extremes_bound (data : ByteArray)
    (c0 : ByteArray) (hc0 : Brotli.compress data 0 = pure c0)
    (c11 : ByteArray) (hc11 : Brotli.compress data 11 = pure c11) :
    c0.size ≤ maxCompressedSize data.size ∧
    c11.size ≤ maxCompressedSize data.size :=
  ⟨compress_size_le data 0 (by decide) c0 hc0,
   compress_size_le data 11 (by decide) c11 hc11⟩

end Brotli.Spec.SizeBound
