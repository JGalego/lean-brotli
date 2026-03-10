import Lake
open System Lake DSL

/-- Run `pkg-config` and split the output into flags. Returns `#[]` on failure. -/
def pkgConfig (pkg : String) (flag : String) : IO (Array String) := do
  let out ← IO.Process.output { cmd := "pkg-config", args := #[flag, pkg] }
  if out.exitCode != 0 then return #[]
  return out.stdout.trimAscii.toString.splitOn " " |>.filter (· ≠ "") |>.toArray

/-- Get brotli encoder include flags, respecting `BROTLI_CFLAGS` env var override. -/
def brotliCFlags : IO (Array String) := do
  if let some flags := (← IO.getEnv "BROTLI_CFLAGS") then
    return flags.trimAscii.toString.splitOn " " |>.filter (· ≠ "") |>.toArray
  pkgConfig "libbrotlienc" "--cflags"

/-- Extract `-L` library paths from `NIX_LDFLAGS` (set by nix-shell). -/
def nixLdLibPaths : IO (Array String) := do
  let some val := (← IO.getEnv "NIX_LDFLAGS") | return #[]
  return val.splitOn " " |>.filter (·.startsWith "-L") |>.toArray

/-- Get the library directory for a pkg-config package. -/
def pkgConfigLibDir (pkg : String) : IO (Option String) := do
  let out ← IO.Process.output { cmd := "pkg-config", args := #["--variable=libdir", pkg] }
  if out.exitCode != 0 then return none
  let dir := out.stdout.trimAscii.toString
  if dir.isEmpty then return none
  return some dir

/-- Search for a static brotli library in the given paths and standard dirs. -/
def findStaticLib (libName : String) (libPaths : Array String) : IO (Option System.FilePath) := do
  let fname := s!"lib{libName}.a"
  for p in libPaths do
    let path := (⟨(p.drop 2).toString⟩ : System.FilePath) / fname
    if (← path.pathExists) then return some path
  if let some dir := (← pkgConfigLibDir s!"lib{libName}") then
    let path := (⟨dir⟩ : System.FilePath) / fname
    if (← path.pathExists) then return some path
  for dir in #["/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu",
               "/usr/lib64", "/usr/local/lib"] do
    let path := (⟨dir⟩ : System.FilePath) / fname
    if (← path.pathExists) then return some path
  return none

/-- Get combined link flags for libbrotli (enc + dec + common).
    Tries to link the three static archives directly to avoid glibc version
    mismatches with Lean's bundled toolchain sysroot. -/
def linkFlags : IO (Array String) := do
  let libPaths ← nixLdLibPaths
  -- pkg-config flags (may include -L and -l entries)
  let encFlags  ← pkgConfig "libbrotlienc"    "--libs"
  let decFlags  ← pkgConfig "libbrotlidec"    "--libs"
  -- Merge all -L paths for static-lib search
  let allPaths := libPaths ++ (encFlags ++ decFlags).filter (·.startsWith "-L")

  -- Prefer static archives on Linux to avoid glibc symbol issues
  if !System.Platform.isOSX then
    let encSt  ← findStaticLib "brotlienc"    allPaths
    let decSt  ← findStaticLib "brotlidec"    allPaths
    let commSt ← findStaticLib "brotlicommon" allPaths
    if let (some enc, some dec, some comm) := (encSt, decSt, commSt) then
      return #[enc.toString, dec.toString, comm.toString]
  -- macOS or static libs not found — fall back to dynamic linking
  let shlibFlags := if System.Platform.isOSX then #[] else #["-Wl,--allow-shlib-undefined"]
  if !encFlags.isEmpty && !decFlags.isEmpty then
    return encFlags ++ decFlags ++ shlibFlags
  -- Last resort
  return libPaths ++ #["-lbrotlienc", "-lbrotlidec", "-lbrotlicommon"] ++ shlibFlags

package «lean-brotli» where
  moreLinkArgs := run_io linkFlags
  testDriver   := "test"
  lintDriver   := "batteries/runLinter"

require "leanprover-community" / "batteries" @ git "main"

lean_lib Brotli

-- Brotli FFI ------------------------------------------------------------------
input_file brotli_ffi.c where
  path := "c" / "brotli_ffi.c"
  text := true

target brotli_ffi.o pkg : FilePath := do
  let srcJob ← brotli_ffi.c.fetch
  let oFile  := pkg.buildDir / "c" / "brotli_ffi.o"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString] ++ (← brotliCFlags)
  let hardArgs := if Platform.isWindows then #[] else #["-fPIC"]
  buildO oFile srcJob weakArgs hardArgs "cc"

extern_lib libbrotli_ffi pkg := do
  let ffiO ← brotli_ffi.o.fetch
  let name := nameToStaticLib "brotli_ffi"
  buildStaticLib (pkg.staticLibDir / name) #[ffiO]

-- Tests -----------------------------------------------------------------------
lean_lib BrotliTest where
  globs := #[.submodules `BrotliTest]

@[default_target]
lean_exe test where
  root := `BrotliTest

-- Benchmark -------------------------------------------------------------------
lean_exe bench where
  root := `BrotliBench

-- Example ---------------------------------------------------------------------
lean_exe shakespeare where
  root := `BrotliShakespeare
