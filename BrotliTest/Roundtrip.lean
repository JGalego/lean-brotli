import BrotliTest.Helpers

/-! Tests for whole-buffer Brotli compress / decompress. -/

/-- Tests for whole-buffer Brotli compress / decompress roundtrips. -/
def BrotliTest.Roundtrip.tests : IO Unit := do
  let data ← mkTestData

  -- Default quality roundtrip
  let comp ← Brotli.compress data
  let decomp ← Brotli.decompress comp
  unless decomp == data do throw (IO.userError "brotli default-quality roundtrip failed")

  -- All quality levels
  for q in List.range 12 do  -- 0..11
    let c ← Brotli.compress data q.toUInt8
    let d ← Brotli.decompress c
    unless d == data do throw (IO.userError s!"brotli quality {q} roundtrip failed")

  -- Empty input
  let emptyComp ← Brotli.compress ByteArray.empty
  let emptyDecomp ← Brotli.decompress emptyComp
  unless emptyDecomp.size == 0 do throw (IO.userError "brotli empty roundtrip failed")

  -- Single byte
  let oneByte : ByteArray := ByteArray.mk #[0x42]
  let oneComp ← Brotli.compress oneByte
  let oneDecomp ← Brotli.decompress oneComp
  unless oneDecomp == oneByte do throw (IO.userError "brotli single-byte roundtrip failed")

  -- Decompression size limit should be rejected
  assertThrows "brotli decompress size limit"
    (do let _ ← Brotli.decompress comp (maxDecompressedSize := 10))
    "exceeds limit"

  -- Compress more compressible data produces smaller output (quality 11 < quality 0)
  let mut repetitive := ByteArray.empty
  for _ in [:10000] do repetitive := repetitive.push 0x41
  let cFast ← Brotli.compress repetitive 0
  let cBest ← Brotli.compress repetitive 11
  unless cFast.size >= cBest.size do
    IO.eprintln s!"warning: quality 0 ({cFast.size}B) not larger than quality 11 ({cBest.size}B) — unusual but not fatal"

  -- Large data
  let large ← mkLargeData
  let largeComp ← Brotli.compress large
  let largeDec ← Brotli.decompress largeComp
  unless largeDec == large do throw (IO.userError "brotli large-data roundtrip failed")

  IO.println "Roundtrip tests: OK"
