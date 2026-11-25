## test_readme_examples: every ```nim block of README.md compiles and runs.
##
## The README is the library's public documentation, so its examples must be
## real programs: each block is written to a temporary file and built and run
## with the compiler that built this test (``nim c -r``, isolated from user
## and parent configuration, with ``src/`` on the path and nothing else:
## clispec depends on no other package). The examples carry their own
## ``assert``s, which run here. Invoking the compiler is the only
## way to check that documentation code compiles, so nothing is mocked.
##
## A block that cannot compile with clispec alone (an excerpt of a program
## that also needs another project, quoted as it really is) is preceded by
## the marker line
##
##   <!-- readme-check: skip: <why it cannot be compiled here> -->
##
## with only blank lines between the marker and the block's fence. The marker
## is an HTML comment, so a reader of the rendered README does not see it.
## The check prints every skipped block with its line and reason, and counts
## them; a marker without a reason, one that no ```nim block follows, and
## one not on a line of its own outside any block fail the check (the count
## of markers written must equal the count of blocks skipped), so a marker
## cannot outlive its block, be silently ignored, or hide a block silently.
## Any fence whose info string starts with the word ``nim`` opens a block
## (```` ```nim ```` or ```` ```nim extra words ````), so a block cannot
## escape the check by its fence either. The control test removes the
## markers and shows the check then compiles the marked blocks, and that
## they do not compile.

import std/[os, osproc, strutils, tempfiles, unittest]

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()
  srcDir = repoDir / "src"
  markerPrefix = "<!-- readme-check: skip:"
  markerSuffix = "-->"

type
  ReadmeBlock = object
    code: string        ## the block's contents, one trailing newline
    line: int           ## 1-based line of the opening fence
    skipReason: string  ## the marker's reason; empty when the block is checked

proc compilerExe(): string =
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

proc isNimFence(line: string): bool =
  ## Whether ``line`` opens a fenced block of Nim code: an info string whose
  ## first word is ``nim``.
  let s = line.strip()
  if not s.startsWith("```"):
    return false
  let info = s[3 .. ^1].strip()
  info.len > 0 and info.splitWhitespace()[0] == "nim"

proc nimBlocks(markdown: string): seq[ReadmeBlock] =
  ## The contents of every fenced Nim block, each with the reason of the skip
  ## marker that precedes it, if any. Raises ``ValueError`` for a marker with
  ## no reason, a marker that something other than blank lines and a Nim
  ## block follows, a block that is never closed, and a marker that is not
  ## on a line of its own outside any block.
  var inside = false
  var current: seq[string] = @[]
  var pending = ""        # the reason of a marker not yet bound to a block
  var pendingLine = 0
  var opened = 0
  var reason = ""
  let lines = markdown.splitLines()
  for i, line in lines:
    let s = line.strip()
    if inside:
      if s == "```":
        inside = false
        result.add(ReadmeBlock(code: current.join("\n") & "\n", line: opened,
          skipReason: reason))
      else:
        current.add(line)
    elif s.startsWith(markerPrefix):
      if pending.len > 0:
        raise newException(ValueError, "README.md:" & $pendingLine &
          ": skip marker not followed by a ```nim block")
      if not s.endsWith(markerSuffix):
        raise newException(ValueError, "README.md:" & $(i + 1) &
          ": skip marker does not end with " & markerSuffix)
      pending = s[markerPrefix.len ..< s.len - markerSuffix.len].strip()
      pendingLine = i + 1
      if pending.len == 0:
        raise newException(ValueError, "README.md:" & $(i + 1) &
          ": skip marker gives no reason")
    elif isNimFence(line):
      inside = true
      current = @[]
      opened = i + 1
      reason = pending
      pending = ""
    elif s.len > 0 and pending.len > 0:
      raise newException(ValueError, "README.md:" & $pendingLine &
        ": skip marker not followed by a ```nim block")
  if inside:
    raise newException(ValueError, "README.md:" & $opened &
      ": ```nim block is never closed")
  if pending.len > 0:
    raise newException(ValueError, "README.md:" & $pendingLine &
      ": skip marker not followed by a ```nim block")
  # A marker the loop above did not read as one (written after other text on
  # its line, or inside a block) would otherwise be ignored: every
  # occurrence of the prefix must be a marker bound to a block.
  var bound = 0
  for b in result:
    if b.skipReason.len > 0:
      inc bound
  if markdown.count(markerPrefix) != bound:
    raise newException(ValueError, "README.md: " &
      $markdown.count(markerPrefix) & " skip markers written but " & $bound &
      " bound to a block; a marker must be on a line of its own, outside " &
      "any block")

