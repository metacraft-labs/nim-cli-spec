## Reprobuild project file for nim-cli-spec (the ``clispec`` package).
##
## A Nim leaf library. The library itself needs nothing beyond the standard
## library; only its optional TOML adapter (``src/clispec/toml_source.nim``)
## and the tests that drive it need nim-toml-serialization and the four
## libraries it builds on.
##
## * ``uses:`` declares the tool floor (``nim``, the C back-end ``nim c``
##   shells out to, the Justfile's command closure, and what the pinned
##   source fetches below run), mirroring ``clispec.nimble``'s
##   ``requires "nim >= 2.0.0"``.
## * ``library clispec`` exports ``src/`` (the umbrella ``src/clispec.nim``
##   and its submodules under ``src/clispec/``), so a consumer that declares
##   ``uses: "nim-cli-spec"`` gets it on its ``nim c --path:``.
## * Every test module the Justfile and ``clispec.nimble`` run is listed in
##   ``clispecTests`` and gets a BUILD edge (``buildNimUnittest.build``)
##   compiling ``build/test-bin/<stem>`` and an EXECUTE edge
##   (``edge.testBinary.run``) running it. The BUILD halves collect into
##   ``test-builds`` and the EXECUTE halves into ``test``, so
##   ``repro build test`` is the same suite as ``just test``.
##   ``tests/test_suite_lists_agree.nim`` fails when this list, the
##   Justfile's and the nimble task's stop naming the same files.
## * The TOML adapter's five dependency libraries are third-party source
##   trees, not workspace packages, so each is a pinned-archive fetch edge
##   (``repro_dsl_stdlib/operations/pinned_fetch``): the GitHub archive of
##   the revision ``flake.nix`` and ``clispec.nimble`` pin, refused unless it
##   hashes to the SHA-256 recorded here, unpacked under
##   ``.repro/clispec-format-sources/``. Only the edges of the tests that
##   need them order after those fetches and get them on ``--path:``; the
##   README test, which compiles the README's examples itself, also gets
##   them as ``CLISPEC_FORMAT_PATHS``, the variable the dev shell exports
##   for the same purpose.
##
## ``defaultToolProvisioning "path"``: this repository's dev shell
## (``flake.nix``) puts ``nim``, the C compiler, ``just``, ``bash`` and
## coreutils on ``PATH``, so the PATH resolver is the right local default.

# ``/`` for the fetch directories.
import std/os

import repro_project_dsl
# ``useFlakeDevShell()`` in ``devEnv:``.
import repro_dsl_stdlib/foreign_env

# ``buildNimUnittest.build(...)`` for the BUILD edges and the
# ``edge.testBinary.run(...)`` dispatch for the EXECUTE edges.
import ct_test_nim_unittest

# ``PinnedArchive`` and ``emitPinnedFetchAction`` for the format sources: a
# download pinned by URL and SHA-256, as one non-cacheable edge per archive.
import repro_dsl_stdlib/operations/pinned_fetch

type
  ClispecTest = object
    ## One test module. ``needsToml``: it imports the TOML adapter (directly
    ## or through ``tests/cs_m4_fixture.nim``), or compiles code that does,
    ## so its edges need the format sources. ``runsCompiler``: it runs the
    ## Nim compiler (and through ``nim c``, the C compiler) while it
    ## executes, so its EXECUTE edge declares those tools too.
    source: string
    needsToml: bool
    runsCompiler: bool

const clispecTests = [
  ClispecTest(source: "tests/test_dsl_model.nim"),
  ClispecTest(source: "tests/test_extension.nim"),
  ClispecTest(source: "tests/test_cs_m2_model_round_trip.nim"),
  ClispecTest(source: "tests/test_cs_m2_invalid_declarations_fail_to_compile.nim",
    runsCompiler: true),
  ClispecTest(source: "tests/test_cs_m3_parser_accepts_declared_forms.nim"),
  ClispecTest(source: "tests/test_cs_m3_parser_error_taxonomy.nim"),
  ClispecTest(source: "tests/test_cs_m3_help_matches_model.nim"),
  ClispecTest(source: "tests/test_readme_examples.nim",
    needsToml: true, runsCompiler: true),
  ClispecTest(source: "tests/test_cs_m4_precedence_and_origins.nim",
    needsToml: true),
  ClispecTest(source: "tests/test_cs_m4_merge_rules.nim", needsToml: true),
  ClispecTest(source: "tests/test_cs_m4_enforced_value_explained.nim",
    needsToml: true),
  ClispecTest(source: "tests/test_cs_m4_default_never_overrides_file.nim",
    needsToml: true),
  ClispecTest(source: "tests/test_cs_m4_unknown_key_rejected.nim",
    needsToml: true),
  ClispecTest(source: "tests/test_cs_m4b_convention_conversion.nim"),
  ClispecTest(source: "tests/test_cs_m4b_per_source_convention.nim",
    needsToml: true),
  ClispecTest(source: "tests/test_cs_m4b_override_precedence.nim",
    needsToml: true),
  ClispecTest(source: "tests/test_suite_lists_agree.nim"),
]

