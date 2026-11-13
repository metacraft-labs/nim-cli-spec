import std/[strutils]
version       = readFile("version.txt").strip()
author        = "Metacraft Labs"
description   = "Declarative command-line descriptions for Nim: a typed CLI model and the cli: language that builds it."
license       = "Apache-2.0"
srcDir        = "src"
skipDirs      = @["tests"]

requires "nim >= 2.0.0"

task test, "Run the test suite":
  for t in ["test_dsl_model", "test_extension", "test_cs_m2_model_round_trip",
            "test_cs_m2_invalid_declarations_fail_to_compile"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"
