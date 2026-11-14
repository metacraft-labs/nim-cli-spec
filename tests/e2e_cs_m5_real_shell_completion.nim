## e2e_cs_m5_real_shell_completion: real shells, driven in a pseudo-terminal,
## complete a fixture program's subcommand, flag and value through the
## scripts clispec generates.
##
## The fixture (``tests/fixtures/cs_m5_shell/shx.nim``) is compiled with the
## compiler that built this test. For each shell the test:
##
## 1. starts the shell interactively on a pseudo-terminal it opens itself,
##    with a scratch ``HOME``, ``ZDOTDIR`` and XDG directories and none of
##    the user's startup files (``bash --norc --noprofile``, ``zsh -f``,
##    ``fish --no-config``, ``pwsh -NoProfile``);
## 2. types a partial command line, presses Tab, then Enter, and reads the
##    line the fixture prints: the words it received. That is what the shell
##    completed, so the assertions are on the shell's own output, not on the
##    script. A control case runs the same keystrokes before the script is
##    loaded and must come back uncompleted, which shows the completion came
##    from the script;
## 3. for fish and PowerShell, also asks the shell's completion machinery
##    for the full candidate list (``complete -C``, ``TabExpansion2``) and
##    compares it exactly.
##
## Cases: a subcommand (``shx bui``), a nested one (``shx remote a``), a flag
## (``--jo``), an enum value after a flag (``--mode rel``), a value written
## ``--mode=d``, and a dynamic value that contains a space (``--note my``,
## completed to ``my file.txt`` and received as one word).
##
## Portability: on Windows there is no POSIX pseudo-terminal, so the bash,
## zsh and fish legs are reported as skipped there, and PowerShell runs the
## ``TabExpansion2`` leg only, which is the function PowerShell's own Tab key
## calls: for PowerShell 7 (``pwsh``) and for Windows PowerShell 5.1
## (``powershell``), each when it is on ``PATH``. A shell whose executable is not
## on ``PATH`` is skipped with a ``SKIP-LOUD`` line; when the environment
## variable ``CLISPEC_E2E_REQUIRE`` (a comma-separated list, set by the dev
## shell, which provides every shell) names it, its absence fails the test.
## When no shell ran at all, the test fails.
##
## Every read has a deadline. The test kills only the processes it started
## (each shell's pid, by number); it never kills by name. Nothing is mocked:
## the shells, their completion systems and the fixture are real.

import std/[base64, os, osproc, streams, strtabs, strutils, tempfiles, times,
  unicode, unittest]

when not defined(windows):
  import std/posix

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()
  srcDir = repoDir / "src"
  fixtureSource = testsDir / "fixtures" / "cs_m5_shell" / "shx.nim"
  readyMarker = "CLISPEC_READY"

proc compilerExe(): string =
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

proc required(shell: string): bool =
  shell in getEnv("CLISPEC_E2E_REQUIRE").split(',')

type
  Case = object
    typed: string
      ## Typed before Tab.
    after: string
      ## Typed after Tab, before Enter.
    expected: string
      ## The fixture's ``ARGV:`` line.

const
  completingCases = [
    Case(typed: "shx bui", expected: "ARGV:<build> OK"),
    Case(typed: "shx remote a", after: "x",
      expected: "ARGV:<remote><add><x> OK"),
    Case(typed: "shx build --jo", after: "3",
      expected: "ARGV:<build><--jobs><3> OK"),
    Case(typed: "shx build --mode rel",
      expected: "ARGV:<build><--mode><release> OK"),
    Case(typed: "shx build --mode=d",
      expected: "ARGV:<build><--mode=debug> OK"),
    Case(typed: "shx build --note my",
      expected: "ARGV:<build><--note><my file.txt> OK"),
  ]
  control = Case(typed: "shx bui",
    expected: "ARGV:<bui> ERROR unknown subcommand 'bui' for 'shx'; " &
      "expected one of: build, remote")

var scratch = ""
var binDir = ""
var ranShells: seq[string] = @[]
var skippedShells: seq[string] = @[]

