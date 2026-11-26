## test_program_carries_no_source_location: a program compiled from a
## description carries no source location of it, prints none, and the
## description's compile-time diagnostics still name the file and line they
## are about.
##
## Where a declaration was written (the file, line and column the compiler
## records) is for the diagnostics reported while the description compiles.
## It is kept beside the model, in the located model the macros hold, and
## the types a program carries its description in (the grammar
## ``cliProgram`` generates, the model ``cliModel`` and ``plainCliModel``
## return, the grammar behind a configuration table) have no field for it
## (test_run_time_types_have_no_location_fields checks the types). So
## nothing the program holds or prints names the file its description was
## written in.
##
## The test writes its programs into a scratch directory whose name holds a
## marker no other path contains, and runs the real compiler on them (the
## one that built this test):
##
## 1. The image. A description file with a distinctive name
##    (``zq7marker_desc.nim``) uses every declaration that records a
##    position (commands, a ``call:``, parameters, expressions, a group, a
##    retired spelling, a ``plainCliModel`` constant) and derives an external
##    tool's configuration table at run time (``cliConfigTableCode`` in a
##    ``let``, so the grammar the table is derived from is a literal of the
##    program). It is built with ``-d:release``; neither the binary nor any
##    string literal of the C the compiler generated names the file's name or
##    the scratch directory. A debug build (Nim's defaults, stack traces
##    on) is built too: its stack-trace and line-trace tables name every
##    module of the program, the description's included, and those are the
##    compiler's run-time error reporting, outside what clispec emits. So
##    for it the generated C is checked with those calls (``nimfr_``,
##    ``nimlf_``) taken out: no other string literal names the file.
## 2. The outputs. The program's help (short, long, a subcommand's), its
##    JSON help, its version, each shell's completion
##    script, completion replies, every kind of usage error it can raise
##    (unknown flag, unknown subcommand, missing subcommand, a bad value, a
##    value outside the closed set, a retired spelling, a missing and an
##    extra positional), the library calls a program prints from
##    (``helpText``, ``helpJson``, ``canonicalArgv``, ``complete``, a
##    configuration issue) and a ``$`` dump of each value it carries: none
##    names the file, the directory or anything shaped like a source
##    location (``.nim``, ``:<line>:<col>``, ``(<line>, <col>)``). Each
##    output is also checked for the text that shows it is the output
##    meant, so an output that came out empty does not pass. Both builds
##    are run.
## 3. Compile-time diagnostics. Descriptions with one mistake each fail
##    ``nim check`` with an error at the absolute path of their file and the
##    line of the mistake, one per way clispec places one from the located
##    model: the DSL parser (a parameter's, a retired spelling's and a
##    group's location), a grammar rule (a command's location), a problem
##    the program generator reports (a parameter's), a type check of an
##    expression (its line and column), and a help expression evaluated
##    into the grammar constant. A parameter declared twice is reported at
##    the second declaration and names the first one's file and line.
##    Every description ends with a subcommand declared after its mistake
##    (``mistakeTail``): a diagnostic given no position is placed by the
##    compiler at the last node of the description the macro read, so
##    without it a mistake written last would land on its own line even
##    with its location lost.
##
## Only the compiler shows what a binary carries and how a compile error is
## positioned, and only the built program shows what it prints, so nothing
## here is mocked.

import std/[os, osproc, strutils, tempfiles, unittest]

const
  testsDir = currentSourcePath().parentDir()
  srcDir = testsDir.parentDir() / "src"
  dirMarker = "zq7markerDir"
    ## In the scratch directory's name, and in no other path the build sees.
  fileStem = "zq7marker_desc"
    ## The description file's name, without ``.nim``.

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
import std/[macros, os, strutils]
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

