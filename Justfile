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
##   * `lint` is `nim check` over the umbrella module and every test module,
##     then the cross-OS check: `nim check --os:windows` and `--os:macosx`
##     over the umbrella and every module under `src/clispec/`. Code behind
##     `when defined(windows)` or `when defined(macosx)` is not compiled on
##     the host, so without it a module that does not compile for another
##     platform passes every local check and fails first in a consumer's
##     build. `nim check` resolves names and types for the target without a
##     C compiler or the target's headers (an `importc` binding is not looked
##     up until the C compiler sees it, so this does not cover those). The
##     standard library's types differ between Nim versions on Windows
##     (`FileHandle` is `cint` in Nim 2.2 and `int` in later versions), so
##     the check also runs with every `nim` named in `CLISPEC_EXTRA_NIM`
##     (space-separated paths). The dev shell sets it to the metacraft-labs
##     Nim fork (2.3.1); outside the shell the recipe refuses to run without
##     it rather than check with 2.2 alone.
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
tests := "test_dsl_model test_extension test_cs_m2_model_round_trip test_cs_m2_invalid_declarations_fail_to_compile test_cs_m3_parser_accepts_declared_forms test_cs_m3_parser_error_taxonomy test_cs_m3_help_matches_model test_readme_examples test_cs_m4b_convention_conversion test_cs_m4b_per_source_convention test_cs_m4b_override_precedence test_cs_m5_engine_completes_every_level test_cs_m5_internal_parameters_work_unlisted test_cs_m9_clispec_has_no_serialization_dependency test_cs_m10_help_layout test_cs_m10_parse_compat_rules test_cs_m10_confutils_compat_record test_cs_m10_command_word_rules test_cs_m10_dash_and_letter_rules test_cs_m5b_help_matches_design test_cs_m5b_no_color_and_not_a_terminal test_cs_m5c_colour_detection test_cs_m5c_styled_goldens test_cs_m5c_compile_time_knobs_shrink test_type_check_nodes_carry_written_position test_cs_m6_after_separator test_tiered_grouped_subcommand_help test_retired_spellings test_suite_lists_agree"
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
    # The cross-OS check (see the header). `nim check` exits non-zero on an
    # error, and `pipefail` carries that through `tee`.
    if [[ -z "${CLISPEC_EXTRA_NIM:-}" ]]; then
      echo "lint: CLISPEC_EXTRA_NIM is not set, so the cross-OS check would" \
        "run with $(nim --version | head -1) only and miss what a newer" \
        "standard library rejects; run inside the dev shell (nix develop)," \
        "which sets it, or set it to a newer nim" >&2
      exit 1
    fi
    # One nimcache per compiler: two Nim versions do not share one.
    n=0
    for compiler in nim ${CLISPEC_EXTRA_NIM:-}; do
      n=$((n + 1))
      for os in windows macosx; do
        for m in src/clispec.nim src/clispec/*.nim; do
          echo "lint: ${compiler} check --os:${os} ${m}" | tee -a test-logs/lint.log
          "${compiler}" check {{nim-flags}} --os:${os} \
            --nimcache:{{nimcache}}/src/cross${n}_${os}_check {{src-paths}} \
            "${m}" 2>&1 | tee -a test-logs/lint.log
        done
      done
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
