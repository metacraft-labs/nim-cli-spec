## Justfile — nim-cli-spec (clispec).
##
## Recipes:
##   * `build` compiles every test module without running it.
##   * `test` runs the test suite (`tests/test_*.nim`), the same files
##     `nimble test` runs.
##   * `lint` is `nim check` over the umbrella module and every test module.
##   * `format` runs `nimpretty` when it is available.
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
tests := "test_dsl_model test_extension test_cs_m2_model_round_trip test_cs_m2_invalid_declarations_fail_to_compile test_cs_m3_parser_accepts_declared_forms test_cs_m3_parser_error_taxonomy test_cs_m3_help_matches_model test_readme_examples"

# Compile every test module without running it.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    : > test-logs/build.log
    for t in {{tests}}; do
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

# `nim check` over the umbrella and every test module.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    nim check {{nim-flags}} --nimcache:{{nimcache}}/src/clispec_check {{src-paths}} \
      src/clispec.nim 2>&1 | tee test-logs/lint.log
    for t in {{tests}}; do
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

# Set the package version (version.txt).
bump-version version:
    printf '%s\n' "{{version}}" > version.txt

# Remove test logs, binaries and the nimcache.
clean:
    rm -rf test-logs .nimcache
