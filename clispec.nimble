import std/[strutils]
version       = readFile("version.txt").strip()
author        = "Metacraft Labs"
description   = "Declarative command-line descriptions for Nim: a typed CLI model, the cli: language that builds it, and the typed configuration object, parser and help generated from it."
license       = "Apache-2.0"
srcDir        = "src"
skipDirs      = @["tests"]

requires "nim >= 2.0.0"

# Only the optional TOML adapter (`clispec/toml_source`) and the tests that
# drive it need these; a consumer that imports that module requires
# `toml_serialization` itself. The revisions match the dev shell's.
taskRequires "test", "https://github.com/status-im/nim-toml-serialization#b5b387e6fb2a7cc75d54a269b07cc6218361bd46"
taskRequires "test", "https://github.com/status-im/nim-serialization#1790d8a931fce125d6722f7ee8432ee8c054d297"
taskRequires "test", "https://github.com/status-im/nim-faststreams#50889cd16ec8771106cdd0eeea460039e8571e06"
taskRequires "test", "https://github.com/status-im/nim-stew#30dadcd14b5ec1631935d9037213ece6871cc11a"
taskRequires "test", "https://github.com/arnetheduck/nim-results#55b41b285def7b7b98dd5b9669f352d1fdc35c2b"

task test, "Run the test suite":
  for t in ["test_dsl_model", "test_extension", "test_cs_m2_model_round_trip",
            "test_cs_m2_invalid_declarations_fail_to_compile",
            "test_cs_m3_parser_accepts_declared_forms",
            "test_cs_m3_parser_error_taxonomy",
            "test_cs_m3_help_matches_model", "test_readme_examples",
            "test_cs_m4_precedence_and_origins", "test_cs_m4_merge_rules",
            "test_cs_m4_enforced_value_explained",
            "test_cs_m4_default_never_overrides_file",
            "test_cs_m4_unknown_key_rejected",
            "test_cs_m4b_convention_conversion",
            "test_cs_m4b_per_source_convention",
            "test_cs_m4b_override_precedence",
            "test_cs_m5_engine_completes_every_level",
            "test_cs_m5_internal_parameters_work_unlisted",
            "test_suite_lists_agree"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"

task e2e, "Run the end-to-end tests (real shells in a pseudo-terminal)":
  for t in ["e2e_cs_m5_real_shell_completion"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"
