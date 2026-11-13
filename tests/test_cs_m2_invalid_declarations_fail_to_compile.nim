## test_cs_m2_invalid_declarations_fail_to_compile: every class of invalid
## declaration is a compile error whose message names the parameter (or,
## for a command-level mistake, the command).
##
## Each case is a fixture file under ``tests/fixtures/cs_m2_invalid/``: a
## small program whose ``cli:`` description has exactly one line marked
## ``# clispec-invalid``, and whose header states the expected message
## (``## expect: <text>``). For each fixture the test runs the real compiler
## (``nim check``, the same compiler that built this test):
##
## 1. on the fixture as written, and requires a non-zero exit and the
##    expected text in the compiler's output;
## 2. on a copy with the marked line removed, and requires a zero exit. This
##    is the vacuity guard: it shows the error came from that line, not from
##    something else in the fixture being malformed.
##
## Invoking the compiler is the only way to observe a compile error together
## with its message (``compiles()`` only answers yes or no), so no part of
## this test is mocked.

import std/[os, osproc, strutils, tempfiles, unittest]

const
  testsDir = currentSourcePath().parentDir()
  fixturesDir = testsDir / "fixtures" / "cs_m2_invalid"
  srcDir = testsDir.parentDir() / "src"
  invalidMarker = "# clispec-invalid"
  expectPrefix = "## expect: "

proc compilerExe(): string =
  ## The compiler that built this test, so the fixtures are checked by the
  ## same Nim.
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

proc nimCheck(file, nimcache: string): tuple[output: string, exitCode: int] =
  ## ``nim check`` on ``file``, isolated from the user's and the checkout's
  ## configuration, with ``src/`` on the path.
  execCmdEx(quoteShellCommand([compilerExe(), "check", "--hints:off",
    "--skipParentCfg", "--skipUserCfg", "--path:" & srcDir,
    "--nimcache:" & nimcache, file]))

proc expectedMessage(text: string): string =
  for line in text.splitLines():
    if line.startsWith(expectPrefix):
      return line[expectPrefix.len .. ^1]
  ""

proc withoutInvalidLine(text: string): tuple[text: string, removed: int] =
  var kept: seq[string] = @[]
  for line in text.splitLines():
    if line.strip().endsWith(invalidMarker):
      inc result.removed
    else:
      kept.add(line)
  result.text = kept.join("\n")

suite "test_cs_m2_invalid_declarations_fail_to_compile":

  var fixtures: seq[string] = @[]
  for path in walkFiles(fixturesDir / "*.nim"):
    fixtures.add(path)

  test "the fixture set is not empty":
    check fixtures.len >= 20

  let scratch = createTempDir("clispec_cs_m2_", "")
  for fixture in fixtures:
    let caseName = fixture.splitFile().name
    test caseName:
      let text = readFile(fixture)
      let expected = expectedMessage(text)
      let valid = withoutInvalidLine(text)
      check expected.len > 0
      check valid.removed == 1

      let invalidRun = nimCheck(fixture, scratch / caseName & "_invalid")
      check invalidRun.exitCode != 0
      check expected in invalidRun.output
      if invalidRun.exitCode == 0 or expected notin invalidRun.output:
        echo "  expected: ", expected
        echo "  compiler output:\n", invalidRun.output

      let validFile = scratch / caseName & ".nim"
      writeFile(validFile, valid.text)
      let validRun = nimCheck(validFile, scratch / caseName & "_valid")
      check validRun.exitCode == 0
      if validRun.exitCode != 0:
        echo "  the fixture without its invalid line failed:\n",
          validRun.output
  removeDir(scratch)
