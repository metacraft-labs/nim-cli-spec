## Reprobuild project file for nim-cli-spec (the ``clispec`` package).
##
## A Nim leaf library: it and its tests need nothing beyond the standard
## library. (Configuration files, and the serialization libraries that read
## them, are confutils', which is instantiated over a clispec description.)
##
## * ``uses:`` declares the tool floor (``nim``, the C back-end ``nim c``
##   shells out to and the Justfile's command closure), mirroring
##   ``clispec.nimble``'s ``requires "nim >= 2.0.0"``.
## * ``library clispec`` exports ``src/`` (the umbrella ``src/clispec.nim``
##   and its submodules under ``src/clispec/``), so a consumer that declares
##   ``uses: "nim-cli-spec"`` gets it on its ``nim c --path:``.
## * Every test module the Justfile and ``clispec.nimble`` run is listed in
##   ``clispecTests`` and gets a BUILD edge (``buildNimUnittest.build``)
##   compiling ``build/test-bin/<stem>`` and an EXECUTE edge
##   (``edge.testBinary.run``) running it. The BUILD halves collect into
##   ``test-builds`` and the EXECUTE halves into ``test``, so
##   ``repro build test`` is the same suite as ``just test``. The
##   end-to-end tests (``realShells``) collect into ``e2e`` instead, the
##   suite of ``just e2e``.
##   ``tests/test_suite_lists_agree.nim`` fails when this list, the
##   Justfile's and the nimble task's stop naming the same files.
##
## ``defaultToolProvisioning "path"``: this repository's dev shell
## (``flake.nix``) puts ``nim``, the C compiler, ``just``, ``bash`` and
## coreutils on ``PATH``, so the PATH resolver is the right local default.

import repro_project_dsl
# ``useFlakeDevShell()`` in ``devEnv:``.
import repro_dsl_stdlib/foreign_env

# ``buildNimUnittest.build(...)`` for the BUILD edges and the
# ``edge.testBinary.run(...)`` dispatch for the EXECUTE edges.
import ct_test_nim_unittest

type
  ClispecTest = object
    ## One test module. ``runsCompiler``: it runs the
    ## Nim compiler (and through ``nim c``, the C compiler) while it
    ## executes, so its EXECUTE edge declares those tools too.
    ## ``realShells``: an end-to-end test (``tests/e2e_*.nim``) that drives
    ## the real shells in a pseudo-terminal; its EXECUTE edge declares them
    ## and collects into ``e2e`` rather than ``test``, as the Justfile's
    ## ``e2e`` recipe is kept apart from ``test``.
    source: string
    runsCompiler: bool
    realShells: bool

const clispecTests = [
  ClispecTest(source: "tests/test_dsl_model.nim"),
  ClispecTest(source: "tests/test_extension.nim"),
  ClispecTest(source: "tests/test_cs_m2_model_round_trip.nim"),
  ClispecTest(source: "tests/test_cs_m2_invalid_declarations_fail_to_compile.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_cs_m3_parser_accepts_declared_forms.nim"),
  ClispecTest(source: "tests/test_cs_m3_parser_error_taxonomy.nim"),
  ClispecTest(source: "tests/test_cs_m3_help_matches_model.nim"),
  ClispecTest(source: "tests/test_readme_examples.nim", runsCompiler: true),
  ClispecTest(source: "tests/test_cs_m4b_convention_conversion.nim"),
  ClispecTest(source: "tests/test_cs_m4b_per_source_convention.nim"),
  ClispecTest(source: "tests/test_cs_m4b_override_precedence.nim"),
  ClispecTest(source: "tests/test_cs_m5_engine_completes_every_level.nim"),
  ClispecTest(source: "tests/test_cs_m5_internal_parameters_work_unlisted.nim"),
  ClispecTest(source: "tests/test_cs_m9_clispec_has_no_serialization_dependency.nim"),
  ClispecTest(source: "tests/test_cs_m10_help_layout.nim"),
  ClispecTest(source: "tests/test_cs_m10_parse_compat_rules.nim"),
  ClispecTest(source: "tests/test_cs_m10_confutils_compat_record.nim"),
  ClispecTest(source: "tests/test_cs_m10_command_word_rules.nim"),
  ClispecTest(source: "tests/test_cs_m10_dash_and_letter_rules.nim"),
  ClispecTest(source: "tests/test_cs_m5b_help_matches_design.nim"),
  ClispecTest(source: "tests/test_cs_m5b_no_color_and_not_a_terminal.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_cs_m5c_colour_detection.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_cs_m5c_styled_goldens.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_cs_m5c_compile_time_knobs_shrink.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_type_check_nodes_carry_written_position.nim"),
  ClispecTest(source: "tests/test_cs_m6_after_separator.nim"),
  ClispecTest(source: "tests/test_tiered_grouped_subcommand_help.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_retired_spellings.nim"),
  ClispecTest(source: "tests/test_cs_m6_render_argv.nim"),
  ClispecTest(source: "tests/test_cs_m6b_config_check.nim"),
  ClispecTest(source: "tests/test_cs_m6_splice_unbound.nim"),
  ClispecTest(source: "tests/test_cs_m7_completion_install_locations.nim"),
  ClispecTest(source: "tests/test_exported_load_from_another_module.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_suite_lists_agree.nim"),
  ClispecTest(source: "tests/e2e_cs_m5_real_shell_completion.nim",
    runsCompiler: true, realShells: true),
]

