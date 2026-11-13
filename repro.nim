## Reprobuild project file for nim-cli-spec (the ``clispec`` package).
##
## A Nim leaf library with no dependencies beyond the standard library:
##
## * ``uses:`` declares the tool floor (``nim``, the C back-end ``nim c``
##   shells out to, and the Justfile's command closure), mirroring
##   ``clispec.nimble``'s ``requires "nim >= 2.0.0"``.
## * ``library clispec`` exports ``src/`` (the umbrella ``src/clispec.nim``
##   and its submodules under ``src/clispec/``), so a consumer that declares
##   ``uses: "nim-cli-spec"`` gets it on its ``nim c --path:``.
## * Each test file under ``tests/`` gets a BUILD edge
##   (``buildNimUnittest.build``) compiling ``build/test-bin/<stem>`` and an
##   EXECUTE edge (``edge.testBinary.run``) running it. The BUILD halves
##   collect into ``test-builds`` and the EXECUTE halves into ``test``.
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

const clispecTests = [
  "tests/test_dsl_model.nim",
  "tests/test_extension.nim",
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

  library clispec

  devEnv:
    # This repository's own flake dev shell. Windows has no Nix; its
    # toolchain comes from the ``uses:`` floor above.
    when not defined(windows):
      useFlakeDevShell()
    task "bump-version", command = "just bump-version",
      description = "Bump version number (version.txt)"

  build:
    var testBuildActions: seq[BuildActionDef] = @[]
    var testExecuteActions: seq[BuildActionDef] = @[]

    proc stemOf(source: string): string =
      var start = 0
      for i in 0 ..< source.len:
        if source[i] == '/' or source[i] == '\\':
          start = i + 1
      result = source[start .. ^1]
      if result.len > 4 and result[^4 .. ^1] == ".nim":
        result = result[0 ..< ^4]

    for source in clispecTests:
      let stem = stemOf(source)
      let edge = buildNimUnittest.build(
        source = source,
        binary = "build/test-bin/" & stem,
        paths = @["src"],
        extraInputs = @["src", "tests", "config.nims", "clispec.nimble"],
        actionId = "clispec.test_build." & stem)
      when defined(macosx):
        appendRegisteredActionToolIdentityRefs(edge.action.id, @["clang"])
      else:
        appendRegisteredActionToolIdentityRefs(edge.action.id, @["gcc"])
      testBuildActions.add(edge.action)
      # The BUILD edge already owns the binary basename as its implicit
      # target name; the explicit ``actionId`` names the execute edge.
      testExecuteActions.add(edge.testBinary.run(
        actionId = "clispec.test_execute." & stem,
        registerImplicitName = false))

    discard collect("test", testExecuteActions)
    discard collect("test-builds", testBuildActions)
