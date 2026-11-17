## test_cs_m5c_compile_time_knobs_shrink: a colour knob that is off or fixed
## at compile time, by a ``-d:`` define or by a ``cliProgram`` parameter,
## leaves none of its code in the program, and the program behaves as the
## knob says whatever the run-time inputs are.
##
## The fixture ``tests/fixtures/cs_m5c_colour/knobs.nim`` (the ``depot``
## description as the program ``knobs``, printing only through its generated
## ``Knobs.printHelp`` / ``Knobs.printError``) is built with ``-d:release
## --opt:size`` (not stripped) once with every run-time knob on (the users'
## overrides included) and once per knob switched off or fixed, through a
## define or through the ``cliProgram`` parameter (``-d:knobs_params``).
##
## * Behaviour: each build runs through pipes and on a pseudo-terminal
##   (``tests/colour_harness.nim``) with the knob's variable or query in
##   play; the build with the knob off or fixed ignores it, the enabled
##   build honours it. A parameter applies over a contrary define in both
##   directions.
## * Binary: the file of a build with a knob off or fixed contains none of
##   that knob's marker byte strings (its variables' names, the query's
##   escape string, the SGR parameters of the palettes it can never choose,
##   and for ``colors = never`` every ``ESC[`` and every colour variable) and
##   is smaller than the enabled build. The sizes are printed as a table.
## * Negative control: the enabled build contains every marker (so a marker
##   search that can never find anything fails here) and honours every
##   variable and the query (the same cases, with the opposite outcome).
## * A bad parameter value is a compile-time error naming the parameter and
##   its allowed values, paired with valid values that compile.
##
## A build that does not compile fails the test. A POSIX platform where no
## pseudo-terminal can be opened fails it too; on Windows the terminal cases
## are compiled out and the test says so.

import std/[os, osproc, streams, strutils, tables, tempfiles, unittest]

import ./colour_harness

const
  testsDir = currentSourcePath().parentDir()
  srcDir = testsDir.parentDir() / "src"
  knobsSource = testsDir / "fixtures" / "cs_m5c_colour" / "knobs.nim"
  darkAnswer = "\e]11;rgb:1e1e/1e1e/2e2e\e\\\e]10;rgb:d4d4/d4d4/d4d4\e\\" &
    "\e[?62;22c"
    ## A dark theme's answer to the background query.

  # The heading SGR parameters by which a page's palette is recognised.
  plain = "plain"
  p16 = "1;34"
  dark24 = "1;38;2;82;198;137"
  dark256 = "1;38;5;42"
  light24 = "1;38;2;18;129;81"
  light256 = "1;38;5;22"

type
  Build = object
    name: string
    defines: seq[string]
      ## ``-d:`` defines besides ``release``.
    params: string
      ## The ``cliProgram`` colour parameters (``knobs_params``).
    absent: seq[string]
      ## The marker byte strings its file must not contain.
    knob: string
      ## The row of the size table ("" for none).

  Via = enum onPipe, onTerm

  Case = object
    name: string
    stream: Via
    env: seq[(string, string)]
    answer: string
    args: seq[string]
    expect: seq[(string, string, int)]
      ## (build, the heading's SGR parameters or ``plain``, whether the
      ## query is sent: 1 yes, 0 no, -1 not checked).

const
  envMarkers = @["NO_COLOR", "FORCE_COLOR", "CLICOLOR_FORCE", "CLICOLOR"]
  fgbgMarkers = @["COLORFGBG"]
  queryMarkers = @["\e]11;?", "/dev/tty"]
  userMarkers = @["CLISPEC_COLORS", "_COLORS"]
  depthMarkers = @["COLORTERM", "-256color"]
  marks24 = "38;2;"
  marks256 = "38;5;"
  neverMarkers = @["\e[", "NO_COLOR", "FORCE_COLOR", "CLICOLOR",
    "COLORTERM", "COLORFGBG", "CLISPEC_COLORS", "_COLORS", "TERM",
    "-256color", "\e]11;?", "/dev/tty", marks24, marks256, p16]

  onDefines = @["clispec_user_colors=on"]

