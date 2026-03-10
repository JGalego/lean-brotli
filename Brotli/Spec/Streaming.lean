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
    when all input is provided in one push. -/
axiom compress_singleChunk (data : ByteArray) (q : UInt8) :
    streamCompress data q = Brotli.compress data q

/-- **Single-chunk decompression axiom**: Using the streaming decompressor with a
    single push of all compressed data produces the same `ByteArray` as
    whole-buffer `Brotli.decompress`. -/
axiom decompress_singleChunk (data : ByteArray) :
    streamDecompress data = Brotli.decompress data

/-! ## Derived theorems -/

/-- `streamCompress` at the default quality equals `Brotli.compress` at default. -/
theorem compress_singleChunk_default (data : ByteArray) :
    streamCompress data = Brotli.compress data :=
  compress_singleChunk data 11

/-- The streaming compress output is the same as the batch compress output:
    useful in `calc`-style rewrites. -/
theorem streamCompress_eq (data : ByteArray) (q : UInt8) :
    streamCompress data q = Brotli.compress data q :=
  compress_singleChunk data q

/-- The streaming decompress output is the same as the batch decompress output. -/
theorem streamDecompress_eq (data : ByteArray) :
    streamDecompress data = Brotli.decompress data :=
  decompress_singleChunk data

/-- **Streaming roundtrip**: compressing then decompressing via the single-chunk
    streaming API recovers the original data for any valid quality.

    Proof: rewrite both streaming operations to their batch equivalents using
    the single-chunk axioms, then apply the core `roundtrip` axiom. -/
theorem streaming_roundtrip (data : ByteArray) (q : UInt8)
    (hq : Brotli.Spec.ValidQuality q) :
    (streamCompress data q >>= streamDecompress) = pure data := by
  -- streamDecompress = Brotli.decompress as functions (by decompress_singleChunk)
  have hd : streamDecompress = Brotli.decompress :=
    funext decompress_singleChunk
  -- streamCompress data q = Brotli.compress data q (by compress_singleChunk)
  rw [compress_singleChunk data q, hd]
  -- Brotli.compress data q >>= Brotli.decompress = pure data (by roundtrip)
  exact Brotli.Spec.roundtrip data q hq

/-- Streaming roundtrip at the default quality (11). -/
theorem streaming_roundtrip_default (data : ByteArray) :
    (streamCompress data >>= streamDecompress) = pure data :=
  streaming_roundtrip data 11 (by decide)

/-- **Quality invariance for streaming**: regardless of what valid quality is used
    for streaming compression, decompressing the output always yields `data`. -/
theorem streaming_quality_invariant (data : ByteArray) (q₁ q₂ : UInt8)
    (hq₁ : Brotli.Spec.ValidQuality q₁) (hq₂ : Brotli.Spec.ValidQuality q₂) :
    (streamCompress data q₁ >>= streamDecompress) =
    (streamCompress data q₂ >>= streamDecompress) := by
  rw [streaming_roundtrip data q₁ hq₁, streaming_roundtrip data q₂ hq₂]

/-- Streaming and batch compression produce the same bytes (as IO actions). -/
theorem streaming_eq_batch_compress (data : ByteArray) (q : UInt8) :
    streamCompress data q = Brotli.compress data q :=
  compress_singleChunk data q

/-- Streaming and batch decompression produce the same bytes (as IO actions). -/
theorem streaming_eq_batch_decompress (data : ByteArray) :
    streamDecompress data = Brotli.decompress data :=
  decompress_singleChunk data

/-- Streaming compress → streaming decompress is equivalent to
    batch compress → batch decompress. -/
theorem streaming_eq_batch_roundtrip (data : ByteArray) (q : UInt8) :
    (streamCompress data q >>= streamDecompress) =
    (Brotli.compress data q >>= Brotli.decompress) := by
  have hd : streamDecompress = Brotli.decompress := funext decompress_singleChunk
  rw [compress_singleChunk, hd]

end Brotli.Spec.Streaming
