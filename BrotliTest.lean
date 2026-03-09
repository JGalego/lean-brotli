import BrotliTest.Roundtrip
import BrotliTest.Streaming
import BrotliTest.Files

def main : IO Unit := do
  BrotliTest.Roundtrip.tests
  BrotliTest.Streaming.tests
  BrotliTest.Files.tests
  IO.println "All tests passed."
