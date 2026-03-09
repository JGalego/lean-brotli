import Brotli

/-! Download the Complete Works of Shakespeare from Project Gutenberg
    and compress/decompress with Brotli at several quality levels. -/

def main : IO Unit := do
  IO.println "Downloading Shakespeare 🪶"
  let cachedFile : System.FilePath := "pg100.txt"
  let shakespeare ←
    if ← cachedFile.pathExists then
      IO.println "Using cached Shakespeare 📖"
      IO.FS.readBinFile cachedFile
    else
      let child ← IO.Process.spawn {
        cmd    := "curl"
        args   := #["-#", "-L", "-o", cachedFile.toString,
                    "https://www.gutenberg.org/cache/epub/100/pg100.txt"]
        stderr := .inherit
      }
      let exitCode ← child.wait
      if exitCode != 0 then
        throw (IO.userError s!"curl failed (exit {exitCode})")
      IO.FS.readBinFile cachedFile

  -- Compress at different quality levels
  IO.println "Compressing with Brotli 🥦"
  let qualities := [0, 1, 4, 6, 9, 11]
  let mut rows : Array (String × String × String) := #[]
  for q in qualities do
    let compressed ← Brotli.compress shakespeare q.toUInt8
    let pct := (compressed.size * 1000 / shakespeare.size)
    rows := rows.push (s!"{q}", s!"{compressed.size}", s!"{pct / 10}.{pct % 10}%")
  -- Compute column widths from headers and data
  let headers := ("Quality", "Size", "Ratio")
  let mut w1 := headers.1.length
  let mut w2 := headers.2.1.length
  let mut w3 := headers.2.2.length
  for (c1, c2, c3) in rows do
    w1 := max w1 c1.length
    w2 := max w2 c2.length
    w3 := max w3 c3.length
  let pad (s : String) (w : Nat) (right : Bool := true) : String :=
    if right then s ++ String.pushn "" ' ' (w - s.length)
    else String.pushn "" ' ' (w - s.length) ++ s
  IO.println s!"┌{String.pushn "" '─' (w1 + 2)}┬{String.pushn "" '─' (w2 + 2)}┬{String.pushn "" '─' (w3 + 2)}┐"
  IO.println s!"│ {pad headers.1 w1} │ {pad headers.2.1 w2} │ {pad headers.2.2 w3} │"
  IO.println s!"├{String.pushn "" '─' (w1 + 2)}┼{String.pushn "" '─' (w2 + 2)}┼{String.pushn "" '─' (w3 + 2)}┤"
  for (c1, c2, c3) in rows do
    IO.println s!"│ {pad c1 w1 (right := false)} │ {pad c2 w2} │ {pad c3 w3 (right := false)} │"
  IO.println s!"└{String.pushn "" '─' (w1 + 2)}┴{String.pushn "" '─' (w2 + 2)}┴{String.pushn "" '─' (w3 + 2)}┘"

  -- Roundtrip tests
  IO.println "Testing roundtrips 🔄"
  let compressed ← Brotli.compress shakespeare
  let decompressed ← Brotli.decompress compressed
  IO.println s!"  + Original:     {shakespeare.size} bytes"
  IO.println s!"  + Compressed:   {compressed.size} bytes"
  IO.println s!"  + Decompressed: {decompressed.size} bytes"
  IO.println s!"  + In-memory: {if shakespeare == decompressed then "✅" else "⚠️"}"
  let tmpIn  : System.FilePath := "/tmp/shakespeare.txt"
  let tmpBr  : System.FilePath := "/tmp/shakespeare.txt.br"
  IO.FS.writeBinFile tmpIn shakespeare
  let _ ← Brotli.compressFile tmpIn
  let _ ← Brotli.decompressFile tmpBr
  let recovered ← IO.FS.readBinFile tmpIn
  IO.println s!"  + Streaming: {if shakespeare == recovered then "✅" else "⚠️"}"

  -- Clean up
  let _ ← IO.Process.run { cmd := "rm", args := #["-f", tmpIn.toString, tmpBr.toString] }