proc withoutMarkers(markdown: string): string =
  ## ``markdown`` with every skip marker line removed.
  var kept: seq[string] = @[]
  for line in markdown.splitLines():
    if not line.strip().startsWith(markerPrefix):
      kept.add(line)
  kept.join("\n")

proc compileAndRun(dir: string; index: int; code: string):
    tuple[output: string, exitCode: int] =
  ## Builds and runs one block in ``dir`` with clispec alone on the path.
  let file = dir / ("readme_example_" & $index & ".nim")
  writeFile(file, code)
  var args = @[compilerExe(), "c", "-r", "--hints:off",
    "--skipParentCfg", "--skipUserCfg", "--path:" & srcDir]
  args.add(["--nimcache:" & (dir / ("cache_" & $index)),
    "-o:" & (dir / ("readme_example_" & $index)), file])
  execCmdEx(quoteShellCommand(args))

suite "test_readme_examples":

  test "every nim block of the README compiles and runs":
    let readme = readFile(repoDir / "README.md")
    let blocks = nimBlocks(readme)
    let dir = createTempDir("clispec_readme_", "")
    defer: removeDir(dir)
    var checked, skipped = 0
    for i, b in blocks:
      if b.skipReason.len > 0:
        inc skipped
        echo "README block ", i + 1, " (README.md:", b.line, "): skipped: ",
          b.skipReason
        continue
      checkpoint("README block " & $(i + 1) & " (README.md:" & $b.line &
        "):\n" & b.code)
      let (output, exitCode) = compileAndRun(dir, i + 1, b.code)
      checkpoint(output)
      check exitCode == 0
      inc checked
    echo "README: ", checked, " nim blocks checked (any failure is shown ",
      "above), ", skipped, " skipped"
    check checked >= 4
    # Every marker was bound to a block (nimBlocks raises otherwise), so the
    # skipped count is the marker count; checked again here, where the
    # README's own count is printed.
    check skipped == readme.count(markerPrefix)

  test "control: without its marker a skipped block is compiled, and fails":
    let readme = readFile(repoDir / "README.md")
    let marked = nimBlocks(readme)
    let unmarked = nimBlocks(withoutMarkers(readme))
    # The same blocks, none of them skipped any more.
    check unmarked.len == marked.len
    var tried = 0
    let dir = createTempDir("clispec_readme_control_", "")
    defer: removeDir(dir)
    for i in 0 ..< min(marked.len, unmarked.len):
      check unmarked[i].skipReason.len == 0
      check unmarked[i].code == marked[i].code
      if marked[i].skipReason.len == 0:
        continue
      inc tried
      let (output, exitCode) = compileAndRun(dir, i + 1, unmarked[i].code)
      let firstError = block:
        var e = ""
        for line in output.splitLines():
          if "Error:" in line:
            e = line
            break
        e
      echo "README block ", i + 1, " without its marker: exit ", exitCode,
        ": ", firstError
      checkpoint(output)
      # It does not compile with clispec alone, which is the marker's reason.
      check exitCode != 0
    check tried > 0

  test "skip markers bind to the next nim block, or fail the check":
    let ok = nimBlocks("text\n\n" & markerPrefix & " needs X " & markerSuffix &
      "\n\n```nim\necho 1\n```\n\n```nim extra\necho 2\n```\n")
    check ok.len == 2
    check ok[0].skipReason == "needs X" and ok[0].line == 5
    check ok[1].skipReason == "" and ok[1].code == "echo 2\n"
    expect ValueError:   # no reason
      discard nimBlocks(markerPrefix & " " & markerSuffix & "\n```nim\n```\n")
    expect ValueError:   # text between the marker and the block
      discard nimBlocks(markerPrefix & " r " & markerSuffix &
        "\nprose\n```nim\n```\n")
    expect ValueError:   # a block of another language
      discard nimBlocks(markerPrefix & " r " & markerSuffix &
        "\n```sh\nls\n```\n```nim\n```\n")
    expect ValueError:   # no block at all
      discard nimBlocks("```nim\n```\n" & markerPrefix & " r " & markerSuffix)
    expect ValueError:   # a block never closed
      discard nimBlocks("```nim\necho 1\n")
    expect ValueError:   # a marker after other text on its line
      discard nimBlocks("prose " & markerPrefix & " r " & markerSuffix &
        "\n```nim\necho 1\n```\n")
    expect ValueError:   # a marker inside a block
      discard nimBlocks("```nim\n# " & markerPrefix & " r " & markerSuffix &
        "\n```\n")
