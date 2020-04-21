# Package

version       = "0.2.0"
author        = "Mamy André-Ratsimbazafy"
description   = "A compile-time, compact, fast, without allocation, state-machine generator."
license       = "MIT or Apache License 2.0"

# Dependencies

requires "nim >= 1.0.4"

proc test(path: string, lang = "c") =
  if not dirExists "build":
    mkDir "build"
  exec "nim " & lang & " --outdir:build -r " & path

task test, "Run Synthesis tests":
  test "examples/water_phase_transitions.nim"
