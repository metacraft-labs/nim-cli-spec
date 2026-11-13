## test_readme_examples: every ```nim block of README.md compiles and runs.
##
## The README is the library's public documentation, so its examples must be
## real programs: each block is written to a temporary file and built and run
## with the compiler that built this test (``nim c -r``, isolated from user
## and parent configuration, with ``src/`` on the path). The examples carry
## their own ``assert``s, which run here. Invoking the compiler is the only
## way to check that documentation code compiles, so nothing is mocked.

import std/[os, osproc, strutils, tempfiles, unittest]

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()
  srcDir = repoDir / "src"

proc compilerExe(): string =
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

proc nimBlocks(markdown: string): seq[string] =
  ## The contents of every fenced block opened with ```nim.
  var inside = false
  var current: seq[string] = @[]
  for line in markdown.splitLines():
    if not inside and line.strip() == "```nim":
      inside = true
      current = @[]
    elif inside and line.strip() == "```":
      inside = false
      result.add(current.join("\n") & "\n")
    elif inside:
      current.add(line)

suite "test_readme_examples":

  test "every nim block of the README compiles and runs":
    let blocks = nimBlocks(readFile(repoDir / "README.md"))
    check blocks.len >= 4
    let dir = createTempDir("clispec_readme_", "")
    defer: removeDir(dir)
    for i, code in blocks:
      checkpoint("README block " & $(i + 1) & ":\n" & code)
      let file = dir / ("readme_example_" & $(i + 1) & ".nim")
      writeFile(file, code)
      let (output, exitCode) = execCmdEx(quoteShellCommand([compilerExe(),
        "c", "-r", "--hints:off", "--skipParentCfg", "--skipUserCfg",
        "--path:" & srcDir, "--nimcache:" & (dir / ("cache_" & $(i + 1))),
        "-o:" & (dir / ("readme_example_" & $(i + 1))), file]))
      checkpoint(output)
      check exitCode == 0
