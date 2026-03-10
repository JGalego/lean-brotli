import BrotliTest.Roundtrip
import BrotliTest.Streaming
import BrotliTest.Files

/-- Run all Brotli test suites. -/
def main : IO Unit := do
  BrotliTest.Roundtrip.tests
  BrotliTest.Streaming.tests
  BrotliTest.Files.tests
  IO.println "All tests passed."
