## test_suite_lists_agree: the three places that name the test suite name the
## same files, and the three places that pin the TOML adapter's dependencies
## pin the same revisions.
##
## The suite is run three ways: ``just test`` (the ``tests`` variable of the
## ``Justfile``), ``nimble test`` (the ``test`` task of ``clispec.nimble``)
## and the build graph of ``repro.nim`` (its ``clispecTests`` list, one
## build and one run per entry). Each list is written by hand, so a new test
## module added to one of them and not the others silently drops out of a
## runner. This test reads the files as text and requires every list to name
## exactly the ``tests/test_*.nim`` modules on disk.
##
## It also checks the two facts ``repro.nim`` records per test that the other
## runners do not need:
##
## * ``needsToml`` must be set exactly for the modules that use the TOML
##   adapter (they import ``clispec/toml_source``, read
##   ``CLISPEC_FORMAT_PATHS`` to compile code that may, or import a helper
##   module under ``tests/`` that does one of those). Without it the
##   module does not compile in the graph; with it where it is not needed,
##   the module waits for downloads it never reads.
## * ``runsCompiler`` must be set exactly for the modules that run the Nim
##   compiler while they execute (they call ``getCurrentCompilerExe()``).
##
## And it requires ``flake.nix`` (the dev shell), ``clispec.nimble``
## (``nimble test``) and ``repro.nim`` (the graph's pinned archives) to name
## the same repository at the same revision for each of the TOML adapter's
## dependencies.
##
## The files are read as text rather than evaluated because evaluating them
## needs three different tools; the text forms read here are the ones each
## file is written in, and a reformatting that defeats a reader fails this
## test rather than passing it (every reader requires a non-empty result).
## Nothing is mocked.

import std/[algorithm, os, sets, strutils, unittest]

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()

proc sortedList(items: openArray[string]): seq[string] =
  result = @items
  result.sort()

proc duplicates(items: openArray[string]): seq[string] =
  var seen = initHashSet[string]()
  for item in items:
    if item in seen:
      result.add(item)
    seen.incl(item)

proc between(text, startMarker, endMarker: string): string =
  ## The text after the first ``startMarker`` up to the next ``endMarker``;
  ## empty when either is missing.
  let start = text.find(startMarker)
  if start < 0:
    return ""
  let bodyStart = start + startMarker.len
  let stop = text.find(endMarker, bodyStart)
  if stop < 0:
    return ""
  text[bodyStart ..< stop]

proc quotedStrings(text: string): seq[string] =
  ## Every ``"..."`` literal in ``text``, in order (no escapes are needed by
  ## the lists read here).
  var i = 0
  while i < text.len:
    if text[i] == '"':
      let stop = text.find('"', i + 1)
      if stop < 0:
        break
      result.add(text[i + 1 ..< stop])
      i = stop + 1
    else:
      inc i

proc testsOnDisk(): seq[string] =
  for path in walkFiles(testsDir / "test_*.nim"):
    result.add(path.extractFilename.changeFileExt(""))
  result.sort()

proc justfileTests(): seq[string] =
  ## The ``tests := "..."`` variable of the Justfile.
  for line in readFile(repoDir / "Justfile").splitLines():
    if line.startsWith("tests :="):
      let literals = quotedStrings(line)
      if literals.len == 1:
        return literals[0].splitWhitespace()

proc nimbleTests(): seq[string] =
  ## The array the nimble ``test`` task loops over.
  let body = between(readFile(repoDir / "clispec.nimble"), "task test,", "exec")
  for literal in quotedStrings(body):
    if literal.startsWith("test_"):
      result.add(literal)

type ReproTest = object
  stem: string
  needsToml: bool
  runsCompiler: bool

proc reproTests(): seq[ReproTest] =
  ## The ``clispecTests`` list of repro.nim: one ``ClispecTest(...)`` per
  ## module, with its ``needsToml`` / ``runsCompiler`` flags.
  let body = between(readFile(repoDir / "repro.nim"),
    "const clispecTests = [", "\n]")
  for entry in body.split("ClispecTest(")[1 .. ^1]:
    let literals = quotedStrings(entry)
    if literals.len == 0 or not literals[0].startsWith("tests/"):
      continue
    result.add(ReproTest(
      stem: literals[0].extractFilename.changeFileExt(""),
      needsToml: "needsToml: true" in entry,
      runsCompiler: "runsCompiler: true" in entry))

proc codeLines(text: string): seq[string] =
  ## The lines of ``text`` that are not comments, stripped.
  for line in text.splitLines():
    let code = line.strip()
    if code.len > 0 and not code.startsWith("#"):
      result.add(code)

proc importsModule(text, module: string): bool =
  ## Whether an ``import`` statement of ``text`` names ``module``.
  for code in codeLines(text):
    if code.startsWith("import ") and module in code:
      return true

const
  # Spelled in two pieces so this file's own text does not match them.
  formatPathsRead = "getEnv(\"" & "CLISPEC_FORMAT_PATHS\")"
  compilerCall = "getCurrentCompilerExe" & "()"

