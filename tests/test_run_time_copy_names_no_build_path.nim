## test_run_time_copy_names_no_build_path: a program compiled from a
## description carries no build-host path from it, and the description's
## compile-time diagnostics still name the file and line they are about.
##
## The compiler records each declaration's file as the absolute path it read
## it from. Diagnostics need that path; the copy of the description a
## program carries at run time (the grammar ``cliProgram`` generates, the
## model ``cliModel`` and ``plainCliModel`` return) records only the file's
## name (``cliRunTimeCopy``), so the program's bytes do not depend on the
## directory it was built in.
##
## The test writes small programs into a scratch directory whose name holds
## a marker no other path contains, and runs the real compiler on them (the
## one that built this test):
##
## 1. a program whose description uses every declaration that records a
##    position (commands, a ``call:``, parameters, expressions, a group, a
##    retired spelling), and that derives an external tool's configuration
##    table at run time (``cliConfigTableCode`` in a ``let``, so the grammar
##    the table is derived from is a literal of the program), is built with
##    ``-d:release``; neither its binary nor
##    the C the compiler generated from it contains the marker as a string
##    literal, and the program prints the file name its run-time copies
##    record, which shows they were carried and reduced, not dropped;
## 2. descriptions with one mistake each fail ``nim check`` with an error
##    at the absolute path of their file and the line of the mistake, one
##    per way clispec reports one: the DSL parser, a grammar problem the
##    program generator reports, a type check of an expression, and a help
##    expression evaluated into the grammar constant.
##
## Only the compiler shows what a binary carries and how a compile error is
## positioned, so nothing here is mocked.

import std/[os, osproc, strutils, tempfiles, unittest]

const
  testsDir = currentSourcePath().parentDir()
  srcDir = testsDir.parentDir() / "src"
  marker = "clispecBuildHostMarkerR8"
    ## In the scratch directory's name, and in no other path the build sees.

proc compilerExe(): string =
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

proc nim(command, file: string; options: openArray[string]):
    tuple[output: string, exitCode: int] =
  ## The compiler's ``command`` on ``file``, isolated from the user's and
  ## the checkout's configuration, with ``src/`` on the path.
  execCmdEx(quoteShellCommand(@[compilerExe(), command, "--hints:off",
    "--skipParentCfg", "--skipUserCfg", "--path:" & srcDir] & @options &
    @[file]))

const program = """
import std/macros
import clispec

macro toolTable(body: untyped): untyped =
  let model = parseCliModel[NoCliExtension, NoCliExtension](body,
    NoCliExtension())
  cliConfigTableCode(model, "tool")

const levelHelp = "the level, " & "from a constant"

cliProgram(Fx, "fx"):
  help "A program whose description records positions"
  retired "--old", replacement = "--level"
  flag level is int, default = 3, help = levelHelp,
    implies = [quiet = true]
  group "Output", help = "Where results go":
    boolFlag quiet is bool
  flag mode is string, values = ["a", "b"], default = "a"
  subcmd "run", help = "Run it":
    pos target is string
  subcmd "tool":
    call(help = "The tool itself"):
      pos x is string

const model = plainCliModel:
  flag only is int, default = 1

let g = Fx.cliGrammar
var files: seq[string]
for c in g.commands:
  files.add(c.sourceFile)
  for r in c.retired:
    files.add(r.sourceFile)
for gr in g.groups:
  files.add(gr.sourceFile)
let m = Fx.cliModel
for p in m.root.params:
  files.add(p.sourceFile)
  if p.default.isSet:
    files.add(p.default.sourceFile)
for e in m.root.params[0].implies:
  files.add(e.value.sourceFile)
files.add(model.root.params[0].sourceFile)
files.add(model.root.params[0].default.sourceFile)
# Derived when the program runs: the grammar behind it is in the image.
let table = toolTable:
  subcmd "build":
    flag jobs is int, key = "build.jobs"
doAssert table.entries.len == 1
for f in files:
  echo f
"""

type Mistake = object
  name: string
  source: string
  message: string
    ## The error's text after ``Error: ``.

const mistakes = [
  Mistake(name: "parser", message: "clispec: parameter 'a': implies itself",
    source: """
import clispec
cliProgram(Fx, "fx"):
  help "x"
  boolFlag a is bool, implies = [a = true] # mistake
"""),
  Mistake(name: "grammar", message: "clispec: parameter 'schema': " &
    "configuration key 'schema' is reserved",
    source: """
import clispec
cliProgram(Fx, "fx"):
  configSchema "fx.config.v1"
  flag schema is string, default = "" # mistake
"""),
  Mistake(name: "typecheck", message: "clispec: parameter 'jobs': " &
    "default `wrong` is not a valid int",
    source: """
import clispec
const wrong = (when defined(never): 4 else: "four")
cliProgram(Fx, "fx"):
  flag jobs is int,
    default = wrong # mistake
"""),
  Mistake(name: "help", message: "type mismatch: got 'int literal(3)'",
    source: """
import clispec
const helpNum = 3
cliProgram(Fx, "fx"):
  flag jobs is int,
    help = helpNum # mistake
"""),
]

proc mistakeLine(source: string): int =
  ## The 1-based line marked ``# mistake``.
  for i, line in pairs(source.splitLines()):
    if line.endsWith("# mistake"):
      return i + 1
  doAssert false, "no line is marked"

suite "test_run_time_copy_names_no_build_path":

  let scratch = createTempDir(marker & "_", "")

  test "the scratch directory is the only place the marker is":
    check marker in scratch
    check marker notin srcDir
    check marker notin compilerExe()

  test "a program built from a description carries no build-host path":
    let dir = scratch / "program"
    createDir(dir)
    let source = dir / "probe.nim"
    writeFile(source, program)
    let exe = dir / addFileExt("probe", ExeExt)
    let nimcache = scratch / "nimcache_program"
    let built = nim("c", source, ["-d:release", "--nimcache:" & nimcache,
      "-o:" & exe])
    checkpoint(built.output)
    require built.exitCode == 0
    let image = readFile(exe)
    check marker notin image
    check source notin image
    # The generated C (whose header comments name the build's directories,
    # which no image carries) holds no string literal naming the source. The
    # module generated from the program is the one holding its help text.
    var modules = 0
    for c in walkFiles(nimcache / "*.c"):
      let text = readFile(c)
      check ("\"" & source & "\"") notin text
      if "A program whose description records positions" in text:
        inc modules
    check modules == 1
    let (output, code) = execCmdEx(quoteShellCommand([exe]))
    check code == 0
    let lines = output.strip().splitLines()
    checkpoint(output)
    # 3 commands and the call:, 1 retired, 1 group, 3 parameters and the 2
    # defaults given, 1 implication, the plain model's parameter and its
    # default.
    check lines.len == 4 + 1 + 1 + 5 + 1 + 2
    for line in lines:
      check line == "probe.nim"

  for mistake in mistakes:
    test "a compile-time diagnostic names its file and line: " & mistake.name:
      let dir = scratch / mistake.name
      createDir(dir)
      let source = dir / ("bad_" & mistake.name & ".nim")
      writeFile(source, mistake.source)
      let checked = nim("check", source, ["--nimcache:" & (scratch /
        ("nimcache_" & mistake.name))])
      checkpoint(checked.output)
      check checked.exitCode != 0
      let at = source & "(" & $mistakeLine(mistake.source) & ", "
      var found = false
      for line in checked.output.splitLines():
        if line.startsWith(at) and ("Error: " & mistake.message) in line:
          found = true
      check found

  removeDir(scratch)
