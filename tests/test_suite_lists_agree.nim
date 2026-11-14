## test_suite_lists_agree: the three places that name the test suite name the
## same files.
##
## The suite is run three ways: ``just test`` (the ``tests`` variable of the
## ``Justfile``), ``nimble test`` (the ``test`` task of ``clispec.nimble``)
## and the build graph of ``repro.nim`` (its ``clispecTests`` list, one
## build and one run per entry). Each list is written by hand, so a new test
## module added to one of them and not the others silently drops out of a
## runner. This test reads the files as text and requires every list to name
## exactly the ``tests/test_*.nim`` modules on disk.
##
## The end-to-end tests (``tests/e2e_*.nim``, real shells in a
## pseudo-terminal) are a separate suite run the same three ways: the
## Justfile's ``e2e-tests`` (``just e2e``), the nimble ``e2e`` task and the
## ``clispecTests`` entries of ``repro.nim`` marked ``realShells: true``
## (collected into ``e2e``). Those three must name exactly the
## ``tests/e2e_*.nim`` modules on disk, and no other entry may be marked
## ``realShells``.
##
## It also checks the fact ``repro.nim`` records per test that the other
## runners do not need: ``runsCompiler`` must be set exactly for the modules
## that run the Nim compiler while they execute (they call
## ``getCurrentCompilerExe()``).
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

proc e2eOnDisk(): seq[string] =
  for path in walkFiles(testsDir / "e2e_*.nim"):
    result.add(path.extractFilename.changeFileExt(""))
  result.sort()

proc justfileList(variable: string): seq[string] =
  ## The ``<variable> := "..."`` variable of the Justfile.
  for line in readFile(repoDir / "Justfile").splitLines():
    if line.startsWith(variable & " :="):
      let literals = quotedStrings(line)
      if literals.len == 1:
        return literals[0].splitWhitespace()

proc justfileTests(): seq[string] =
  justfileList("tests")

proc nimbleList(task, prefix: string): seq[string] =
  ## The array the nimble task ``task`` loops over.
  let body = between(readFile(repoDir / "clispec.nimble"),
    "task " & task & ",", "exec")
  for literal in quotedStrings(body):
    if literal.startsWith(prefix):
      result.add(literal)

proc nimbleTests(): seq[string] =
  nimbleList("test", "test_")

type ReproTest = object
  stem: string
  runsCompiler: bool
  realShells: bool

proc reproTests(): seq[ReproTest] =
  ## The ``clispecTests`` list of repro.nim: one ``ClispecTest(...)`` per
  ## module, with its ``runsCompiler`` / ``realShells`` flags.
  let body = between(readFile(repoDir / "repro.nim"),
    "const clispecTests = [", "\n]")
  for entry in body.split("ClispecTest(")[1 .. ^1]:
    let literals = quotedStrings(entry)
    if literals.len == 0 or not literals[0].startsWith("tests/"):
      continue
    result.add(ReproTest(
      stem: literals[0].extractFilename.changeFileExt(""),
      runsCompiler: "runsCompiler: true" in entry,
      realShells: "realShells: true" in entry))

proc codeLines(text: string): seq[string] =
  ## The lines of ``text`` that are not comments, stripped.
  for line in text.splitLines():
    let code = line.strip()
    if code.len > 0 and not code.startsWith("#"):
      result.add(code)

const
  # Spelled in two pieces so this file's own text does not match it.
  compilerCall = "getCurrentCompilerExe" & "()"

proc runsCompiler(text: string): bool =
  for code in codeLines(text):
    if compilerCall in code:
      return true

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
      if not t.realShells:
        listed.add(t.stem)
    check listed.len > 0
    check duplicates(listed).len == 0
    check sortedList(listed) == onDisk

  test "the end-to-end suite is the same in all three runners":
    let e2e = e2eOnDisk()
    check e2e.len > 0
    let just = justfileList("e2e-tests")
    check duplicates(just).len == 0
    check sortedList(just) == e2e
    let nimble = nimbleList("e2e", "e2e_")
    check duplicates(nimble).len == 0
    check sortedList(nimble) == e2e
    var repro: seq[string] = @[]
    for t in reproTests():
      if t.realShells:
        repro.add(t.stem)
    check duplicates(repro).len == 0
    check sortedList(repro) == e2e

  test "repro.nim declares the compiler for exactly the tests that run it":
    for t in reproTests():
      let runs = runsCompiler(readFile(testsDir / (t.stem & ".nim")))
      checkpoint(t.stem & ": runs the compiler = " & $runs &
        ", runsCompiler = " & $t.runsCompiler)
      check runs == t.runsCompiler