proc shellEnv(): seq[(string, string)] =
  ## A minimal environment: scratch home and XDG directories, the fixture
  ## first on PATH.
  let home = scratch / "home"
  for d in ["home", "config", "data", "cache", "state", "work"]:
    createDir(scratch / d)
  writeFile(scratch / "inputrc", "set bell-style none\n")
  result = @[
    ("PATH", binDir & $PathSep & getEnv("PATH")),
    ("HOME", home), ("USERPROFILE", home), ("ZDOTDIR", home),
    ("XDG_CONFIG_HOME", scratch / "config"),
    ("XDG_DATA_HOME", scratch / "data"),
    ("XDG_CACHE_HOME", scratch / "cache"),
    ("XDG_STATE_HOME", scratch / "state"),
    ("TERM", "xterm-256color"),
    ("LANG", (if existsEnv("LANG"): getEnv("LANG") else: "C.UTF-8")),
    ("INPUTRC", scratch / "inputrc"),
    ("PS1", "CLISPEC_PROMPT> "),
    ("POWERSHELL_TELEMETRY_OPTOUT", "1"),
    ("POWERSHELL_UPDATECHECK", "Off"),
    ("DOTNET_CLI_TELEMETRY_OPTOUT", "1"),
    ("DOTNET_NOLOGO", "1"),
  ]
  when defined(windows):
    for name in ["SystemRoot", "SYSTEMROOT", "TEMP", "TMP", "ComSpec",
        "PATHEXT", "LOCALAPPDATA", "APPDATA", "ProgramFiles", "WINDIR"]:
      if existsEnv(name):
        result.add((name, getEnv(name)))

proc writeScript(shell, file: string) =
  ## The fixture's own ``completion <shell>`` output, saved for sourcing.
  let (output, code) = execCmdEx(quoteShellCommand(
    [binDir / addFileExt("shx", ExeExt), "completion", shell]))
  doAssert code == 0, output
  writeFile(file, output)

# ---------------------------------------------------------------------------
# PowerShell's completion function, without a terminal (every OS).
# ---------------------------------------------------------------------------

proc tabExpansion(pwsh: string; lines: openArray[string]):
    tuple[lists: seq[seq[string]], output: string, exitCode: int] =
  ## For each line, the ``CompletionText`` of every match ``TabExpansion2``
  ## returns with the cursor at the end of the line.
  let script = scratch / "shx.ps1"
  writeScript("powershell", script)
  var program = ". '" & script.replace("'", "''") & "'\n"
  for line in lines:
    program.add("'CASE'\n$r = TabExpansion2 -inputScript '" &
      line.replace("'", "''") & "' -cursorColumn " &
      # PowerShell counts UTF-16 code units; every test line is in the BMP.
      $line.runeLen & "\n" &
      # Each candidate as base64 of its UTF-8 bytes: Windows PowerShell
      # writes redirected output in the console's code page, which cannot
      # carry every character.
      "foreach ($m in $r.CompletionMatches) { 'CAND:' + " &
      "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(" &
      "$m.CompletionText)) }\n")
  program.add("'DONE'\n")
  let file = scratch / "tabexpansion.ps1"
  # With a byte-order mark, so Windows PowerShell 5.1 reads it as UTF-8.
  writeFile(file, "\xEF\xBB\xBF" & program)
  var env = newStringTable(modeCaseSensitive)
  for (k, v) in shellEnv():
    env[k] = v
  let p = startProcess(pwsh, workingDir = scratch / "work",
    args = ["-NoProfile", "-NonInteractive", "-File", file], env = env,
    options = {poStdErrToStdOut})
  # The read ends when PowerShell exits; a hung PowerShell is killed by
  # its own pid after two minutes.
  let started = epochTime()
  var exitCode = -1
  while true:
    exitCode = p.peekExitCode()
    if exitCode != -1:
      break
    if epochTime() - started > 120:
      p.kill()
      exitCode = p.waitForExit()
      break
    sleep(100)
  result.output = p.outputStream.readAll()
  result.exitCode = exitCode
  p.close()
  var current = -1
  for l in result.output.splitLines():
    let s = l.strip(leading = false)
    if s == "CASE":
      result.lists.add(@[])
      inc current
    elif s.startsWith("CAND:") and current >= 0:
      result.lists[current].add(try: decode(s[5 .. ^1])
                                except ValueError: "<undecodable " & s & ">")

