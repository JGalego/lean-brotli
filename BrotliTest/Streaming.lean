import BrotliTest.Helpers

/-! Tests for streaming Brotli compression / decompression. -/

/-- Tests for streaming Brotli compression / decompression. -/
def BrotliTest.Streaming.tests : IO Unit := do
  let data ← mkTestData
  let chunkSize := 1000

  -- Invalid quality should be rejected for streaming state
  assertThrows "brotli streaming invalid quality"
    (do let _ ← Brotli.CompressState.new 12)
    "quality"

  -- Streaming compress → streaming decompress (small chunks)
  let enc ← Brotli.CompressState.new
  let mut compBuf := ByteArray.empty
  let mut off := 0
  while off < data.size do
    let chunk := data.extract off (min (off + chunkSize) data.size)
    let out ← enc.push chunk
    compBuf := compBuf ++ out
    off := off + chunkSize
  let final ← enc.finish
  compBuf := compBuf ++ final

  let dec ← Brotli.DecompressState.new
  let mut decBuf := ByteArray.empty
  off := 0
  while off < compBuf.size do
    let chunk := compBuf.extract off (min (off + chunkSize) compBuf.size)
    let out ← dec.push chunk
    decBuf := decBuf ++ out
    off := off + chunkSize
  let decFinal ← dec.finish
  decBuf := decBuf ++ decFinal
  unless decBuf == data do throw (IO.userError "streaming compress→decompress roundtrip failed")

  -- Trailing garbage after a valid Brotli stream should be rejected
  let trailing := compBuf ++ (ByteArray.mk #[0xAA, 0xBB, 0xCC])
  let decTrailing ← Brotli.DecompressState.new
  assertThrows "brotli trailing compressed bytes"
    (do let _ ← decTrailing.push trailing)
    "trailing data"

  -- Additional push after end-of-stream should be rejected
  let decDone ← Brotli.DecompressState.new
  let _ ← decDone.push compBuf
  let _ ← decDone.finish
  assertThrows "brotli push after stream end"
    (do let _ ← decDone.push (ByteArray.mk #[0x00]))
    "end of stream"

  -- compressStream / decompressStream helpers
  let inStream  ← byteArrayReadStream data
  let (outStream, getOut) ← collectStream
  Brotli.compressStream inStream outStream
  let streamCompressed ← getOut

  let inStream2 ← byteArrayReadStream streamCompressed
  let (outStream2, getOut2) ← collectStream
  Brotli.decompressStream inStream2 outStream2
  let streamDecompressed ← getOut2
  unless streamDecompressed == data do throw (IO.userError "compressStream/decompressStream roundtrip failed")

  -- compressStream at quality 0 (fastest)
  let inStream3 ← byteArrayReadStream data
  let (outStream3, getOut3) ← collectStream
  Brotli.compressStream inStream3 outStream3 (quality := 0)
  let fastCompressed ← getOut3
  let inStream4 ← byteArrayReadStream fastCompressed
  let (outStream4, getOut4) ← collectStream
  Brotli.decompressStream inStream4 outStream4
  let fastDecompressed ← getOut4
  unless fastDecompressed == data do throw (IO.userError "compressStream quality 0 roundtrip failed")

  -- Large data streaming
  let large ← mkLargeData
  let inLarge  ← byteArrayReadStream large
  let (outLarge, getLarge) ← collectStream
  Brotli.compressStream inLarge outLarge
  let largeComp ← getLarge

  let inLarge2 ← byteArrayReadStream largeComp
  let (outLarge2, getLarge2) ← collectStream
  Brotli.decompressStream inLarge2 outLarge2
  let largeDec ← getLarge2
  unless largeDec == large do throw (IO.userError "large streaming roundtrip failed")

  IO.println "Streaming tests: OK"
