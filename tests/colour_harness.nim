## Runs the ``depot`` fixture (``tests/fixtures/cs_m5b_help/depot.nim``) the
## way the colour tests need: built with ``-d:`` defines, on a
## pseudo-terminal that plays the terminal (it answers the background
## query, or stays silent) and through pipes, each with exactly the
## environment the test gives.
##
## Used by ``test_cs_m5c_colour_detection`` and
## ``test_cs_m5c_styled_goldens``. It kills only the process it started, by
## its pid, and every read has a deadline.

import std/[os, osproc, streams, strtabs, strutils, times]

when not defined(windows):
  import std/posix

import clispec

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()
  srcDir = repoDir / "src"
  fixtureSource* = testsDir / "fixtures" / "cs_m5b_help" / "depot.nim"
  deadlineSeconds = 60.0

type Outcome* = object
  output*: string
    ## Standard output (on the terminal: standard output and error, without
    ## the background query when the program sent one).
  errors*: string
    ## Standard error, through pipes.
  code*: int
  queried*: bool
    ## The program wrote ``CliBackgroundQuery`` to the terminal.
  seconds*: float
    ## How long the program ran.

proc nimCommand*(compiler, scratch, name, command: string;
                 defines: openArray[string]; output = ""): (string, int) =
  ## Runs ``<compiler> <command>`` on the fixture with ``defines`` (``-d:``
  ## each), its nimcache under ``scratch``; the output and exit code. The
  ## test passes the compiler that built it.
  var args = @[compiler, command, "--hints:off", "--skipParentCfg",
    "--skipUserCfg", "--path:" & srcDir,
    "--nimcache:" & (scratch / ("nimcache_" & name))]
  for d in defines:
    args.add("-d:" & d)
  if output.len > 0:
    args.add("-o:" & output)
  args.add(fixtureSource)
  execCmdEx(quoteShellCommand(args))

proc buildFixture*(compiler, scratch, name: string;
                   defines: openArray[string] = []): string =
  ## The fixture compiled by ``compiler`` with ``defines`` into
  ## ``scratch``; its path.
  result = scratch / addFileExt("depot_" & name, ExeExt)
  let (output, code) = nimCommand(compiler, scratch, name, "c", defines,
    result)
  doAssert code == 0, "the fixture (" & name & ") does not compile:\n" &
    output

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

  proc onTerminal*(exe: string; args: openArray[string];
                   env: openArray[(string, string)]; columns = 90;
                   answer = ""): Outcome =
    ## Runs ``exe`` as the session leader of a new pseudo-terminal
    ## ``columns`` wide, with exactly ``env``, and reads everything it
    ## writes until it exits. When it sends the background query, the
    ## terminal writes ``answer`` back (nothing when ``answer`` is empty).
    let master = posix_openpt(O_RDWR or O_NOCTTY)
    doAssert master >= 0, "posix_openpt failed: no pseudo-terminal"
    doAssert grantpt(master) == 0 and unlockpt(master) == 0,
      "grantpt/unlockpt failed"
    let slaveName = $ptsname(master)
    var size = Winsize(ws_row: 50, ws_col: cushort(columns))
    discard ioctlArg(master, TIOCSWINSZ, addr size)
    var argvList = @[exe]
    for a in args:
      argvList.add(a)
    var envList: seq[string] = @[]
    for (k, v) in env:
      envList.add(k & "=" & v)
    let argv = allocCStringArray(argvList)
    let envp = allocCStringArray(envList)
    let cSlave = slaveName.cstring
    let cExe = exe.cstring
    let started = epochTime()
    let pid = fork()
    doAssert pid >= 0, "fork failed"
    if pid == 0:
      discard setsid()
      let slave = posix.open(cSlave, O_RDWR)
      if slave < 0:
        exitnow(126)
      discard ioctlArg(slave, TIOCSCTTY, 0)
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
    let deadline = started + deadlineSeconds
    var text = ""
    var answered = false
    var timedOut = false
    var exited = false
    var st: cint
    proc readAvailable(wait: cint): bool =
      ## Reads what the terminal has; false when there is nothing (after
      ## ``wait`` ms) or the slave side is closed.
      var fds = [TPollfd(fd: master, events: POLLIN)]
      if poll(addr fds[0], 1, wait) <= 0:
        return false
      var buf: array[4096, char]
      let n = read(master, addr buf[0], buf.len)
      if n <= 0:
        return false
      for k in 0 ..< n:
        text.add(buf[k])
      true
    while true:
      if epochTime() > deadline:
        timedOut = true
        break
      let got = readAvailable(20)
      if not answered and answer.len > 0 and CliBackgroundQuery in text:
        answered = true
        discard write(master, unsafeAddr answer[0], answer.len)
      if not got:
        if waitpid(pid, st, WNOHANG) == pid:
          exited = true
          while readAvailable(0):
            discard
          break
    result.seconds = epochTime() - started
    discard close(master)
    if timedOut:
      discard kill(pid, SIGKILL)
    if not exited:
      discard waitpid(pid, st, 0)
    doAssert not timedOut, "the fixture did not finish within " &
      $deadlineSeconds & " s; output so far:\n" & text
    result.code = if WIFEXITED(st): WEXITSTATUS(st) else: -1
    result.queried = CliBackgroundQuery in text
    if result.queried:
      text = text.replace(CliBackgroundQuery, "")
    result.output = text.replace("\r\n", "\n")

proc throughPipes*(exe: string; args: openArray[string];
                   env: openArray[(string, string)]): Outcome =
  ## Runs ``exe`` with its standard output and error on pipes and exactly
  ## ``env`` (on Windows, plus ``SYSTEMROOT``, which a process needs).
  let table = newStringTable(modeCaseSensitive)
  when defined(windows):
    table["SYSTEMROOT"] = getEnv("SYSTEMROOT")
  for (k, v) in env:
    table[k] = v
  let started = epochTime()
  let p = startProcess(exe, args = args, env = table, options = {})
  try:
    result.output = p.outputStream.readAll()
    result.errors = p.errorStream.readAll()
    result.code = p.waitForExit(int(deadlineSeconds * 1000))
  finally:
    p.close()
  result.seconds = epochTime() - started
