import Brotli

/-! Test utilities: byte-array comparison, assertion helpers, and test data generation. -/

/-- Check that two byte arrays are equal. -/
def ByteArray.beq (a b : ByteArray) : Bool :=
  a.data == b.data

/-- Assert that an IO action throws an error containing the given substring. -/
def assertThrows (description : String) (action : IO α) (errorSubstring : String) : IO Unit := do
  let sentinel := "<<ASSERT_THROWS_FAIL>>"
  try
    let _ ← action
    throw (IO.userError s!"{sentinel}{description}: expected error containing '{errorSubstring}' but succeeded")
  catch e =>
    let msg := toString e
    if msg.contains sentinel then throw e
    else if msg.contains errorSubstring then pure ()
    else throw (IO.userError s!"{sentinel}{description}: expected '{errorSubstring}' but got: {msg}")

/-- Create a readable `IO.FS.Stream` backed by a `ByteArray`. -/
def byteArrayReadStream (data : ByteArray) : IO IO.FS.Stream := do
  let posRef ← IO.mkRef 0
  return {
    flush   := pure ()
    read    := fun n => do
      let pos  ← posRef.get
      let avail := data.size - pos
      let toRead := min n.toNat avail
      let result := data.extract pos (pos + toRead)
      posRef.set (pos + toRead)
      return result
    write   := fun _ => throw (IO.userError "byteArrayReadStream: write not supported")
    getLine := pure ""
    putStr  := fun _ => pure ()
    isTty   := pure false
  }

/-- Collect all bytes written to a stream into a `ByteArray`. -/
def collectStream : IO (IO.FS.Stream × IO (ByteArray)) := do
  let buf ← IO.mkRef ByteArray.empty
  let stream : IO.FS.Stream := {
    flush   := pure ()
    read    := fun _ => pure ByteArray.empty
    write   := fun chunk => buf.modify (· ++ chunk)
    getLine := pure ""
    putStr  := fun _ => pure ()
    isTty   := pure false
  }
  return (stream, buf.get)

/-- Build the standard medium-sized test payload (~50 KB of mixed data). -/
def mkTestData : IO ByteArray := do
  let mut result := ByteArray.empty
  -- Repeated pattern portion (compresses well)
  for i in [:10000] do
    result := result.push (i % 256).toUInt8
  -- Pseudo-random portion (harder to compress)
  let mut state : UInt32 := 2463534242
  for _ in [:10000] do
    state := state ^^^ (state <<< 13)
    state := state ^^^ (state >>> 17)
    state := state ^^^ (state <<< 5)
    result := result.push (state &&& 0xFF).toUInt8
  -- ASCII text portion
  let text := "The quick brown fox jumps over the lazy dog. "
  for _ in [:500] do
    for b in text.toUTF8 do
      result := result.push b
  return result

/-- Build a larger test payload (~1 MB). -/
def mkLargeData : IO ByteArray := do
  let base ← mkTestData
  let mut result := ByteArray.empty
  for _ in [:20] do
    result := result ++ base
  return result