let builds = @[
  Build(name: "on", defines: onDefines),
  Build(name: "env_off_define", defines: onDefines & "clispec_color_env=off",
    absent: envMarkers, knob: "colorEnv=off (define)"),
  Build(name: "env_off_param", defines: onDefines, params: "colorEnv=off",
    absent: envMarkers, knob: "colorEnv=off (parameter)"),
  Build(name: "env_on_param", defines: onDefines & "clispec_color_env=off",
    params: "colorEnv=on"),
  Build(name: "fgbg_off", defines: onDefines & "clispec_colorfgbg=off",
    absent: fgbgMarkers, knob: "colorFgBg=off (define)"),
  Build(name: "query_off", defines: onDefines,
    params: "backgroundQuery=off", absent: queryMarkers,
    knob: "backgroundQuery=off (parameter)"),
  Build(name: "user_off_define", defines: @["clispec_user_colors=off"],
    absent: userMarkers, knob: "userColors=off (define)"),
  Build(name: "user_off_param", defines: onDefines, params: "userColors=off",
    absent: userMarkers, knob: "userColors=off (parameter over define)"),
  Build(name: "depth24", defines: onDefines & "clispec_color_depth=24",
    absent: depthMarkers & marks256, knob: "colorDepth=24 (define)"),
  Build(name: "depth256", defines: onDefines, params: "colorDepth=256",
    absent: depthMarkers & marks24, knob: "colorDepth=256 (parameter)"),
  Build(name: "bg_unknown", defines: onDefines & "clispec_background=unknown",
    absent: depthMarkers & fgbgMarkers & queryMarkers & marks24 & marks256,
    knob: "background=unknown (define)"),
  Build(name: "light24_param", defines: onDefines,
    params: "colorDepth=24,background=light",
    absent: depthMarkers & fgbgMarkers & queryMarkers & marks256,
    knob: "colorDepth=24,background=light (parameter)"),
  Build(name: "never_define", defines: onDefines & "clispec_colors=never",
    absent: neverMarkers, knob: "colors=never (define)"),
  Build(name: "never_param", defines: onDefines, params: "colors=never",
    absent: neverMarkers, knob: "colors=never (parameter)")]

proc allMarkers(): seq[string] =
  for b in builds:
    for m in b.absent:
      if m notin result:
        result.add(m)

let cases = @[
  # The environment switches.
  Case(name: "FORCE_COLOR=1 through a pipe", stream: onPipe,
    env: @[("FORCE_COLOR", "1"), ("TERM", "xterm")], args: @["-h"],
    expect: @[("on", p16, -1), ("env_off_define", plain, -1),
              ("env_off_param", plain, -1), ("env_on_param", p16, -1),
              ("never_define", plain, -1), ("never_param", plain, -1)]),
  Case(name: "CLICOLOR_FORCE=1 through a pipe", stream: onPipe,
    env: @[("CLICOLOR_FORCE", "1"), ("TERM", "xterm")], args: @["-h"],
    expect: @[("on", p16, -1), ("env_off_define", plain, -1),
              ("env_off_param", plain, -1), ("env_on_param", p16, -1)]),
  Case(name: "NO_COLOR=1 on a terminal", stream: onTerm,
    env: @[("NO_COLOR", "1"), ("TERM", "xterm")], args: @["-h"],
    expect: @[("on", plain, 0), ("env_off_define", p16, 0),
              ("env_off_param", p16, 0), ("env_on_param", plain, 0)]),
  # COLORFGBG.
  Case(name: "COLORFGBG light on a 256-colour terminal, no answer",
    stream: onTerm, env: @[("TERM", "xterm-256color"), ("COLORFGBG", "0;15")],
    args: @["-h"],
    expect: @[("on", light256, 0), ("fgbg_off", p16, 1)]),
  # The background query.
  Case(name: "the query answered dark", stream: onTerm,
    env: @[("TERM", "xterm-256color")], answer: darkAnswer, args: @["-h"],
    expect: @[("on", dark256, 1), ("query_off", p16, 0),
              ("bg_unknown", p16, 0), ("never_define", plain, 0),
              ("never_param", plain, 0), ("light24_param", light24, 0)]),
  # The users' overrides.
  Case(name: "CLISPEC_COLORS through a pipe", stream: onPipe,
    env: @[("FORCE_COLOR", "1"), ("CLISPEC_COLORS", "heading=7")],
    args: @["-h"],
    expect: @[("on", "7", -1), ("user_off_define", p16, -1),
              ("user_off_param", p16, -1)]),
  Case(name: "KNOBS_COLORS through a pipe", stream: onPipe,
    env: @[("FORCE_COLOR", "1"), ("KNOBS_COLORS", "heading=4")],
    args: @["-h"],
    expect: @[("on", "4", -1), ("user_off_define", p16, -1),
              ("user_off_param", p16, -1)]),
  # A fixed depth.
  Case(name: "no COLORTERM, a dark COLORFGBG", stream: onPipe,
    env: @[("FORCE_COLOR", "1"), ("TERM", "xterm"), ("COLORFGBG", "15;0")],
    args: @["-h"],
    expect: @[("on", p16, -1), ("depth24", dark24, -1),
              ("depth256", dark256, -1), ("bg_unknown", p16, -1)]),
  Case(name: "COLORTERM=truecolor, a dark COLORFGBG", stream: onPipe,
    env: @[("FORCE_COLOR", "1"), ("TERM", "xterm-256color"),
           ("COLORTERM", "truecolor"), ("COLORFGBG", "15;0")],
    args: @["-h"],
    expect: @[("on", dark24, -1), ("depth256", dark256, -1),
              ("bg_unknown", p16, -1), ("light24_param", light24, -1)]),
  Case(name: "FORCE_COLOR=3, a dark COLORFGBG", stream: onPipe,
    env: @[("FORCE_COLOR", "3"), ("COLORFGBG", "15;0")], args: @["-h"],
    expect: @[("on", dark24, -1), ("depth256", dark256, -1),
              ("bg_unknown", p16, -1)]),
  # A fixed background and depth.
  Case(name: "a dark COLORFGBG on a 256-colour terminal", stream: onTerm,
    env: @[("TERM", "xterm-256color"), ("COLORFGBG", "15;0")],
    answer: darkAnswer, args: @["-h"],
    expect: @[("on", dark256, 0), ("light24_param", light24, 0)]),
  # colors = never, whatever the program and the environment say.
  Case(name: "CliOptions.color always through a pipe", stream: onPipe,
    env: @[("KNOBS_FIXTURE_MODE", "always")], args: @["-h"],
    expect: @[("on", p16, -1), ("never_define", plain, -1),
              ("never_param", plain, -1)]),
  Case(name: "a 256-colour terminal", stream: onTerm,
    env: @[("TERM", "xterm-256color"), ("COLORTERM", "truecolor"),
           ("COLORFGBG", "15;0")], args: @["-h"],
    expect: @[("on", dark24, 0), ("never_define", plain, 0),
              ("never_param", plain, 0)]),
  Case(name: "a usage error with FORCE_COLOR=1", stream: onPipe,
    env: @[("FORCE_COLOR", "1")], args: @["build", "--nope"],
    expect: @[("on", "1;31", -1), ("never_define", plain, -1),
              ("never_param", plain, -1), ("env_off_param", plain, -1)])]

