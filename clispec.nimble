import std/[strutils]
version       = readFile("version.txt").strip()
author        = "Metacraft Labs"
description   = "Declarative command-line descriptions for Nim: a typed CLI model, the cli: language that builds it, and the typed configuration object, parser and help generated from it."
license       = "Apache-2.0"
srcDir        = "src"
skipDirs      = @["tests"]

requires "nim >= 2.0.0"

task test, "Run the test suite":
  for t in ["test_dsl_model", "test_extension", "test_cs_m2_model_round_trip",
            "test_cs_m2_invalid_declarations_fail_to_compile",
            "test_cs_m3_parser_accepts_declared_forms",
            "test_cs_m3_parser_error_taxonomy",
            "test_cs_m3_help_matches_model", "test_readme_examples"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"
