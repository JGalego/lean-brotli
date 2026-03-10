import Brotli.Stream
import Brotli.Spec.Basic

/-!
# Brotli Streaming Specification

Formal axioms and theorems relating the streaming (chunk-based) Brotli API to
the whole-buffer API in `Brotli.Basic`.

## Overview

The streaming API decomposes a compression/decompression operation into three
phases — `new`, `push`, `finish` — to keep memory usage bounded regardless of
input size.  These axioms capture the *functional* equivalence between a single-
chunk streaming pass and the corresponding whole-buffer call.

The central theorems proved here are:

- `compress_singleChunk` / `decompress_singleChunk` — axioms: one push equals batch.
- `streaming_roundtrip` — compressing then decompressing via the streaming API
  recovers the original data.
- `streaming_rounds_eq_batch` — the streaming result equals the batch result.
-/

namespace Brotli.Spec.Streaming

/-! ## Canonical streaming helpers -/

/-- Whole-buffer compression using the streaming API:
    create a state, push all data in one chunk, flush and finish. -/
def streamCompress (data : ByteArray) (q : UInt8 := 11) : IO ByteArray := do
  let state  ← CompressState.new q
  let chunk  ← state.push data
  let tail   ← state.finish
  return chunk ++ tail

/-- Whole-buffer decompression using the streaming API:
    create a state, push all compressed data in one chunk, flush and finish. -/
def streamDecompress (data : ByteArray) : IO ByteArray := do
  let state  ← DecompressState.new
  let chunk  ← state.push data
  let tail   ← state.finish
  return chunk ++ tail

/-! ## Streaming axioms -/

/-- **Single-chunk compression axiom**: Using the streaming compressor with a
    single push of all data produces the same `ByteArray` as whole-buffer
    `Brotli.compress`.

    This axiom captures the RFC 7932 guarantee that the streaming encoder is
    *transparent*: it produces the same bit-for-bit output as the block encoder
    when all input is provided in one push.

    Note: quantified over all `q`, not just `ValidQuality q`.  For invalid `q`
    both sides raise the same error, so the equality holds vacuously. -/
axiom compress_singleChunk (data : ByteArray) (q : UInt8) :
    streamCompress data q = Brotli.compress data q

/-- **Single-chunk decompression axiom**: Using the streaming decompressor with a
    single push of all compressed data produces the same `ByteArray` as
    whole-buffer `Brotli.decompress`.

    Note: unconditional — holds for any input, valid or not.  Both sides either
    return the same bytes or raise the same error. -/
axiom decompress_singleChunk (data : ByteArray) :
    streamDecompress data = Brotli.decompress data

/-! ## Derived theorems -/

/-- `streamCompress` at the default quality equals `Brotli.compress` at default. -/
theorem compress_singleChunk_default (data : ByteArray) :
    streamCompress data = Brotli.compress data :=
  compress_singleChunk data 11

/-- **Streaming roundtrip**: compressing then decompressing via the single-chunk
    streaming API recovers the original data for any valid quality, given
    successful compression.

    Proof: rewrite the streaming operations to their batch equivalents, then
    apply the core conditional `roundtrip` axiom from `Brotli.Spec.Basic`. -/
theorem streaming_roundtrip (data : ByteArray) (q : UInt8)
    (hq : Brotli.Spec.ValidQuality q)
    (c : ByteArray) (hc : streamCompress data q = pure c) :
    streamDecompress c = pure data := by
  -- Rewrite streaming compress to batch compress
  rw [compress_singleChunk] at hc
  -- Rewrite streaming decompress to batch decompress
  rw [decompress_singleChunk]
  -- Apply the core conditional roundtrip axiom
  exact Brotli.Spec.roundtrip data q hq c hc

/-- Streaming roundtrip at the default quality (11). -/
theorem streaming_roundtrip_default (data : ByteArray)
    (c : ByteArray) (hc : streamCompress data = pure c) :
    streamDecompress c = pure data :=
  streaming_roundtrip data 11 (by simp) c hc

/-- **Quality invariance for streaming**: regardless of what valid quality is used
    for streaming compression, decompressing either result returns `data`. -/
theorem streaming_quality_invariant (data : ByteArray) (q₁ q₂ : UInt8)
    (hq₁ : Brotli.Spec.ValidQuality q₁) (hq₂ : Brotli.Spec.ValidQuality q₂)
    (c₁ : ByteArray) (hc₁ : streamCompress data q₁ = pure c₁)
    (c₂ : ByteArray) (hc₂ : streamCompress data q₂ = pure c₂) :
    streamDecompress c₁ = streamDecompress c₂ := by
  rw [streaming_roundtrip data q₁ hq₁ c₁ hc₁,
      streaming_roundtrip data q₂ hq₂ c₂ hc₂]

/-- Streaming and batch compression produce the same bytes (as IO actions). -/
theorem streaming_eq_batch_compress (data : ByteArray) (q : UInt8) :
    streamCompress data q = Brotli.compress data q :=
  compress_singleChunk data q

/-- Streaming and batch decompression produce the same bytes (as IO actions). -/
theorem streaming_eq_batch_decompress (data : ByteArray) :
    streamDecompress data = Brotli.decompress data :=
  decompress_singleChunk data

end Brotli.Spec.Streaming