proc main(): int =
  let args = commandLineParams()
  # Derived when the program runs: the grammar behind it is in the image.
  let table = toolTable:
    subcmd "build":
      flag jobs is int, key = "build.jobs"
  # (No ``doAssert`` here: its message names this file, which is what the
  # test looks for.)
  if table.entries.len != 1:
    return 1
  if args.len == 2 and args[0] == "probe-script":
    var shell: CliShell
    if not cliParseShell(args[1], shell):
      return 1
    stdout.write Fx.completionScript(shell)
    return 0
  if args.len == 1 and args[0] == "probe-dump":
    echo $Fx.cliGrammar
    echo $Fx.cliModel
    echo $model
    echo $table
    return 0
  if args.len == 1 and args[0] == "probe-api":
    try:
      echo Fx.helpText(["run"], long = true)
      echo Fx.helpText(["tool"], all = true)
      echo Fx.helpJson(["tool"])
      echo Fx.canonicalArgv(["--level=5", "run", "x"]).join(" ")
      for c in Fx.complete(["ru"]):
        echo "candidate ", c.value
      echo Fx.completionReply(["bash", "--", "--le"])
      let issue = cliCheckEntry(table, ["build", "job"],
        CliConfigValue(kind: ccvInteger, text: "2"), line = 4)
      echo cliConfigIssueMessage(issue, "tool.toml")
    except CatchableError as e:
      echo "unexpected: ", e.msg
      return 1
    return 0
  try:
    discard Fx.load(args, CliOptions(versionText: "fx 1.0"))
  except CliHelpRequest as e:
    Fx.printHelp(e)
    return 0
  except CliUsageError as e:
    Fx.printError(e)
    return e.exitCode
  echo "parsed"
  0

