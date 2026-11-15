## Justfile — nim-cli-spec (clispec).
##
## Recipes:
##   * `build` compiles every test module without running it.
##   * `test` runs the test suite (`tests/test_*.nim`), the same files
##     `nimble test` runs and `repro.nim` builds and runs
##     (`tests/test_suite_lists_agree.nim` keeps the three lists equal).
##   * `e2e` runs the end-to-end tests (`tests/e2e_*.nim`): real shells
##     (bash, zsh, fish, PowerShell) driven in a pseudo-terminal, which the
##     dev shell provides. They are kept out of `test` so that suite needs
##     nothing but the compiler; `build` and `lint` cover them too.
##   * `lint` is `nim check` over the umbrella module and every test module.
##   * `format` runs `nimpretty` when it is available.
##
## The tests need nothing but the compiler and the standard library: clispec
## depends on no other package.
##
## Hermetic flags (`--skipParentCfg --skipUserCfg`) are baked into `nim-flags`
## so every invocation gets the same isolation. That switches off
## `config.nims`, so the recipes state `--path:src` themselves and name their
## own `--nimcache:` under `.nimcache/`, in the layout `config.nims` uses for
## everything else: `.nimcache/<module dir>/<module>_<d|r|check>`.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

alias t := test
alias fmt := format

src-paths := "--path:src"
nim-flags := "--skipParentCfg --skipUserCfg --hints:off"
nimcache := ".nimcache"
tests := "test_dsl_model test_extension test_cs_m2_model_round_trip test_cs_m2_invalid_declarations_fail_to_compile test_cs_m3_parser_accepts_declared_forms test_cs_m3_parser_error_taxonomy test_cs_m3_help_matches_model test_readme_examples test_cs_m4b_convention_conversion test_cs_m4b_per_source_convention test_cs_m4b_override_precedence test_cs_m5_engine_completes_every_level test_cs_m5_internal_parameters_work_unlisted test_cs_m9_clispec_has_no_serialization_dependency test_cs_m10_help_layout test_cs_m10_parse_compat_rules test_cs_m10_confutils_compat_record test_cs_m10_command_word_rules test_cs_m10_dash_and_letter_rules test_type_check_nodes_carry_written_position test_suite_lists_agree"
e2e-tests := "e2e_cs_m5_real_shell_completion"

# Compile every test module without running it.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    : > test-logs/build.log
    for t in {{tests}} {{e2e-tests}}; do
      nim c {{nim-flags}} --nimcache:{{nimcache}}/tests/${t}_d {{src-paths}} \
        -o:test-logs/${t} tests/${t}.nim 2>&1 | tee -a test-logs/build.log
    done

# Run the test suite.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    : > test-logs/test.log
    for t in {{tests}}; do
      nim c -r {{nim-flags}} --nimcache:{{nimcache}}/tests/${t}_d {{src-paths}} \
        -o:test-logs/${t} tests/${t}.nim 2>&1 | tee -a test-logs/test.log
    done

# Run the end-to-end tests (real shells in a pseudo-terminal).
e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    : > test-logs/e2e.log
    for t in {{e2e-tests}}; do
      nim c -r {{nim-flags}} --nimcache:{{nimcache}}/tests/${t}_d {{src-paths}} \
        -o:test-logs/${t} tests/${t}.nim 2>&1 | tee -a test-logs/e2e.log
    done

# `nim check` over the umbrella and every test module.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    nim check {{nim-flags}} --nimcache:{{nimcache}}/src/clispec_check {{src-paths}} \
      src/clispec.nim 2>&1 | tee test-logs/lint.log
    for t in {{tests}} {{e2e-tests}}; do
      nim check {{nim-flags}} --nimcache:{{nimcache}}/tests/${t}_check {{src-paths}} \
        tests/${t}.nim 2>&1 | tee -a test-logs/lint.log
    done

# Format the Nim sources in place with nimpretty, when it is installed.
format:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nimpretty >/dev/null 2>&1; then
      find src tests -name '*.nim' -print0 | xargs -0 -n1 nimpretty
    else
      echo "nimpretty not found; skipping" >&2
    fi

# Set the package version (version.txt and clispec.nimble's `version`).
bump-version version:
    printf '%s\n' "{{version}}" > version.txt
    sed -i.bak -e 's/^version       = ".*"$/version       = "{{version}}"/' clispec.nimble
    rm -f clispec.nimble.bak

# Remove test logs, binaries and the nimcache.
clean:
    rm -rf test-logs .nimcache
