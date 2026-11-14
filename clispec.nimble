import std/[os, strutils]
# Nimble evaluates this file from its own working directory, not the
# package's, so the version file is located relative to this file.
version       = readFile(thisDir() / "version.txt").strip()
author        = "Metacraft Labs"
description   = "Declarative command-line descriptions for Nim: a typed CLI model, the cli: language that builds it, and the typed configuration object, parser and help generated from it."
license       = "Apache-2.0"
srcDir        = "src"
skipDirs      = @["tests"]

# Clispec needs nothing beyond the standard library. Configuration files
# (and the serialization libraries that read them) are confutils', which is
# instantiated over a clispec description.
requires "nim >= 2.0.0"

task test, "Run the test suite":
  for t in ["test_dsl_model", "test_extension", "test_cs_m2_model_round_trip",
            "test_cs_m2_invalid_declarations_fail_to_compile",
            "test_cs_m3_parser_accepts_declared_forms",
            "test_cs_m3_parser_error_taxonomy",
            "test_cs_m3_help_matches_model", "test_readme_examples",
            "test_cs_m4b_convention_conversion",
            "test_cs_m4b_per_source_convention",
            "test_cs_m4b_override_precedence",
            "test_cs_m5_engine_completes_every_level",
            "test_cs_m5_internal_parameters_work_unlisted",
            "test_cs_m9_clispec_has_no_serialization_dependency",
            "test_suite_lists_agree"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"

task e2e, "Run the end-to-end tests (real shells in a pseudo-terminal)":
  for t in ["e2e_cs_m5_real_shell_completion"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"
