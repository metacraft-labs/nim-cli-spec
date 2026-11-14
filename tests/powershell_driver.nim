## powershell_driver: the command line that runs a PowerShell program for
## the end-to-end completion test (``e2e_cs_m5_real_shell_completion``),
## kept apart from that test so a unit test can check it on any OS.
##
## Why no script file. On Windows, PowerShell's execution policy decides
## whether a *script file* (``.ps1``, ``.psm1``, ``.ps1xml`` and the
## profile) may run. When no scope sets a policy, the effective policy of a
## Windows client is ``Restricted``, which "permits individual commands, but
## doesn't allow scripts", and Group Policy can impose ``Restricted`` or
## ``AllSigned`` whatever a process asks for
## (https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies).
## The policy does not apply to commands: a ``-Command`` or
## ``-EncodedCommand`` argument, or a string passed to ``Invoke-Expression``.
##
## So the driver is passed as ``-EncodedCommand`` (no ``-File``), and it
## loads the completion script the way the README tells users to:
## ``tool completion powershell | Out-String | Invoke-Expression``, never by
## dot-sourcing a saved ``.ps1``. That works under every policy, including
## one Group Policy enforces, which ``-ExecutionPolicy Bypass`` (a
## ``Process``-scope setting that Group Policy overrides) would not, and it
## changes no policy on the machine.
##
## ``-EncodedCommand`` takes the base64 of the program's UTF-16LE bytes
## (``pwsh -?``), so every character, including non-ASCII ones, reaches
## PowerShell exactly, independent of the console code page and of how a
## PowerShell version re-parses its command line. Windows limits a whole
## command line to 32767 UTF-16 code units
## (https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw);
## ``powerShellDriverArgs`` refuses a program that would not fit.

import std/[base64, strutils, unicode]

const
  maxCommandLine* = 32_767
    ## CreateProcessW's limit on ``lpCommandLine``, in UTF-16 code units.
  commandLineReserve = 1_024
    ## Room left for the executable's path and the other arguments.

func utf16le*(s: string): string =
  ## ``s`` (UTF-8) as UTF-16LE bytes; a character outside the BMP becomes a
  ## surrogate pair.
  for r in s.runes:
    var c = int(r)
    if c >= 0x10000:
      c -= 0x10000
      for unit in [0xD800 + (c shr 10), 0xDC00 + (c and 0x3FF)]:
        result.add(char(unit and 0xFF))
        result.add(char(unit shr 8))
    else:
      result.add(char(c and 0xFF))
      result.add(char(c shr 8))

func powerShellLiteral*(s: string): string =
  ## ``s`` as a PowerShell single-quoted string (the test's paths and lines
  ## hold no typographic quotes).
  "'" & s.replace("'", "''") & "'"

func tabExpansionProgram*(fixtureExe: string;
    lines: openArray[string]): string =
  ## A program that loads ``fixtureExe``'s completion script as the README
  ## installs it, then prints, for each line, ``CASE`` and one
  ## ``CAND:<base64 of the UTF-8 CompletionText>`` per match
  ## ``TabExpansion2`` returns with the cursor at the end of the line, then
  ## ``DONE``.
  # Progress records (module loading in Windows PowerShell 5.1) would reach
  # a redirected stream as CLIXML; they carry nothing the test reads.
  result = "$ProgressPreference = 'SilentlyContinue'\n"
  result.add("& " & powerShellLiteral(fixtureExe) &
    " completion powershell | Out-String | Invoke-Expression\n")
  for line in lines:
    result.add("'CASE'\n$r = TabExpansion2 -inputScript " &
      powerShellLiteral(line) & " -cursorColumn " &
      # PowerShell counts UTF-16 code units.
      $(utf16le(line).len div 2) & "\n" &
      # Each candidate as base64 of its UTF-8 bytes: Windows PowerShell
      # writes redirected output in the console's code page, which cannot
      # carry every character.
      "foreach ($m in $r.CompletionMatches) { 'CAND:' + " &
      "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(" &
      "$m.CompletionText)) }\n")
  result.add("'DONE'\n")

func powerShellDriverArgs*(program: string): seq[string] =
  ## The arguments that run ``program`` in a fresh PowerShell (``pwsh`` or
  ## Windows PowerShell's ``powershell``) without a profile and without a
  ## script file, so no execution policy can refuse it. Raises
  ## ``ValueError`` when the encoded program would exceed Windows'
  ## command-line limit.
  let encoded = encode(utf16le(program))
  if encoded.len > maxCommandLine - commandLineReserve:
    raise newException(ValueError, "the PowerShell program encodes to " &
      $encoded.len & " characters; a Windows command line holds " &
      $maxCommandLine)
  @["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]