# ---------------------------------------------------------------------------
# A pseudo-terminal driver (POSIX).
# ---------------------------------------------------------------------------

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

  type
    Session = object
      name: string
      pid: Pid
      fd: cint
      output: string
        ## Everything read so far.
      seen: int
        ## How much of ``output`` earlier waits consumed.
      exited: bool

  proc spawn(name, exe: string; args: openArray[string];
             env: openArray[(string, string)]; cwd: string): Session =
    ## Starts ``exe`` as the session leader of a new pseudo-terminal.
    let master = posix_openpt(O_RDWR or O_NOCTTY)
    doAssert master >= 0, "posix_openpt failed"
    doAssert grantpt(master) == 0 and unlockpt(master) == 0
    let slaveName = $ptsname(master)
    var size = Winsize(ws_row: 50, ws_col: 250)
    discard ioctlArg(master, TIOCSWINSZ, addr size)
    # Everything the child needs is prepared before fork: after it, the
    # child only makes system calls.
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
    let cCwd = cwd.cstring
    let pid = fork()
    doAssert pid >= 0, "fork failed"
    if pid == 0:
      discard setsid()
      let slave = posix.open(cSlave, O_RDWR)
      if slave < 0:
        exitnow(126)
      discard ioctlArg(slave, TIOCSCTTY, 0)
      discard dup2(slave, 0)
      discard dup2(slave, 1)
      discard dup2(slave, 2)
      if slave > 2:
        discard close(slave)
      discard close(master)
      discard chdir(cCwd)
      discard execve(cExe, argv, envp)
      exitnow(127)
    deallocCStringArray(argv)
    deallocCStringArray(envp)
    Session(name: name, pid: pid, fd: master)

  proc send(s: var Session; text: string) =
    var off = 0
    while off < text.len:
      let n = write(s.fd, unsafeAddr text[off], text.len - off)
      if n <= 0:
        break
      off += n

  proc answerQueries(s: var Session; fresh: string) =
    ## Terminal queries a shell waits for: the cursor position and the
    ## primary device attributes.
    if "\e[6n" in fresh:
      s.send("\e[1;1R")
    if "\e[c" in fresh or "\e[0c" in fresh:
      s.send("\e[?62;22c")

  proc pump(s: var Session; waitMs: int): bool =
    ## Reads what is available within ``waitMs``; false when nothing came.
    var fds = [TPollfd(fd: s.fd, events: POLLIN)]
    let ready = poll(addr fds[0], 1, cint(waitMs))
    if ready <= 0:
      return false
    var buf: array[4096, char]
    let n = read(s.fd, addr buf[0], buf.len)
    if n <= 0:
      s.exited = true
      return false
    var fresh = newString(n)
    copyMem(addr fresh[0], addr buf[0], n)
    s.output.add(fresh)
    s.answerQueries(fresh)
    true

  proc waitFor(s: var Session; marker: string; timeoutMs: int): int =
    ## Reads until ``marker`` appears after what earlier waits consumed;
    ## returns its index, or -1 at the deadline.
    let deadline = epochTime() + timeoutMs / 1000
    while true:
      let at = s.output.find(marker, s.seen)
      if at >= 0:
        s.seen = at + marker.len
        return at
      if s.exited or epochTime() > deadline:
        return -1
      discard s.pump(200)

  proc settle(s: var Session; quietMs, timeoutMs: int) =
    ## Reads until the terminal has been quiet for ``quietMs``.
    let deadline = epochTime() + timeoutMs / 1000
    while epochTime() < deadline:
      if not s.pump(quietMs):
        return

  proc lineAfter(s: var Session; marker: string; timeoutMs: int): string =
    ## The rest of the line on which ``marker`` next appears.
    let at = s.waitFor(marker, timeoutMs)
    if at < 0:
      return ""
    discard s.waitFor("\n", timeoutMs)
    result = s.output[at ..< s.seen].strip()

  proc stop(s: var Session) =
    ## Ends the session: ``exit``, then SIGKILL to this session's own pid
    ## if it is still running. Nothing else is signalled.
    if s.pid <= 0:
      return
    s.send("\rexit\r")
    let deadline = epochTime() + 5
    var status: cint
    while epochTime() < deadline:
      discard s.pump(100)
      if waitpid(s.pid, status, WNOHANG) == s.pid:
        s.pid = 0
        break
    if s.pid > 0:
      discard kill(s.pid, SIGKILL)
      discard waitpid(s.pid, status, 0)
      s.pid = 0
    discard close(s.fd)

  proc runCase(s: var Session; c: Case; spaceAfterTab: bool): string =
    ## Types ``c``, Tab between its parts, Enter; the fixture's line.
    ## ``spaceAfterTab``: the shell does not end a completed word with a
    ## space (PowerShell), so the user types one before the next word.
    s.settle(300, 10_000)
    s.send(c.typed & "\t")
    s.settle(400, 5000)
    s.send((if spaceAfterTab and c.after.len > 0: " " else: "") & c.after &
      "\r")
    result = s.lineAfter("ARGV:", 15_000)

  proc ready(s: var Session; command: string; timeoutMs: int): bool =
    ## Runs ``command`` followed by an echo of the ready marker (spelt so
    ## that the echoed command line does not contain it) and waits for it.
    s.settle(300, 10_000)
    s.send(command & "\r")
    s.waitFor(readyMarker, timeoutMs) >= 0

  type Outcome = object
    label, got, expected: string

  proc runShell(s: var Session; setup, echoReady: string; startMs: int;
                spaceAfterTab = false): seq[Outcome] =
    ## The control case, then the script, then every case; the test body
    ## compares each outcome. Nothing is typed until the shell has started
    ## and gone quiet: .NET reads the terminal's answer to its cursor query
    ## from the same input, so PowerShell mishandles typeahead.
    s.settle(1500, startMs)
    result.add(Outcome(label: "started", expected: "ready",
      got: (if s.ready(echoReady, startMs): "ready" else: "no ready marker")))
    result.add(Outcome(label: "before the script: " & control.typed &
      " <Tab>", got: s.runCase(control, spaceAfterTab),
      expected: control.expected))
    result.add(Outcome(label: "script loaded", expected: "ready",
      got: (if s.ready(setup & "; " & echoReady, startMs): "ready"
            else: "no ready marker")))
    for c in completingCases:
      result.add(Outcome(label: c.typed & " <Tab> " & c.after,
        got: s.runCase(c, spaceAfterTab), expected: c.expected))

  proc transcript(s: Session): string =
    ## The terminal output, with escape sequences made visible. Also saved
    ## under ``$CLISPEC_E2E_TRANSCRIPTS`` when that names a directory.
    result = s.output.replace("\e", "<ESC>")
    let dir = getEnv("CLISPEC_E2E_TRANSCRIPTS")
    if dir.len > 0 and dirExists(dir):
      writeFile(dir / (s.name & ".transcript"), result)

  template checkOutcomes(s: Session; outcomes: seq[Outcome]) =
    for o in outcomes:
      checkpoint(s.name & ": " & o.label & " -> " & o.got)
      check o.got == o.expected

