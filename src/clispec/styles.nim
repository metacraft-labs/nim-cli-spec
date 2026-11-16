## Where help and errors go: whether to style them and how wide a page is.
##
## Colour
## ======
##
## Help and usage errors are styled only when the stream they are written to
## is a terminal, the environment variable ``NO_COLOR`` is unset or empty
## and ``TERM`` is not ``dumb``, unless the program forces it with
## ``CliOptions.color`` (``ccmAlways``, ``ccmNever``; ``ccmAuto``, the
## default, is the rule above). On Windows a terminal is a console on
## which virtual terminal processing (``ENABLE_VIRTUAL_TERMINAL_PROCESSING``)
## is on or can be turned on (``cliUseColor`` turns it on); any other
## stream gets plain text. The palette is cargo's, written as ANSI SGR
## sequences, each closed by ``ESC[0m``:
##
## =====================  =================  ===========================
## What                   Style              Sequence
## =====================  =================  ===========================
## headings               bold bright green  ``ESC[1;92m``
## literals               bold bright cyan   ``ESC[1;96m``
## placeholders           cyan               ``ESC[36m``
## ``error:``             bold bright red    ``ESC[1;91m``
## the offending word     yellow             ``ESC[33m``
## ``tip:``               bold bright green  ``ESC[1;92m``
## =====================  =================  ===========================
##
## Literals are flag spellings, command names and aliases, the program name
## and the words of a usage line, example command lines and suggestions;
## placeholders are ``<NAME>`` (with a list's ``...``) and the bracketed
## words of a usage line (``[options]``, ``[<packages>...]``). Descriptions,
## notes and prose are never styled. A styled text is the plain text with
## escape sequences added and nothing else changed (``cliStripStyles`` of
## it is the plain text), so its layout is the same: widths are measured on
## the visible text (``cliVisibleLen``).
##
## Width
## =====
##
## ``cliOutputWidth`` is the width a page printed to a stream gets: the
## environment variable ``COLUMNS`` when it is a positive integer, else the
## terminal's width when the stream is a terminal, else 80; at most 100.

import std/[os, strutils, terminal]

when defined(windows):
  import std/winlean

type
  CliColorMode* = enum
    ## Whether help and errors are styled (``CliOptions.color``).
    ccmAuto = "auto"
      ## When the stream is a terminal, ``NO_COLOR`` is unset or empty and
      ## ``TERM`` is not ``dumb``.
    ccmAlways = "always"
      ## Always, wherever the text goes.
    ccmNever = "never"
      ## Never.

  CliTextStyle* = enum
    ## The styles help and errors use (see the module documentation).
    ctsHeading = "\e[1;92m"
    ctsLiteral = "\e[1;96m"
    ctsPlaceholder = "\e[36m"
    ctsError = "\e[1;91m"
    ctsOffending = "\e[33m"
    ctsTip = "\e[1;92m"

const
  CliStyleReset* = "\e[0m"
    ## Ends every styled span.
  CliDefaultWidth* = 80
    ## The page width when neither ``COLUMNS`` nor a terminal gives one.
  CliMaxWidth* = 100
    ## The widest a page is, whatever ``COLUMNS`` or the terminal says.

func cliStyled*(text: string; style: CliTextStyle; on: bool): string =
  ## ``text`` in ``style`` when ``on`` (and ``text`` is not empty), else
  ## ``text`` itself.
  if on and text.len > 0: $style & text & CliStyleReset else: text

func cliStripStyles*(text: string): string =
  ## ``text`` without its ANSI escape sequences (``ESC[`` ... final byte).
  var i = 0
  while i < text.len:
    if text[i] == '\e' and i + 1 < text.len and text[i + 1] == '[':
      var j = i + 2
      while j < text.len and text[j] notin {'@' .. '~'}:
        inc j
      i = j + 1
    else:
      result.add(text[i])
      inc i

func cliVisibleLen*(text: string): int =
  ## The width ``text`` takes on a line: its length without escape
  ## sequences.
  cliStripStyles(text).len

func cliStyleUsage*(text: string; on: bool): string =
  ## A usage line (``tool build [options] <target>``) or a command line
  ## shown in prose (``tool build --help``): each word that starts with
  ## ``<`` or ``[`` is a placeholder, every other word a literal. Spaces
  ## are kept as they are.
  if not on:
    return text
  var i = 0
  while i < text.len:
    if text[i] == ' ':
      result.add(' ')
      inc i
      continue
    var j = i
    while j < text.len and text[j] != ' ':
      inc j
    let word = text[i ..< j]
    result.add(cliStyled(word, (if word[0] in {'<', '['}: ctsPlaceholder
                                else: ctsLiteral), true))
    i = j

