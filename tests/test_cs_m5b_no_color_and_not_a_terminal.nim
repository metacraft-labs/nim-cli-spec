## test_cs_m5b_no_color_and_not_a_terminal: what a program prints with
## ``cliPrintHelp`` and ``cliPrintError`` on a real terminal and through a
## pipe.
##
## The fixture ``tests/fixtures/cs_m5b_help/depot.nim`` (the ``depot``
## description of ``test_cs_m5b_help_matches_design``, printing help and
## usage errors as the README says) is compiled with the compiler that built
## this test and run:
##
## * on a pseudo-terminal the test opens itself (``posix_openpt``), with
##   the window size set by ``TIOCSWINSZ``: styled with ``TERM=xterm`` and
##   ``NO_COLOR`` empty; plain with ``NO_COLOR=1`` or ``TERM=dumb``; plain
##   when the program sets ``CliOptions.color`` to ``ccmNever``; the page as
##   wide as the terminal (90, and 120 capped at 100) unless ``COLUMNS``
##   says otherwise (60, and 160 capped at 100);
## * through pipes: plain, 80 columns wide or ``COLUMNS`` (capped at 100;
##   a value that is not a positive integer is ignored), with ``NO_COLOR=1``
##   or ``TERM=dumb`` too, and styled when the program sets
##   ``CliOptions.color`` to ``ccmAlways`` (whatever ``NO_COLOR`` and
##   ``TERM`` say).
##
## Help goes to standard output and usage errors to standard error. Every
## output is compared in full with what the library renders in this
## process for that width and colour, and in every case the plain output is
## the styled one without its escape sequences.
##
## A POSIX platform where no pseudo-terminal can be opened fails this test;
## it does not skip it. Windows has no POSIX pseudo-terminal: there the
## terminal cases are compiled out and the test says so on its output (they
## are not counted as passes; Linux and macOS run them), and the pipe cases
## run. The test kills only the process it started, by its
## pid, and every read has a deadline.

import std/[os, osproc, streams, strtabs, strutils, tempfiles, unittest]

import clispec

import ./fixtures/cs_m5b_help/depot_cli

when not defined(windows):
  import std/[posix, times]

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()
  srcDir = repoDir / "src"
  fixtureSource = testsDir / "fixtures" / "cs_m5b_help" / "depot.nim"
  deadlineSeconds = 60.0

proc compilerExe(): string =
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

var scratch = ""
var depotExe = ""

type Outcome = object
  output: string
    ## Standard output (on the terminal: standard output and error).
  errors: string
    ## Standard error, through pipes.
  code: int

