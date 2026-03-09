import BrotliTest.Helpers

/-! Tests for file-based Brotli compress / decompress helpers. -/

def BrotliTest.Files.tests : IO Unit := do
  let data ← mkTestData

  -- compressFile / decompressFile
  let inPath  : System.FilePath := "/tmp/lean-brotli-test-input"
  let brPath  : System.FilePath := "/tmp/lean-brotli-test-input.br"
  IO.FS.writeBinFile inPath data

  let outBr ← Brotli.compressFile inPath
  unless outBr.toString == brPath.toString do
    throw (IO.userError s!"compressFile: unexpected output path {outBr}")

  -- decompress back to a different temp path
  let decPath : System.FilePath := "/tmp/lean-brotli-test-input.dec"
  let _ ← Brotli.decompressFile outBr (outPath := some decPath)
  let recovered ← IO.FS.readBinFile decPath
  unless recovered.beq data do throw (IO.userError "compressFile/decompressFile roundtrip failed")

  -- decompressFile with default path stripping (.br suffix)
  let _ ← Brotli.decompressFile outBr   -- writes to /tmp/lean-brotli-test-input
  let recovered2 ← IO.FS.readBinFile inPath
  unless recovered2.beq data do throw (IO.userError "decompressFile suffix-strip roundtrip failed")

  let _ ← IO.Process.run { cmd := "rm", args := #["-f", inPath.toString, brPath.toString, decPath.toString] }

  IO.println "File tests: OK"
