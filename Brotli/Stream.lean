import Brotli.Basic

/-! Streaming Brotli compression and decompression with file helpers.

  Streaming is the preferred API for data too large to fit in memory.
  The whole-buffer functions in `Brotli.Basic` are simpler but require the
  entire payload to be in memory at once. -/

namespace Brotli

-- Streaming compression -------------------------------------------------------

/-- Opaque streaming Brotli compression state.  Automatically cleaned up when dropped. -/
opaque CompressState.nonemptyType : NonemptyType
def CompressState : Type := CompressState.nonemptyType.type
instance : Nonempty CompressState := CompressState.nonemptyType.property

/-- Create a new streaming Brotli compressor.
    `quality` ranges from 0 (fastest) to 11 (best compression), default 11. -/
@[extern "lean_brotli_compress_new"]
opaque CompressState.new (quality : UInt8 := 11) : IO CompressState

/-- Push a chunk of uncompressed data through the compressor.
    Returns any compressed output produced so far (may be empty — Brotli
    buffers internally and emits data in its own rhythm). -/
@[extern "lean_brotli_compress_push"]
opaque CompressState.push (state : @& CompressState) (chunk : @& ByteArray) : IO ByteArray

/-- Finish the compression stream.
    Flushes all buffered data and writes the final Brotli end-of-stream marker.
    Must be called exactly once after all data has been pushed. -/
@[extern "lean_brotli_compress_finish"]
opaque CompressState.finish (state : @& CompressState) : IO ByteArray

-- Streaming decompression -----------------------------------------------------

/-- Opaque streaming Brotli decompression state.  Automatically cleaned up when dropped. -/
opaque DecompressState.nonemptyType : NonemptyType
def DecompressState : Type := DecompressState.nonemptyType.type
instance : Nonempty DecompressState := DecompressState.nonemptyType.property

/-- Create a new streaming Brotli decompressor. -/
@[extern "lean_brotli_decompress_new"]
opaque DecompressState.new : IO DecompressState

/-- Push a chunk of compressed data through the decompressor.
    Returns all decompressed output produced from this chunk. -/
@[extern "lean_brotli_decompress_push"]
opaque DecompressState.push (state : @& DecompressState) (chunk : @& ByteArray) : IO ByteArray

/-- Finish the decompression stream and clean up.
    Returns any remaining output (typically empty for Brotli). -/
@[extern "lean_brotli_decompress_finish"]
opaque DecompressState.finish (state : @& DecompressState) : IO ByteArray

-- Stream piping ---------------------------------------------------------------

/-- Compress from input stream to output stream in Brotli format.
    Reads 64 KB chunks — memory usage is bounded regardless of data size. -/
partial def compressStream (input : IO.FS.Stream) (output : IO.FS.Stream)
    (quality : UInt8 := 11) : IO Unit := do
  let state ← CompressState.new quality
  repeat do
    let chunk ← input.read 65536
    if chunk.isEmpty then break
    let compressed ← state.push chunk
    if compressed.size > 0 then output.write compressed
  let final ← state.finish
  if final.size > 0 then output.write final
  output.flush

/-- Decompress Brotli data from input stream to output stream.
    Memory usage is bounded. -/
partial def decompressStream (input : IO.FS.Stream) (output : IO.FS.Stream) : IO Unit := do
  let state ← DecompressState.new
  repeat do
    let chunk ← input.read 65536
    if chunk.isEmpty then break
    let decompressed ← state.push chunk
    if decompressed.size > 0 then output.write decompressed
  let final ← state.finish
  if final.size > 0 then output.write final
  output.flush

-- File helpers ----------------------------------------------------------------

/-- Compress a file in Brotli format, writing to `path ++ ".br"`.
    Returns the output path.  Streams with bounded memory. -/
def compressFile (path : System.FilePath) (quality : UInt8 := 11) : IO System.FilePath := do
  let outPath : System.FilePath := ⟨path.toString ++ ".br"⟩
  IO.FS.withFile path .read fun inH =>
    IO.FS.withFile outPath .write fun outH =>
      compressStream (IO.FS.Stream.ofHandle inH) (IO.FS.Stream.ofHandle outH) quality
  return outPath

/-- Decompress a `.br` file.  Strips `.br` suffix, or appends `.unbr` as fallback.
    Optional explicit output path.  Streams with bounded memory. -/
def decompressFile (path : System.FilePath) (outPath : Option System.FilePath := none)
    : IO System.FilePath := do
  let out := match outPath with
    | some p => p
    | none =>
      let s := path.toString
      if s.endsWith ".br" then ⟨(s.dropEnd 3).toString⟩ else ⟨s ++ ".unbr"⟩
  IO.FS.withFile path .read fun inH =>
    IO.FS.withFile out .write fun outH =>
      decompressStream (IO.FS.Stream.ofHandle inH) (IO.FS.Stream.ofHandle outH)
  return out

end Brotli
