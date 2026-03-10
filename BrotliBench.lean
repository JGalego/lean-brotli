import Brotli

/-! Benchmark driver.

Usage:
  lake exe bench <operation> <size> <pattern> [quality]

Operations:
  compress       — Brotli compression (FFI)
  decompress     — Brotli decompression (FFI)

Patterns:   constant, cyclic, prng
Quality:    0-11 (default 11, only for compression)

Examples:
  hyperfine 'lake exe bench compress 1048576 prng 6'
  hyperfine '.lake/build/bin/bench compress 10485760 prng 11' \
            '.lake/build/bin/bench decompress 10485760 prng'
  hyperfine --parameter-list quality 0,5,11 \
            '.lake/build/bin/bench compress 1048576 prng {quality}'
-/

def mkConstantData (size : Nat) : ByteArray := Id.run do
  let mut r := ⟨Array.mkEmpty size⟩
  for _ in [:size] do r := r.push 0x42
  return r

def mkCyclicData (size : Nat) : ByteArray := Id.run do
  let pat : Array UInt8 := #[0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
                               0x88,0x99,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF]
  let mut r := ⟨Array.mkEmpty size⟩
  for i in [:size] do r := r.push pat[i % 16]!
  return r

def mkPrngData (size : Nat) : ByteArray := Id.run do
  let mut state : UInt32 := 2463534242
  let mut r := ⟨Array.mkEmpty size⟩
  for _ in [:size] do
    state := state ^^^ (state <<< 13)
    state := state ^^^ (state >>> 17)
    state := state ^^^ (state <<< 5)
    r := r.push (state &&& 0xFF).toUInt8
  return r

def generateData (pattern : String) (size : Nat) : IO ByteArray :=
  match pattern with
  | "constant" => pure (mkConstantData size)
  | "cyclic"   => pure (mkCyclicData size)
  | "prng"     => pure (mkPrngData size)
  | other      => throw (IO.userError s!"unknown pattern: {other}")

def main (args : List String) : IO Unit := do
  match args with
  | [op, sizeStr, pattern]             => run op sizeStr pattern 11
  | [op, sizeStr, pattern, qualityStr] =>
    match qualityStr.toNat? with
    | some q => run op sizeStr pattern q
    | none   => usage
  | _ => usage
where
  usage := throw (IO.userError
    "usage: bench <compress|decompress> <size> <constant|cyclic|prng> [quality]")
  run (op sizeStr pattern : String) (quality : Nat) : IO Unit := do
    let some size := sizeStr.toNat? | usage
    let data ← generateData pattern size
    match op with
    | "compress" =>
      let result ← Brotli.compress data quality.toUInt8
      IO.println s!"compress: {data.size} bytes → {result.size} bytes (quality {quality})"
    | "decompress" =>
      let compressed ← Brotli.compress data quality.toUInt8
      let result ← Brotli.decompress compressed
      IO.println s!"decompress: {compressed.size} bytes → {result.size} bytes"
    | other =>
      throw (IO.userError s!"unknown operation: {other}")
