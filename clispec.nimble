# The version is written here as a literal, not read from version.txt:
# Nimble evaluates this file from its own working directory, and again in
# the installed copy of the package, which holds only `src/` and this file.
# `just bump-version` writes both; test_suite_lists_agree checks they agree.
version       = "0.1.0"
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
            "test_cs_m10_help_layout", "test_cs_m10_parse_compat_rules",
            "test_cs_m10_confutils_compat_record",
            "test_cs_m10_command_word_rules",
            "test_cs_m10_dash_and_letter_rules",
            "test_cs_m5b_help_matches_design",
            "test_cs_m5b_no_color_and_not_a_terminal",
            "test_cs_m5c_colour_detection",
            "test_cs_m5c_styled_goldens",
            "test_cs_m5c_compile_time_knobs_shrink",
            "test_type_check_nodes_carry_written_position",
            "test_cs_m6_after_separator",
            "test_tiered_grouped_subcommand_help",
            "test_retired_spellings",
            "test_cs_m6_render_argv",
            "test_suite_lists_agree"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"

task e2e, "Run the end-to-end tests (real shells in a pseudo-terminal)":
  for t in ["e2e_cs_m5_real_shell_completion"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"
