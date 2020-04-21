# Package

version       = "0.2.0"
author        = "Mamy André-Ratsimbazafy"
description   = "A compile-time, compact, fast, without allocation, state-machine generator."
license       = "MIT or Apache License 2.0"

# Dependencies

requires "nim >= 1.0.4"

proc test(flags, path: string) =
  if not dirExists "build":
    mkDir "build"
  # Note: we compile in release mode. This still have stacktraces
  #       but is much faster than -d:debug

  # Compilation language is controlled by TEST_LANG
  var lang = "c"
  if existsEnv"TEST_LANG":
    lang = getEnv"TEST_LANG"

  echo "\n========================================================================================"
  echo "Running [ ", lang, " ", flags, " ] ", path
  echo "========================================================================================"
  exec "nim " & lang & " " & flags & " -d:release --outdir:build -r " & path

task test, "Run Synthesis tests":
  test "", "examples/water_phase_transitions.nim"
