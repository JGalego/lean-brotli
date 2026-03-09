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

  -- Helper: format byte count as "X.XX MB"
  let toMB (n : Nat) : String :=
    let whole := n / 1048576
    let frac  := (n % 1048576) * 100 / 1048576
    s!"{whole}.{frac / 10}{frac % 10} MB"

  -- Compress at different quality levels
  IO.println "Compressing with Brotli 🥦"
  let qualities := [0, 1, 4, 6, 9, 11]
  let (w1, w2, w3) := (7, 7, 5)  -- Quality / Size (MB) / Ratio
  let pad (s : String) (w : Nat) (right : Bool := true) : String :=
    if right then s ++ String.pushn "" ' ' (w - s.length)
    else String.pushn "" ' ' (w - s.length) ++ s
  IO.println s!"┌{String.pushn "" '─' (w1 + 2)}┬{String.pushn "" '─' (w2 + 2)}┬{String.pushn "" '─' (w3 + 2)}┐"
  IO.println s!"│ {pad "Quality" w1} │ {pad "Size" w2} │ {pad "Ratio" w3} │"
  IO.println s!"├{String.pushn "" '─' (w1 + 2)}┼{String.pushn "" '─' (w2 + 2)}┼{String.pushn "" '─' (w3 + 2)}┤"
  for q in qualities do
    let compressed ← Brotli.compress shakespeare q.toUInt8
    let pct := (compressed.size * 1000 / shakespeare.size)
    IO.println s!"│ {pad s!"{q}" w1 (right := false)} │ {pad (toMB compressed.size) w2} │ {pad s!"{pct / 10}.{pct % 10}%" w3 (right := false)} │"
  IO.println s!"└{String.pushn "" '─' (w1 + 2)}┴{String.pushn "" '─' (w2 + 2)}┴{String.pushn "" '─' (w3 + 2)}┘"

  -- Roundtrip tests
  IO.println "Testing roundtrips 🔄"
  let compressed ← Brotli.compress shakespeare
  let decompressed ← Brotli.decompress compressed
  IO.println s!"  + Original:     {toMB shakespeare.size}"
  IO.println s!"  + Compressed:   {toMB compressed.size}"
  IO.println s!"  + Decompressed: {toMB decompressed.size}"
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