func cliStyleNames*(text: string; on: bool): string =
  ## A list of names separated by ``", "`` (``build, b``): each name a
  ## literal.
  if not on:
    return text
  var parts: seq[string] = @[]
  for name in text.split(", "):
    parts.add(cliStyled(name, ctsLiteral, true))
  parts.join(", ")

func cliStyleSpellings*(text: string; on: bool): string =
  ## The left column of a flag or positional row (``-j, --jobs <N>``,
  ## ``--report[=<PATH>]``, ``--[no-]color``, ``[<packages>...]``): every
  ## spelling starting with ``-`` a literal, every ``<NAME>`` (with a
  ## following ``...``) and an optional positional (``[<NAME>...]``) a
  ## placeholder, the punctuation between them plain.
  if not on:
    return text
  var i = 0
  var plain = ""
  template flush() =
    result.add(plain)
    plain = ""
  while i < text.len:
    let c = text[i]
    let wordStart = i == 0 or text[i - 1] in {' ', ','}
    if c == '[' and wordStart and text.continuesWith("[<", i):
      # An optional positional, ``[<packages>...]``, as in a usage line.
      var j = text.find(']', i)
      j = if j < 0: text.len else: j + 1
      flush()
      result.add(cliStyled(text[i ..< j], ctsPlaceholder, true))
      i = j
    elif c == '<':
      var j = text.find('>', i)
      j = if j < 0: text.len else: j + 1
      if text.continuesWith("...", j):
        j += 3
      flush()
      result.add(cliStyled(text[i ..< j], ctsPlaceholder, true))
      i = j
    elif c == '-' and wordStart:
      var j = i
      while j < text.len and text[j] notin {' ', ',', '<', '='} and
          not (text[j] == '[' and not text.continuesWith("[no-]", j)):
        if text.continuesWith("[no-]", j):
          j += 5
        else:
          inc j
      flush()
      result.add(cliStyled(text[i ..< j], ctsLiteral, true))
      i = j
    else:
      plain.add(c)
      inc i
  flush()

when defined(windows):
  proc getConsoleMode(console: Handle; mode: ptr DWORD): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "GetConsoleMode".}
  proc setConsoleMode(console: Handle; mode: DWORD): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "SetConsoleMode".}

  proc enableEscapeSequences(stream: File): bool =
    ## Whether ``stream`` is a console that now interprets escape sequences:
    ## turns on its virtual terminal processing
    ## (``ENABLE_VIRTUAL_TERMINAL_PROCESSING``), false when it is not a
    ## console or the console refuses (before Windows 10).
    const enableVirtualTerminalProcessing = DWORD(0x0004)
    let console = get_osfhandle(getFileHandle(stream))
    if console == INVALID_HANDLE_VALUE:
      return false
    var mode: DWORD = 0
    if getConsoleMode(console, addr mode) == 0:
      return false
    if (mode and enableVirtualTerminalProcessing) != 0:
      return true
    setConsoleMode(console, mode or enableVirtualTerminalProcessing) != 0

proc cliUseColor*(stream: File; mode = ccmAuto): bool =
  ## Whether text written to ``stream`` is styled under ``mode``: for
  ## ``ccmAuto``, when ``stream`` is a terminal, ``NO_COLOR`` is unset or
  ## empty and ``TERM`` is not ``dumb``. On Windows the terminal must be a
  ## console that accepts virtual terminal processing, which this turns on;
  ## else the text is plain.
  case mode
  of ccmAlways: true
  of ccmNever: false
  of ccmAuto:
    if getEnv("NO_COLOR").len > 0 or getEnv("TERM") == "dumb" or
        not isatty(stream):
      false
    else:
      when defined(windows): enableEscapeSequences(stream)
      else: true

proc cliOutputWidth*(stream: File): int =
  ## The width of a page written to ``stream``: ``COLUMNS`` when it is a
  ## positive integer, else the terminal's width when ``stream`` is a
  ## terminal, else ``CliDefaultWidth``; at most ``CliMaxWidth``.
  result = 0
  let columns = getEnv("COLUMNS").strip()
  if columns.len > 0:
    try:
      result = max(parseInt(columns), 0)
    except ValueError:
      result = 0
  if result == 0 and isatty(stream):
    try:
      when defined(windows):
        result = terminalWidthIoctl([get_osfhandle(getFileHandle(stream))])
      else:
        result = terminalWidthIoctl([int(getFileHandle(stream))])
    except CatchableError:
      result = 0
  if result <= 0:
    result = CliDefaultWidth
  result = min(result, CliMaxWidth)