proc findShell(names: openArray[string]): string =
  ## The first of ``names`` on PATH, its version printed so the log names
  ## the shell that ran.
  for name in names:
    let exe = findExe(name)
    if exe.len > 0:
      # Windows PowerShell has no --version; both PowerShells answer this.
      let versionArgs = if name in ["pwsh", "powershell"]:
          @[exe, "-NoProfile", "-NonInteractive", "-Command",
            "'PowerShell ' + $PSVersionTable.PSVersion.ToString()"]
        else: @[exe, "--version"]
      let (output, code) = execCmdEx(quoteShellCommand(versionArgs))
      var version = "unknown version"
      if code == 0:
        for line in output.splitLines():
          if line.strip().len > 0:
            version = line.strip()
            break
      echo "shell: ", name, " (", exe, "): ", version
      return exe
  ""

template skipLoud(shell, why: string) =
  ## Reports a leg that did not run; fails when the environment requires
  ## the shell.
  echo "SKIP-LOUD: ", shell, ": ", why, "; this shell's leg did NOT run"
  skippedShells.add(shell)
  checkpoint("CLISPEC_E2E_REQUIRE=" & getEnv("CLISPEC_E2E_REQUIRE"))
  check not required(shell)

suite "e2e_cs_m5_real_shell_completion":

  setup:
    if scratch.len == 0:
      scratch = createTempDir("clispec_e2e_", "")
      binDir = scratch / "bin"
      createDir(binDir)
      let (output, code) = execCmdEx(quoteShellCommand([compilerExe(), "c",
        "--hints:off", "--skipParentCfg", "--skipUserCfg",
        "--path:" & srcDir, "--nimcache:" & (scratch / "nimcache"),
        "-o:" & (binDir / addFileExt("shx", ExeExt)), fixtureSource]))
      checkpoint(output)
      doAssert code == 0, "the fixture does not compile:\n" & output

  test "bash":
    when defined(windows):
      skipLoud("bash", "no POSIX pseudo-terminal on Windows")
    else:
      let exe = findShell(["bash"])
      if exe.len == 0:
        skipLoud("bash", "bash is not on PATH")
      else:
        let script = scratch / "shx.bash"
        writeScript("bash", script)
        var s = spawn("bash", exe, ["--norc", "--noprofile", "-i"],
          shellEnv(), scratch / "work")
        try:
          s.checkOutcomes(s.runShell("source " & quoteShell(script),
            "echo CLISPEC_READ''Y", 20_000))
        finally:
          checkpoint(s.transcript)
          s.stop()
        ranShells.add("bash")

  test "zsh":
    when defined(windows):
      skipLoud("zsh", "no POSIX pseudo-terminal on Windows")
    else:
      let exe = findShell(["zsh"])
      if exe.len == 0:
        skipLoud("zsh", "zsh is not on PATH")
      else:
        let script = scratch / "_shx"
        writeScript("zsh", script)
        var s = spawn("zsh", exe, ["-f", "-i"], shellEnv(), scratch / "work")
        try:
          s.checkOutcomes(s.runShell(
            "autoload -U compinit && compinit -u -D && source " &
            quoteShell(script), "echo CLISPEC_READ''Y", 20_000))
        finally:
          checkpoint(s.transcript)
          s.stop()
        ranShells.add("zsh")

  test "fish":
    when defined(windows):
      skipLoud("fish", "no POSIX pseudo-terminal on Windows")
    else:
      let exe = findShell(["fish"])
      if exe.len == 0:
        skipLoud("fish", "fish is not on PATH")
      else:
        let script = scratch / "shx.fish"
        writeScript("fish", script)
        var s = spawn("fish", exe, ["--no-config", "-i"], shellEnv(),
          scratch / "work")
        try:
          s.checkOutcomes(s.runShell("source " & quoteShell(script),
            "echo CLISPEC_READ''Y", 30_000))
          # fish's completion machinery, asked for the whole list.
          s.send("complete -C 'shx '; complete -C 'shx build --mode '; " &
            "echo CLISPEC_LIST''_END\r")
          let at = s.waitFor("CLISPEC_LIST_END", 15_000)
          check at >= 0
          var listed: seq[string] = @[]
          for line in s.output[0 ..< max(at, 0)].splitLines():
            let l = line.strip()
            for want in ["build\tBuild a project", "remote\tRemotes",
                "debug", "release"]:
              if l == want:
                listed.add(l)
          check listed == @["build\tBuild a project", "remote\tRemotes",
            "debug", "release"]
        finally:
          checkpoint(s.transcript)
          s.stop()
        ranShells.add("fish")

  template tabExpansionLeg(exe: string) =
    ## TabExpansion2, the function PowerShell's Tab key calls, for every
    ## case. Also: a non-ASCII word, which travels base64-encoded to the
    ## program and back as UTF-8, and a word inside an open single quote.
    block:
      let (lists, output, exitCode) = tabExpansion(exe, ["shx ", "shx bui",
        "shx build --mode ", "shx build --note my", "shx build --mode=d",
        "shx remote ", "shx build --note \u00FC", "shx build --note 'my"])
      checkpoint(exe & ": TabExpansion2 output:\n" & output)
      check exitCode == 0
      check "DONE" in output
      check lists.len == 8
      if lists.len == 8:
        check lists[0] == @["build", "remote"]
        check lists[1] == @["build"]
        check lists[2] == @["debug", "release"]
        check lists[3] == @["'my file.txt'"]
        check lists[4] == @["--mode=debug"]
        check lists[5] == @["add"]
        check lists[6] == @["\u00FCber.txt"]
        check lists[7] == @["'my file.txt'"]

  test "PowerShell":
    # PowerShell 7 (pwsh) on every OS; on Windows also Windows PowerShell
    # 5.1 (powershell.exe), which is a different engine with its own
    # argument passing and output encoding.
    let pwsh = findShell(["pwsh"])
    if pwsh.len == 0:
      skipLoud("pwsh", "pwsh is not on PATH")
    else:
      tabExpansionLeg(pwsh)
      when not defined(windows):
        # The interactive leg: PSReadLine's Tab in a pseudo-terminal.
        let script = scratch / "shx.ps1"
        var s = spawn("pwsh", pwsh, ["-NoProfile", "-NoLogo"], shellEnv(),
          scratch / "work")
        try:
          s.checkOutcomes(s.runShell(". " & quoteShell(script),
            "function prompt { 'CLISPEC_PROMPT> ' }; " &
            "Write-Output ('CLISPEC_' + 'READY')", 60_000,
            spaceAfterTab = true))
        finally:
          checkpoint(s.transcript)
          s.stop()
      ranShells.add("pwsh")
    when defined(windows):
      let windowsPowerShell = findShell(["powershell"])
      if windowsPowerShell.len == 0:
        skipLoud("powershell", "Windows PowerShell is not on PATH")
      else:
        tabExpansionLeg(windowsPowerShell)
        ranShells.add("powershell")

  test "at least one shell ran":
    echo "shells run: ", ranShells.join(", "),
      (if skippedShells.len > 0: "; SKIPPED: " & skippedShells.join(", ")
       else: "")
    check ranShells.len > 0
    if scratch.len > 0:
      removeDir(scratch)