proc usesTomlAdapter(text: string): bool =
  ## Imports the adapter, or hands the format sources to code it compiles.
  importsModule(text, "toml_source") or formatPathsRead in text

proc runsCompiler(text: string): bool =
  for code in codeLines(text):
    if compilerCall in code:
      return true

proc tomlHelpers(): seq[string] =
  ## Helper modules under ``tests/`` (not themselves tests) that use the TOML
  ## adapter; a test that imports one needs it too.
  for path in walkFiles(testsDir / "*.nim"):
    let stem = path.extractFilename.changeFileExt("")
    if not stem.startsWith("test_") and usesTomlAdapter(readFile(path)):
      result.add(stem)

proc joinConcatenations(text: string): string =
  ## ``"abc" &\n    "def"`` becomes ``"abcdef"``, so a URL split over two
  ## string literals reads as one.
  var i = 0
  while i < text.len:
    if text[i] == '"':
      var p = i + 1
      while p < text.len and text[p] in Whitespace:
        inc p
      if p < text.len and text[p] == '&':
        inc p
        while p < text.len and text[p] in Whitespace:
          inc p
        if p < text.len and text[p] == '"':
          i = p + 1
          continue
    result.add(text[i])
    inc i

proc githubPins(text: string): seq[string] =
  ## Every ``<owner>/<repository>@<40-hex revision>`` named in ``text`` by a
  ## GitHub reference in any of the three spellings the files use:
  ## ``github:owner/repo/<rev>`` (flake), ``github.com/owner/repo#<rev>``
  ## (nimble) and ``github.com/owner/repo/archive/<rev>`` (archive URL).
  var i = 0
  while true:
    let at = text.find("github", i)
    if at < 0:
      break
    i = at + "github".len
    var p = i
    if text.continuesWith(":", p):
      inc p
    elif text.continuesWith(".com/", p):
      p += ".com/".len
    else:
      continue
    var owner, repo = ""
    while p < text.len and text[p] notin {'/', '"', ' ', '\n'}:
      owner.add(text[p])
      inc p
    if not text.continuesWith("/", p):
      continue
    inc p
    while p < text.len and text[p] notin {'/', '#', '"', ' ', '\n'}:
      repo.add(text[p])
      inc p
    if text.continuesWith("/archive/", p):
      p += "/archive/".len
    elif p < text.len and text[p] in {'/', '#'}:
      inc p
    else:
      continue
    if p + 40 <= text.len and
        text[p ..< p + 40].allCharsInSet({'0' .. '9', 'a' .. 'f'}) and
        (p + 40 == text.len or text[p + 40] notin {'0' .. '9', 'a' .. 'f'}):
      result.add(owner & "/" & repo & "@" & text[p ..< p + 40])
  result.sort()

suite "test_suite_lists_agree":

  let onDisk = testsOnDisk()

  test "there are test modules to compare":
    check onDisk.len > 0
    check "test_suite_lists_agree" in onDisk

  test "the Justfile runs every test module and nothing else":
    let listed = justfileTests()
    check listed.len > 0
    check duplicates(listed).len == 0
    check sortedList(listed) == onDisk

  test "the nimble test task runs every test module and nothing else":
    let listed = nimbleTests()
    check listed.len > 0
    check duplicates(listed).len == 0
    check sortedList(listed) == onDisk

  test "repro.nim builds and runs every test module and nothing else":
    var listed: seq[string] = @[]
    for t in reproTests():
      listed.add(t.stem)
    check listed.len > 0
    check duplicates(listed).len == 0
    check sortedList(listed) == onDisk

  test "repro.nim gives the TOML sources to exactly the tests that use them":
    let helpers = tomlHelpers()
    check helpers.len > 0   # tests/cs_m4_fixture.nim
    for t in reproTests():
      let text = readFile(testsDir / (t.stem & ".nim"))
      var uses = usesTomlAdapter(text)
      for helper in helpers:
        if importsModule(text, helper):
          uses = true
      checkpoint(t.stem & ": uses the TOML adapter = " & $uses &
        ", needsToml = " & $t.needsToml)
      check uses == t.needsToml

  test "repro.nim declares the compiler for exactly the tests that run it":
    for t in reproTests():
      let runs = runsCompiler(readFile(testsDir / (t.stem & ".nim")))
      checkpoint(t.stem & ": runs the compiler = " & $runs &
        ", runsCompiler = " & $t.runsCompiler)
      check runs == t.runsCompiler

  test "flake.nix, clispec.nimble and repro.nim pin the same revisions":
    let flake = githubPins(between(readFile(repoDir / "flake.nix"),
      "nim-toml-serialization-src", "outputs"))
    let nimble = githubPins(readFile(repoDir / "clispec.nimble"))
    let repro = githubPins(joinConcatenations(between(
      readFile(repoDir / "repro.nim"), "FormatSources = [", "\n  ]")))
    checkpoint("flake.nix: " & $flake)
    checkpoint("clispec.nimble: " & $nimble)
    checkpoint("repro.nim: " & $repro)
    check flake.len == 5
    check nimble == flake
    check repro == flake
