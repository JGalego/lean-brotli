/-! FFI bindings for whole-buffer Brotli compression/decompression (RFC 7932).

  Brotli does not embed the decompressed size in the stream, so decompression
  always uses a growable internal buffer.  For very large streams prefer the
  streaming API in `Brotli.Stream`. -/
namespace Brotli

/-- Compress data using Brotli.
    `quality` ranges from 0 (fastest) to 11 (best compression), default 11. -/
@[extern "lean_brotli_compress"]
opaque compress (data : @& ByteArray) (quality : UInt8 := 11) : IO ByteArray

/-- Decompress Brotli-compressed data.
    `maxDecompressedSize` limits output size (0 = no limit). -/
@[extern "lean_brotli_decompress"]
opaque decompress (data : @& ByteArray) (maxDecompressedSize : UInt64 := 0) : IO ByteArray

end Brotli