when not defined(windows):
  proc posix_openpt(flags: cint): cint {.importc, header: "<stdlib.h>".}
  proc grantpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
  proc unlockpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
  proc ptsname(fd: cint): cstring {.importc, header: "<stdlib.h>".}
  proc ioctlArg(fd: cint; request: culong): cint {.importc: "ioctl",
    header: "<sys/ioctl.h>", varargs.}
  var TIOCSCTTY {.importc, header: "<sys/ioctl.h>".}: culong
  var TIOCSWINSZ {.importc, header: "<sys/ioctl.h>".}: culong
  type
    Winsize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
      ws_row, ws_col, ws_xpixel, ws_ypixel: cushort

  proc onTerminal(args: openArray[string]; env: openArray[(string, string)];
                  columns: int): Outcome =
    ## Runs the fixture as the session leader of a new pseudo-terminal
    ## ``columns`` wide, and reads everything it writes until it exits.
    let master = posix_openpt(O_RDWR or O_NOCTTY)
    doAssert master >= 0, "posix_openpt failed: no pseudo-terminal"
    doAssert grantpt(master) == 0 and unlockpt(master) == 0,
      "grantpt/unlockpt failed"
    let slaveName = $ptsname(master)
    var size = Winsize(ws_row: 50, ws_col: cushort(columns))
    discard ioctlArg(master, TIOCSWINSZ, addr size)
    var argvList = @[depotExe]
    for a in args:
      argvList.add(a)
    var envList: seq[string] = @[]
    for (k, v) in env:
      envList.add(k & "=" & v)
    let argv = allocCStringArray(argvList)
    let envp = allocCStringArray(envList)
    let cSlave = slaveName.cstring
    let cExe = depotExe.cstring
    let pid = fork()
    doAssert pid >= 0, "fork failed"
    if pid == 0:
      discard setsid()
      let slave = posix.open(cSlave, O_RDWR)
      if slave < 0:
        exitnow(126)
      discard ioctlArg(slave, TIOCSCTTY, 0)
      # On macOS a size set on the master before the slave is open does
      # not stick; set it here too.
      discard ioctlArg(slave, TIOCSWINSZ, addr size)
      discard dup2(slave, 0)
      discard dup2(slave, 1)
      discard dup2(slave, 2)
      if slave > 2:
        discard close(slave)
      discard close(master)
      discard execve(cExe, argv, envp)
      exitnow(127)
    deallocCStringArray(argv)
    deallocCStringArray(envp)
    let deadline = epochTime() + deadlineSeconds
    var text = ""
    var timedOut = false
    while true:
      if epochTime() > deadline:
        timedOut = true
        break
      var fds = [TPollfd(fd: master, events: POLLIN)]
      let ready = poll(addr fds[0], 1, 200)
      if ready < 0:
        break
      if ready == 0:
        # Nothing to read: done once the child has exited.
        var st: cint
        if waitpid(pid, st, WNOHANG) == pid:
          result.code = if WIFEXITED(st): WEXITSTATUS(st) else: -1
          var buf: array[4096, char]
          while true:
            var more = [TPollfd(fd: master, events: POLLIN)]
            if poll(addr more[0], 1, 0) <= 0:
              break
            let n = read(master, addr buf[0], buf.len)
            if n <= 0:
              break
            for k in 0 ..< n:
              text.add(buf[k])
          discard close(master)
          result.output = text.replace("\r\n", "\n")
          return
        continue
      var buf: array[4096, char]
      let n = read(master, addr buf[0], buf.len)
      if n <= 0:
        # The slave side is closed (EIO on Linux): the child is done.
        break
      for k in 0 ..< n:
        text.add(buf[k])
    discard close(master)
    if timedOut:
      discard kill(pid, SIGKILL)
    var st: cint
    discard waitpid(pid, st, 0)
    doAssert not timedOut, "the fixture did not finish within " &
      $deadlineSeconds & " s; output so far:\n" & text
    result.code = if WIFEXITED(st): WEXITSTATUS(st) else: -1
    result.output = text.replace("\r\n", "\n")

proc throughPipes(args: openArray[string];
                  env: openArray[(string, string)]): Outcome =
  ## Runs the fixture with its standard output and error on pipes.
  # The test's own environment (on Windows a process needs some of it),
  # without what decides colour and width or sets the fixture's flags.
  let table = newStringTable(modeCaseSensitive)
  for k, v in envPairs():
    if k.toUpperAscii() in ["NO_COLOR", "TERM", "COLUMNS", "FORCE_COLOR",
        "CLICOLOR", "CLICOLOR_FORCE", "COLORTERM", "COLORFGBG", "CI",
        "CLISPEC_COLORS"] or k.toUpperAscii().startsWith("DEPOT_"):
      continue
    table[k] = v
  for (k, v) in env:
    table[k] = v
  let p = startProcess(depotExe, args = args, env = table, options = {})
  try:
    result.output = p.outputStream.readAll()
    result.errors = p.errorStream.readAll()
    result.code = p.waitForExit(int(deadlineSeconds * 1000))
  finally:
    p.close()

proc page(path: openArray[string]; width: int; styled: bool): string =
  ## The short page of ``path`` as the library renders it at ``width``.
  var layout = cliDefaultHelpLayout
  layout.width = width
  Depot.helpText(path, layout = layout, styled = styled)