proc compilerExe(): string =
  ## The compiler that built this test.
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

proc nimArgs(scratch, name, command: string; defines: openArray[string];
             params: string; output = ""): seq[string] =
  result = @[compilerExe(), command, "--hints:off", "--warnings:off",
    "--skipParentCfg", "--skipUserCfg", "--path:" & srcDir,
    "--nimcache:" & (scratch / ("nimcache_" & name))]
  if command == "c":
    result.add(["-d:release", "--opt:size", "--parallelBuild:1"])
  for d in defines:
    result.add("-d:" & d)
  if params.len > 0:
    result.add("-d:knobs_params=" & params)
  if output.len > 0:
    result.add("-o:" & output)
  result.add(knobsSource)

proc exeOf(scratch, name: string): string =
  scratch / addFileExt("knobs_" & name, ExeExt)

proc buildAll(scratch: string): Table[string, string] =
  ## Compiles every build, four at a time; a build that does not compile
  ## fails the test with the compiler's output.
  var commands: seq[string] = @[]
  for b in builds:
    commands.add(quoteShellCommand(nimArgs(scratch, b.name, "c", b.defines,
      b.params, exeOf(scratch, b.name))))
  var outputs = newSeq[string](commands.len)
  var codes = newSeq[int](commands.len)
  let worst = execProcesses(commands, {poStdErrToStdOut, poEvalCommand},
    n = 4, afterRunEvent = proc (k: int; p: Process) =
      outputs[k] = p.outputStream.readAll()
      codes[k] = p.peekExitCode())
  for k, b in builds:
    checkpoint(b.name & ": " & commands[k] & "\n" & outputs[k])
    doAssert codes[k] == 0, "the knobs fixture (" & b.name &
      ") does not compile (exit code " & $codes[k] & "):\n" & outputs[k]
    doAssert fileExists(exeOf(scratch, b.name)), b.name & ": no binary"
    result[b.name] = exeOf(scratch, b.name)
  doAssert worst == 0, "a build failed (exit code " & $worst & ")"

proc headingOf(output: string): string =
  ## The SGR parameters of the first styled span (``plain`` when the
  ## output holds no escape sequence).
  let at = output.find("\e[")
  if at < 0 and '\e' notin output:
    return plain
  if at < 0:
    return "an escape that is not ESC["
  let m = output.find('m', at)
  if m < 0: "an unterminated ESC[" else: output[at + 2 ..< m]