quit main()
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
  Mistake(name: "retired", message: "clispec: the root command: retired " &
    "'--level' is a spelling of flag 'level'",
    source: """
import clispec
cliProgram(Fx, "fx"):
  flag level is int
  retired "--level", replacement = "--x" # mistake
"""),
  Mistake(name: "group", message: "clispec: group 'G' lists both",
    source: """
import clispec
cliProgram(Fx, "fx"):
  group "G": # mistake
    flag level is int
  subcmd "s":
    group "G":
      subcmd "t":
        flag x is int
"""),
  Mistake(name: "rule", message: "clispec: command 's' has more than one " &
    "repeated positional",
    source: """
import clispec
cliProgram(Fx, "fx"):
  subcmd "s":
    pos a is seq[string], repeated = true # mistake
    pos b is seq[string], repeated = true
"""),
  Mistake(name: "duplicate", message: "clispec: parameter 'level': " &
    "declared twice in the root command; the other declaration is " &
    "'level' (@FILE@:3)",
    source: """
import clispec
cliProgram(Fx, "fx"):
  flag level is int
  flag level is string # mistake
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

const mistakeTail = """
  subcmd "tail":
    pos tailWord is string
"""
  ## Appended to every mistake's description, so that something the macro
  ## reads follows the mistake. A node a macro creates without a position
  ## takes the position of the user's node it read last (the compiler's
  ## heuristic for macro-made nodes), so an error that lost its location
  ## would still name the mistake's line if the mistake were the last thing
  ## written.

proc mistakeLine(source: string): int =
  ## The 1-based line marked ``# mistake``.
  for i, line in pairs(source.splitLines()):
    if line.endsWith("# mistake"):
      return i + 1
  doAssert false, "no line is marked"

proc digitsAt(text: string; i: int): int =
  ## How many decimal digits start at ``text[i]``.
  var j = i
  while j < text.len and text[j] in Digits:
    inc j
  j - i

proc hasLineColumn(text: string): bool =
  ## Whether ``text`` holds a location as ``:<line>:<col>`` or as the
  ## compiler writes one, ``(<line>, <col>)`` (the space optional).
  for i, c in text:
    if c == ':':
      let a = digitsAt(text, i + 1)
      if a > 0 and i + 1 + a < text.len and text[i + 1 + a] == ':' and
          digitsAt(text, i + 2 + a) > 0:
        return true
    elif c == '(':
      let a = digitsAt(text, i + 1)
      var j = i + 1 + a
      if a > 0 and j < text.len and text[j] == ',':
        inc j
        if j < text.len and text[j] == ' ':
          inc j
        let b = digitsAt(text, j)
        if b > 0 and j + b < text.len and text[j + b] == ')':
          return true

proc withoutTraceCalls(line: string): string =
  ## ``line`` of generated C without the calls a stack-traced build makes to
  ## record the frame and the line (``nimfr_(<proc>, <file>)``,
  ## ``nimlf_(<line>, <file>)``), whose string arguments are the compiler's
  ## stack-trace table, not clispec's data.
  result = line
  for call in ["nimfr_(", "nimlf_("]:
    var at = result.find(call)
    while at >= 0:
      let close = result.find(')', at)
      if close < 0:
        break
      result = result[0 ..< at] & result[close + 1 .. ^1]
      at = result.find(call)

proc quotedLiteralsNaming(text, name: string): seq[string] =
  ## The C string literals on ``text``'s lines that contain ``name``.
  for line in text.splitLines():
    var at = line.find(name)
    while at >= 0:
      if line[0 ..< at].count('"') mod 2 == 1:
        result.add(line)
        break
      at = line.find(name, at + 1)

type Run = object
  args: seq[string]
  expect: string
    ## Text that shows the output is the one meant.

const runs = [
  Run(args: @[], expect: "needs a subcommand"),
  Run(args: @["-h"], expect: "A program whose description records"),
  Run(args: @["--help"], expect: "the level, from a constant"),
  Run(args: @["--help=text"], expect: "Where results go"),
  Run(args: @["--help=json"], expect: "clispec-help/1"),
  Run(args: @["run", "--help"], expect: "Run it"),
  Run(args: @["run", "--help=json"], expect: "clispec-help/1"),
  Run(args: @["tool", "--help"], expect: "The tool itself"),
  Run(args: @["--version"], expect: "fx 1.0"),
  Run(args: @["--bogus", "run", "x"], expect: "unknown flag '--bogus'"),
  Run(args: @["nosuch"], expect: "nosuch"),
  Run(args: @["--level=abc", "run", "x"], expect: "abc"),
  Run(args: @["--mode=c", "run", "x"], expect: "'c'"),
  Run(args: @["--old", "run", "x"], expect: "--level"),
  Run(args: @["run"], expect: "target"),
  Run(args: @["run", "a", "b"], expect: "'b'"),
  Run(args: @["run", "x"], expect: "parsed"),
  # The completion protocol (``clispec/completion``): bash passes its word
  # breaks and the command line, zsh and fish the words, PowerShell each
  # word as ``:`` and its base64.
  Run(args: @["__complete", "bash", "\"'@><=;|&(:", "fx ru"], expect: "run"),
  Run(args: @["__complete", "fish", "--le"], expect: "--level"),
  Run(args: @["__complete", "zsh", "--mode", ""], expect: "a"),
  Run(args: @["__complete", "powershell", ":dA=="], expect: "tool"),
  Run(args: @["probe-script", "bash"], expect: "__complete"),
  Run(args: @["probe-script", "zsh"], expect: "__complete"),
  Run(args: @["probe-script", "fish"], expect: "__complete"),
  Run(args: @["probe-script", "powershell"], expect: "__complete"),
  Run(args: @["probe-api"], expect: "unknown key 'build.job'"),
  Run(args: @["probe-dump"], expect: "the level, from a constant"),
]

suite "test_program_carries_no_source_location":

  let scratch = createTempDir(dirMarker & "_", "")
  let dir = scratch / "program"
  let source = dir / (fileStem & ".nim")
  let exe = dir / addFileExt("fx", ExeExt)
  let nimcache = scratch / "nimcache_program"
  let debugExe = dir / addFileExt("fx_debug", ExeExt)
  let debugNimcache = scratch / "nimcache_program_debug"
  var built, debugBuilt = false

  proc namesTheDescription(text: string): seq[string] =
    ## What in ``text`` names the description's file or a source location.
    if fileStem.toLowerAscii in text.toLowerAscii: result.add("file name")
    if dirMarker.toLowerAscii in text.toLowerAscii: result.add("directory")
    if ".nim" in text: result.add("'.nim'")
    if hasLineColumn(text): result.add("a line and column")

  test "the scratch directory is the only place the markers are":
    check dirMarker in scratch
    for path in [srcDir, compilerExe()]:
      check dirMarker notin path
      check fileStem notin path

  test "a program built from a description carries no source location":
    createDir(dir)
    writeFile(source, program)
    let compiled = nim("c", source, ["-d:release", "--nimcache:" & nimcache,
      "-o:" & exe])
    checkpoint(compiled.output)
    require compiled.exitCode == 0
    built = true
    let image = readFile(exe)
    check fileStem notin image
    check dirMarker notin image
    check source notin image
    # The generated C (whose header comments name the build's directories,
    # which no image carries) holds no string literal naming the file. The
    # module generated from the program is the one holding its help text.
    var modules = 0
    for c in walkFiles(nimcache / "*.c"):
      let text = readFile(c)
      let literals = quotedLiteralsNaming(text, fileStem)
      checkpoint(c & ": " & $literals)
      check literals.len == 0
      if "A program whose description records positions" in text:
        inc modules
    check modules == 1

  test "a debug build's data carries no source location":
    # The description's own data, in a build with stack traces on: only
    # the compiler's trace calls may name the file (what clispec emits is
    # checked, not the compiler's stack-trace tables).
    let compiled = nim("c", source, ["--nimcache:" & debugNimcache,
      "-o:" & debugExe])
    checkpoint(compiled.output)
    require compiled.exitCode == 0
    debugBuilt = true
    var traced, modules = 0
    for c in walkFiles(debugNimcache / "*.c"):
      let text = readFile(c)
      var rest = ""
      for line in text.splitLines():
        if fileStem in line and (line.contains("nimfr_(") or
            line.contains("nimlf_(")):
          inc traced
        rest.add(withoutTraceCalls(line))
        rest.add('\n')
      let literals = quotedLiteralsNaming(rest, fileStem)
      checkpoint(c & ": " & $literals)
      check literals.len == 0
      if "A program whose description records positions" in text:
        inc modules
    check modules == 1
    # Control: the build is the stack-traced one, whose trace calls do name
    # the description's file.
    check traced > 0

  for run in runs:
    for (build, path) in [("release", exe), ("debug", debugExe)]:
      test "no output names the description (" & build & "): " &
          run.args.join(" "):
        require (if build == "release": built else: debugBuilt)
        # Standard error is merged into the output (``execCmdEx``'s
        # default).
        let (output, code) = execCmdEx(quoteShellCommand(@[path] & run.args))
        checkpoint("exit " & $code & ":\n" & output)
        check run.expect in output
        check namesTheDescription(output).len == 0
        checkpoint($namesTheDescription(output))

  for mistake in mistakes:
    test "a compile-time diagnostic names its file and line: " & mistake.name:
      let dir = scratch / mistake.name
      createDir(dir)
      let source = dir / ("bad_" & mistake.name & ".nim")
      writeFile(source, mistake.source & mistakeTail)
      let checked = nim("check", source, ["--nimcache:" & (scratch /
        ("nimcache_" & mistake.name))])
      checkpoint(checked.output)
      check checked.exitCode != 0
      let at = source & "(" & $mistakeLine(mistake.source) & ", "
      let message = mistake.message.replace("@FILE@", source)
      var found = false
      for line in checked.output.splitLines():
        if line.startsWith(at) and ("Error: " & message) in line:
          found = true
      check found

  removeDir(scratch)