proc usageError(argv: openArray[string]): ref CliUsageError =
  try:
    discard Depot.load(@argv)
  except CliUsageError as e:
    return e
  doAssert false, "no usage error for " & $argv

proc checkStyled(styled, plain: string) =
  ## Styled: escape sequences, and the plain text once they are removed.
  check "\e[" in styled
  check cliStripStyles(styled) == plain

proc checkPlain(output: string) =
  check "\e" notin output

when defined(windows):
  # Not a pass: these cases are not run here.
  echo "NOT RUN on Windows: the terminal cases of this test need a POSIX " &
    "pseudo-terminal; they run on Linux and macOS. The pipe cases run."

suite "test_cs_m5b_no_color_and_not_a_terminal":

  setup:
    if scratch.len == 0:
      scratch = createTempDir("clispec_m5b_", "")
      depotExe = scratch / addFileExt("depot", ExeExt)
      let (output, code) = execCmdEx(quoteShellCommand([compilerExe(), "c",
        "--hints:off", "--skipParentCfg", "--skipUserCfg",
        "--path:" & srcDir, "--nimcache:" & (scratch / "nimcache"),
        "-o:" & depotExe, fixtureSource]))
      checkpoint(output)
      doAssert code == 0, "the fixture does not compile:\n" & output

  when not defined(windows):
    test "a pseudo-terminal can be opened":
      let r = onTerminal(["build", "-h"], [("TERM", "xterm")], 120)
      check r.code == 0
      check r.output.len > 0

    test "on a terminal: styled, as wide as the terminal, at most 100":
      # NO_COLOR set but empty does not turn colour off.
      let r = onTerminal(["build", "-h"],
        [("TERM", "xterm"), ("NO_COLOR", "")], 90)
      check r.code == 0
      check r.output == page(["build"], 90, true)
      checkStyled(r.output, page(["build"], 90, false))
      # 120 columns: capped at 100.
      let wide = onTerminal(["-h"], [("TERM", "xterm")], 120)
      check wide.output == page([], 100, true)
      checkStyled(wide.output, page([], 100, false))
      for line in cliStripStyles(wide.output).splitLines():
        check line.len <= 100
      # The long page too.
      let long = onTerminal(["build", "--help"], [("TERM", "xterm")], 120)
      var layout = cliDefaultHelpLayout
      layout.width = 100
      check long.output == Depot.helpText(["build"], layout = layout,
        long = true, styled = true)
      checkStyled(long.output, Depot.helpText(["build"], layout = layout,
        long = true))

    test "on a terminal: COLUMNS wins over the terminal's width":
      let narrow = onTerminal(["build", "-h"],
        [("TERM", "xterm"), ("COLUMNS", "60")], 120)
      check narrow.output == page(["build"], 60, true)
      checkStyled(narrow.output, page(["build"], 60, false))
      # COLUMNS=160: the 160-column page, which is capped at 100.
      let wide = onTerminal(["build", "-h"],
        [("TERM", "xterm"), ("COLUMNS", "160")], 80)
      check wide.output == page(["build"], 160, true)
      check page(["build"], 160, false) == page(["build"], 100, false)
      checkStyled(wide.output, page(["build"], 160, false))

    test "on a terminal: NO_COLOR, TERM=dumb and color = never are plain":
      for env in [@[("TERM", "xterm"), ("NO_COLOR", "1")],
                  @[("TERM", "dumb")],
                  @[("TERM", "xterm"), ("DEPOT_FIXTURE_COLOR", "never")]]:
        let r = onTerminal(["build", "-h"], env, 90)
        checkpoint($env)
        check r.code == 0
        checkPlain(r.output)
        check r.output == page(["build"], 90, false)
        # The same page styled, once the escapes are removed.
        checkStyled(page(["build"], 90, true), r.output)

    test "on a terminal: a usage error is styled":
      let r = onTerminal(["biuld"], [("TERM", "xterm")], 120)
      check r.code == 2
      let e = usageError(["biuld"])
      check r.output == cliErrorText(e, styled = true)
      checkStyled(r.output, cliErrorText(e))
      let plain = onTerminal(["build", "--job", "3"],
        [("TERM", "xterm"), ("NO_COLOR", "1")], 120)
      check plain.code == 2
      check plain.output == cliErrorText(usageError(["build", "--job", "3"]))
      checkPlain(plain.output)
      checkStyled(cliErrorText(usageError(["build", "--job", "3"]),
        styled = true), plain.output)

    test "on a terminal: JSON help is never styled":
      let r = onTerminal(["--help=json"], [("TERM", "xterm")], 120)
      check r.code == 0
      check r.output == Depot.helpJson()
      checkPlain(r.output)

  test "through a pipe: plain, 80 columns or COLUMNS":
    let r = throughPipes(["build", "-h"], [("TERM", "xterm")])
    check r.code == 0
    check r.errors == ""
    checkPlain(r.output)
    check r.output == page(["build"], 80, false)
    checkStyled(page(["build"], 80, true), r.output)
    for (columns, width) in [("60", 60), ("160", 100), ("100", 100),
                             ("abc", 80), ("0", 80), ("-5", 80)]:
      let c = throughPipes(["build", "-h"],
        [("TERM", "xterm"), ("COLUMNS", columns)])
      checkpoint("COLUMNS=" & columns)
      check c.code == 0
      checkPlain(c.output)
      check c.output == page(["build"], width, false)
      checkStyled(page(["build"], width, true), c.output)

  test "through a pipe: NO_COLOR and TERM=dumb are plain, color = always wins":
    for env in [@[("TERM", "xterm"), ("NO_COLOR", "1")], @[("TERM", "dumb")]]:
      checkpoint($env)
      let r = throughPipes(["build", "-h"], env)
      check r.code == 0
      checkPlain(r.output)
      check r.output == page(["build"], 80, false)
      let e = throughPipes(["biuld"], env)
      check e.code == 2
      checkPlain(e.errors)
      check e.errors == cliErrorText(usageError(["biuld"]))
      # Forced by the program, colour does not ask NO_COLOR or TERM.
      let forced = throughPipes(["build", "-h"],
        env & @[("DEPOT_FIXTURE_COLOR", "always")])
      check forced.code == 0
      check forced.output == page(["build"], 80, true)
      checkStyled(forced.output, r.output)

  test "through a pipe: color = always styles":
    let r = throughPipes(["-h"],
      [("TERM", "xterm"), ("DEPOT_FIXTURE_COLOR", "always")])
    check r.code == 0
    check r.output == page([], 80, true)
    checkStyled(r.output, page([], 80, false))
    let e = throughPipes(["biuld"], [("DEPOT_FIXTURE_COLOR", "always")])
    check e.code == 2
    check e.output == ""
    check e.errors == cliErrorText(usageError(["biuld"]), styled = true)
    checkStyled(e.errors, cliErrorText(usageError(["biuld"])))

  test "through a pipe: the error block on standard error":
    let r = throughPipes(["biuld"], [("TERM", "xterm")])
    check r.code == 2
    check r.output == ""
    checkPlain(r.errors)
    check r.errors == """error: unknown subcommand 'biuld' for 'depot'; expected one of: build, remote

  tip: a similar subcommand exists: 'build'

Usage: depot [options] <command>

For more information, try 'depot --help'.
"""
    checkStyled(cliErrorText(usageError(["biuld"]), styled = true), r.errors)
    let v = throughPipes(["build", "--profile", "relase"], [])
    check v.code == 2
    check v.errors == cliErrorText(usageError(["build", "--profile",
      "relase"]))
    check "  tip: a similar value exists: 'release'\n" in v.errors

  test "a command line the program accepts":
    let r = throughPipes(["build", "-j", "2", "app"], [])
    check r.code == 0 and r.output == "OK\n" and r.errors == ""