proc run(exe: string; c: Case): Outcome =
  if c.stream == onTerm:
    when not defined(windows):
      result = onTerminal(exe, c.args, c.env, 90, c.answer)
  else:
    result = throughPipes(exe, c.args, c.env)
    result.output.add(result.errors)

when defined(windows):
  echo "NOT RUN on Windows: the terminal cases of this test need a POSIX " &
    "pseudo-terminal; they run on Linux and macOS. The pipe cases run."

var scratch = createTempDir("clispec_m5c_shrink_", "")
var exes: Table[string, string]

suite "test_cs_m5c_compile_time_knobs_shrink":

  test "every build compiles":
    exes = buildAll(scratch)
    check exes.len == builds.len

  test "negative control: the enabled build holds every marker":
    let file = readFile(exes["on"])
    for m in allMarkers():
      checkpoint("marker " & m.escape)
      check m in file

  test "a build with a knob off or fixed holds none of its markers":
    for b in builds:
      if b.absent.len == 0:
        continue
      let file = readFile(exes[b.name])
      for m in b.absent:
        checkpoint(b.name & ": marker " & m.escape)
        check m notin file

  test "a build with a knob off or fixed is smaller than the enabled one":
    let onSize = getFileSize(exes["on"])
    var rows: seq[(string, BiggestInt)] = @[]
    for b in builds:
      if b.knob.len > 0:
        rows.add((b.knob, getFileSize(exes[b.name])))
    echo ""
    echo "  Binary sizes (-d:release --opt:size, not stripped), bytes:"
    echo "  " & alignLeft("knob", 46) & align("on", 9) & align("off", 9) &
      align("saved", 8)
    for (knob, size) in rows:
      echo "  " & alignLeft(knob, 46) & align($onSize, 9) & align($size, 9) &
        align($(onSize - size), 8)
      checkpoint(knob)
      check size < onSize
    # A parameter that turns a knob back on over a contrary define gives
    # the enabled program.
    echo "  " & alignLeft("colorEnv=on (parameter over define off)", 46) &
      align($onSize, 9) & align($getFileSize(exes["env_on_param"]), 9)
    check "NO_COLOR" in readFile(exes["env_on_param"])

  test "each build behaves as its knobs say":
    var ran = 0
    for c in cases:
      when defined(windows):
        if c.stream == onTerm:
          continue
      for (name, want, queried) in c.expect:
        checkpoint(c.name & " / " & name)
        let r = run(exes[name], c)
        check r.code == (if c.args[0] == "-h": 0 else: 2)
        let got = headingOf(r.output)
        checkpoint("printed: " & r.output.escape)
        check got == want
        if queried >= 0:
          check r.queried == (queried == 1)
        inc ran
    when defined(windows):
      check ran > 0
    else:
      var all = 0
      for c in cases:
        all += c.expect.len
      check ran == all

  test "negative control: the enabled build honours every input":
    # For each case, a knob's build and the enabled build disagree, so the
    # behaviour checks above could not pass with an input that is ignored
    # everywhere.
    for c in cases:
      var onWant = ""
      for (name, want, queried) in c.expect:
        if name == "on":
          onWant = want
      checkpoint(c.name)
      check onWant.len > 0
      var differs = false
      for (name, want, queried) in c.expect:
        if name != "on" and name != "env_on_param" and want != onWant:
          differs = true
      check differs

  test "a bad parameter value is a compile-time error naming it":
    for (params, words) in [
        ("colors=sometimes", @["'colors'", "auto, always, never"]),
        ("colorEnv=maybe", @["'colorEnv'", "on, yes, true, 1"]),
        ("colorDepth=99", @["'colorDepth'", "auto, 16, 256, 24"]),
        ("background=grey", @["'background'", "auto, dark, light, unknown"]),
        ("colorFgBg=2", @["'colorFgBg'"]),
        ("backgroundQuery=x", @["'backgroundQuery'"]),
        ("userColors=please", @["'userColors'"]),
        ("palette=heading=red", @["'palette'", "heading=red"]),
        ("palette=bg=dark", @["'palette'", "background"])]:
      checkpoint(params)
      let (output, code) = execCmdEx(quoteShellCommand(nimArgs(scratch,
        "check", "check", [], params)))
      checkpoint(output)
      check code != 0
      for w in words:
        check w in output
    # The same parameters with valid values compile.
    let (output, code) = execCmdEx(quoteShellCommand(nimArgs(scratch,
      "check", "check", [], "colors=Always,colorEnv=no,colorDepth=256," &
      "background=light,colorFgBg=0,backgroundQuery=none,userColors=yes," &
      "palette=heading=1;4:tip=")))
    checkpoint(output)
    check code == 0

if dirExists(scratch):
  removeDir(scratch)