const
  FormatSourcesDir = ".repro/clispec-format-sources"
    ## Where the format sources are unpacked, one directory per archive.
    ## Under ``.repro/``, which ``.gitignore`` already excludes.
  FormatSources = [
    ## The TOML adapter's dependencies, at the revisions ``flake.nix``'s
    ## ``nim-*-src`` inputs and ``clispec.nimble``'s ``taskRequires`` pin
    ## (a set known to work together: toml-serialization v0.2.18 and the
    ## serialization, faststreams, stew and results revisions whose sources
    ## match it). Each repository's root is its import root. The SHA-256 is
    ## that of GitHub's archive of the revision; its unpacked tree was
    ## checked identical to the flake input's.
    PinnedArchive(name: "nim-toml-serialization",
      url: "https://github.com/status-im/nim-toml-serialization/archive/" &
        "b5b387e6fb2a7cc75d54a269b07cc6218361bd46.tar.gz",
      sha256: "992afe9fd71cb5ee75ac6ab7dcdeadb60101c359f0f368095915109941979258",
      kind: pakTarball, stripComponents: 1),
    PinnedArchive(name: "nim-serialization",
      url: "https://github.com/status-im/nim-serialization/archive/" &
        "1790d8a931fce125d6722f7ee8432ee8c054d297.tar.gz",
      sha256: "7f0280fd8ff19d11d1f25582d6537402a0c490fec873648e174f76e505029c34",
      kind: pakTarball, stripComponents: 1),
    PinnedArchive(name: "nim-faststreams",
      url: "https://github.com/status-im/nim-faststreams/archive/" &
        "50889cd16ec8771106cdd0eeea460039e8571e06.tar.gz",
      sha256: "67a173f1e5a6cabd59365d07926530e244af3ed86b3897acc1a48f97fcccf0f1",
      kind: pakTarball, stripComponents: 1),
    PinnedArchive(name: "nim-stew",
      url: "https://github.com/status-im/nim-stew/archive/" &
        "30dadcd14b5ec1631935d9037213ece6871cc11a.tar.gz",
      sha256: "26823283ec38579bf63d23ddc4eba36ec7132d927ca7943fb7df8cbde0362c65",
      kind: pakTarball, stripComponents: 1),
    PinnedArchive(name: "nim-results",
      url: "https://github.com/arnetheduck/nim-results/archive/" &
        "55b41b285def7b7b98dd5b9669f352d1fdc35c2b.tar.gz",
      sha256: "622746e7f5bcd0efc30f53d9b9eea19585422d9b1768d52820a94eff58bdc530",
      kind: pakTarball, stripComponents: 1),
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
    # What the pinned source fetches run (``operations/pinned_fetch``): an
    # undeclared tool is not on the edge's PATH.
    "curl"
    "sha256sum"
    "tar"
    "gzip"
    "mv"
    "rm"

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

    let root = activeProviderProjectRoot()
    # One fetch edge per format source; the TOML tests order after all five.
    var formatFetches: seq[BuildActionDef] = @[]
    var formatPaths: seq[string] = @[]
    for archive in FormatSources:
      let dir = root / FormatSourcesDir / archive.name
      formatFetches.add(emitPinnedFetchAction(root, "clispec", archive, dir))
      formatPaths.add(dir)
    var formatPathFlags = ""
    for dir in formatPaths:
      if formatPathFlags.len > 0:
        formatPathFlags.add(' ')
      formatPathFlags.add("--path:" & dir)

    let cTool = when defined(macosx): "clang" else: "gcc"

    for spec in clispecTests:
      let stem = stemOf(spec.source)
      var paths = @["src"]
      var after: seq[BuildActionDef] = @[]
      var executeEnv: seq[(string, string)] = @[]
      if spec.needsToml:
        paths.add(formatPaths)
        after = formatFetches
      if spec.needsToml and spec.runsCompiler:
        # A test that compiles TOML-using code itself (the README test)
        # passes these to the ``nim c`` it runs on each example, exactly as
        # the dev shell's ``CLISPEC_FORMAT_PATHS``. The other TOML tests
        # never read the variable, so their EXECUTE edges do not carry it.
        executeEnv.add(("CLISPEC_FORMAT_PATHS", formatPathFlags))
      let edge = buildNimUnittest.build(
        source = spec.source,
        binary = "build/test-bin/" & stem,
        paths = paths,
        after = after,
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
      testExecuteActions.add(run)

    discard collect("test", testExecuteActions)
    discard collect("test-builds", testBuildActions)