package clispec:
  defaultToolProvisioning "path"

  uses:
    "nim >=2.0"
    when defined(macosx):
      "clang >=14"
    else:
      "gcc >=12"
    # The Justfile's command closure: ``just``, the ``bash`` its ``set
    # shell`` and shebang recipes name, and the coreutils they invoke.
    "just >=1"
    "bash >=4"
    "mkdir"
    "tee"
    # The shells the end-to-end completion test drives (``e2e``); the dev
    # shell provides them. Windows runs only that test's PowerShell leg.
    when not defined(windows):
      "zsh"
      "fish"
      "pwsh"

  library clispec

  devEnv:
    # This repository's own flake dev shell. Windows has no Nix; its
    # toolchain comes from the ``uses:`` floor above.
    when not defined(windows):
      useFlakeDevShell()
    task "bump-version", command = "just bump-version",
      description = "Bump version number (version.txt, clispec.nimble)"

  build:
    var testBuildActions: seq[BuildActionDef] = @[]
    var testExecuteActions: seq[BuildActionDef] = @[]
    var e2eExecuteActions: seq[BuildActionDef] = @[]

    proc stemOf(source: string): string =
      var start = 0
      for i in 0 ..< source.len:
        if source[i] == '/' or source[i] == '\\':
          start = i + 1
      result = source[start .. ^1]
      if result.len > 4 and result[^4 .. ^1] == ".nim":
        result = result[0 ..< ^4]

    let cTool = when defined(macosx): "clang" else: "gcc"

    for spec in clispecTests:
      let stem = stemOf(spec.source)
      var executeEnv: seq[(string, string)] = @[]
      if spec.realShells:
        # As in the dev shell: every shell this edge declares must run, so
        # a shell missing from the action's PATH fails the test instead of
        # being reported as skipped.
        when not defined(windows):
          executeEnv.add(("CLISPEC_E2E_REQUIRE", "bash,zsh,fish,pwsh"))
      let edge = buildNimUnittest.build(
        source = spec.source,
        binary = "build/test-bin/" & stem,
        paths = @["src"],
        extraInputs = @["src", "tests", "config.nims", "clispec.nimble"],
        actionId = "clispec.test_build." & stem)
      appendRegisteredActionToolIdentityRefs(edge.action.id, @[cTool])
      testBuildActions.add(edge.action)
      # The BUILD edge already owns the binary basename as its implicit
      # target name; the explicit ``actionId`` names the execute edge.
      let run = edge.testBinary.run(
        actionId = "clispec.test_execute." & stem,
        registerImplicitName = false,
        extraEnv = executeEnv)
      if spec.runsCompiler:
        appendRegisteredActionToolIdentityRefs(run.id, @["nim", cTool])
      if spec.realShells:
        when not defined(windows):
          appendRegisteredActionToolIdentityRefs(run.id,
            @["bash", "zsh", "fish", "pwsh"])
        e2eExecuteActions.add(run)
      else:
        testExecuteActions.add(run)

    discard collect("test", testExecuteActions)
    discard collect("e2e", e2eExecuteActions)
    discard collect("test-builds", testBuildActions)
