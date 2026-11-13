## Justfile — nim-cli-spec (clispec).
##
## Recipes:
##   * `build` compiles every test module without running it.
##   * `test` runs the test suite (`tests/test_*.nim`), the same files
##     `nimble test` runs.
##   * `lint` is `nim check` over the umbrella module and every test module.
##   * `format` runs `nimpretty` when it is available.
##
## The TOML adapter (`src/clispec/toml_source.nim`) and the tests that use it
## need nim-toml-serialization and its dependencies on the path. The dev shell
## exports them as `CLISPEC_FORMAT_PATHS` (`--path:` flags); the recipes pass
## that to every test compile. Without it those tests do not compile.
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
tests := "test_dsl_model test_extension test_cs_m2_model_round_trip test_cs_m2_invalid_declarations_fail_to_compile test_cs_m3_parser_accepts_declared_forms test_cs_m3_parser_error_taxonomy test_cs_m3_help_matches_model test_readme_examples test_cs_m4_precedence_and_origins test_cs_m4_merge_rules test_cs_m4_enforced_value_explained test_cs_m4_default_never_overrides_file test_cs_m4_unknown_key_rejected"

# Compile every test module without running it.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    : > test-logs/build.log
    for t in {{tests}}; do
      nim c {{nim-flags}} --nimcache:{{nimcache}}/tests/${t}_d {{src-paths}} \
        ${CLISPEC_FORMAT_PATHS:-} -o:test-logs/${t} tests/${t}.nim 2>&1 | tee -a test-logs/build.log
    done

# Run the test suite.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    : > test-logs/test.log
    for t in {{tests}}; do
      nim c -r {{nim-flags}} --nimcache:{{nimcache}}/tests/${t}_d {{src-paths}} \
        ${CLISPEC_FORMAT_PATHS:-} -o:test-logs/${t} tests/${t}.nim 2>&1 | tee -a test-logs/test.log
    done

# `nim check` over the umbrella and every test module.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    nim check {{nim-flags}} --nimcache:{{nimcache}}/src/clispec_check {{src-paths}} \
      src/clispec.nim 2>&1 | tee test-logs/lint.log
    nim check {{nim-flags}} --nimcache:{{nimcache}}/src/clispec/toml_source_check {{src-paths}} \
      ${CLISPEC_FORMAT_PATHS:-} src/clispec/toml_source.nim 2>&1 | tee -a test-logs/lint.log
    for t in {{tests}}; do
      nim check {{nim-flags}} --nimcache:{{nimcache}}/tests/${t}_check {{src-paths}} \
        ${CLISPEC_FORMAT_PATHS:-} tests/${t}.nim 2>&1 | tee -a test-logs/lint.log
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

# Set the package version (version.txt).
bump-version version:
    printf '%s\n' "{{version}}" > version.txt

# Remove test logs, binaries and the nimcache.
clean:
    rm -rf test-logs .nimcache
