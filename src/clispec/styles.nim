## Where help and errors go: whether to style them, in which colours, and
## how wide a page is.
##
## Colour
## ======
##
## Help and usage errors are styled for the stream they are written to.
## Styling never changes the text: a styled page with its escape sequences
## removed (``cliStripStyles``) is the plain page, byte for byte, so colour
## never says anything the words do not.
##
## Elements
## --------
##
## Six elements are styled (``CliTextStyle``), and nothing else:
##
## ===============  ===========================================================
## ``heading``      section headings and ``Usage:``
## ``literal``      flag spellings, command names and aliases, the program
##                  name, the words of a usage line, example command lines
##                  and suggestions
## ``placeholder``  ``<NAME>`` (with a list's ``...``) and the bracketed words
##                  of a usage line (``[options]``, ``[<packages>...]``)
## ``error``        the word ``error:``
## ``invalid``      the offending word in an error (``ctsOffending``)
## ``tip``          the word ``tip:``
## ===============  ===========================================================
##
## Descriptions, notes and prose are never styled. Only bold is used, and
## underline in the ``portable16`` palette's ``invalid``: never dim, italic,
## blink, reverse, a background colour or hyperlinks. Every span is
## ``ESC[<parameters>m``, the text, then ``ESC[0m``.
##
## On or off
## ---------
##
## The first rule that applies decides (``cliColorOn``):
##
## 1. ``CliOptions.color`` ``ccmAlways`` or ``ccmNever`` (the program's own
##    choice, for example its ``--color`` flag);
## 2. ``NO_COLOR`` set and not empty: off;
## 3. ``FORCE_COLOR`` set: ``0`` or ``false`` off, any other value (``1``,
##    ``2``, ``3``, ``true``, empty) on;
## 4. ``CLICOLOR_FORCE`` set, not empty and not ``0``: on;
## 5. ``CLICOLOR=0``: off;
## 6. otherwise on exactly when the stream is a terminal and either
##    ``TERM`` is set (not empty) and not ``dumb``, or ``CI`` is set. On
##    Windows the stream must be a console on which virtual terminal
##    processing is or can be turned on (``cliColorOn`` turns it on), and
##    an unset ``TERM`` counts as usable.
##
## Depth
## -----
##
## When styling is on, the colour depth is the first of
## (``cliColorDepthOf``):
##
## 1. ``CliOptions.colorDepth``, when the program sets it;
## 2. ``FORCE_COLOR=2`` (256 colours) or ``3`` (24-bit);
## 3. 24-bit when ``COLORTERM`` is ``truecolor`` or ``24bit``;
## 4. 256 colours when ``TERM`` ends in ``-256color`` or ``256``;
## 5. 16 colours.
##
## Whatever these say, the depth is 16 when the background is unknown.
##
## Background
## ----------
##
## The palettes for 256 colours and 24-bit are tuned for a dark or a light
## background. The first source that answers wins:
##
## 1. ``bg=dark`` or ``bg=light`` in the users' variables (below);
## 2. ``CliOptions.background``, when the program sets it (``cbUnknown``
##    fixes it unknown);
## 3. ``COLORFGBG``: its last field is the background's palette index; 0 to
##    6 and 8 are dark, 7 and 9 to 15 light;
## 4. a query of the terminal (OSC 11).
##
## If none answers, the background is unknown, and the page gets the
## ``portable16`` palette. The background is only looked for when the
## depth is 256 or 24-bit.
##
## The query is made at most once per process, only when the depth would
## be 256 or 24-bit and the styled stream is a terminal, and never when
## ``TERM`` is ``dumb`` or starts with ``screen`` or ``tmux``, when the
## process is not in the terminal's foreground process group, or on
## Windows. It opens the controlling terminal (``/dev/tty``), turns off
## its canonical mode and echo, writes ``ESC]11;?`` (the background),
## ``ESC]10;?`` (the foreground) and ``ESC[c`` (a request every terminal
## answers, so its answer marks the end), and reads until that last answer
## arrives or 100 ms have passed; then it restores the terminal's
## settings, discarding what the terminal sent and was not read. The
## background is dark when its relative luminance (WCAG) is
## below the foreground's, or below 0.5 when the terminal does not report
## its foreground. An answer that does not parse leaves the background
## unknown.
##
## Palettes
## --------
##
## SGR parameters, per element and palette (``cliPortable16``,
## ``cliDark24``, ``cliDark256``, ``cliLight24``, ``cliLight256``):
##
## ===============  ==========  ===================  ===========  ==================  ===========
## Element          portable16  dark, 24-bit         dark, 256    light, 24-bit       light, 256
## ===============  ==========  ===================  ===========  ==================  ===========
## ``heading``      1;34        1;38;2;82;198;137    1;38;5;42    1;38;2;18;129;81    1;38;5;22
## ``literal``      1           1;38;2;83;192;210    1;38;5;44    1;38;2;9;125;140    1;38;5;23
## ``placeholder``  35          38;2;150;183;189     38;5;152     38;2;87;118;124     38;5;242
## ``error``        1;31        1;38;2;255;147;139   1;38;5;217   1;38;2;214;47;53    1;38;5;160
## ``invalid``      4;35        38;2;227;168;1       38;5;178     38;2;145;107;2      38;5;94
## ``tip``          1;34        1;38;2;82;198;137    1;38;5;42    1;38;2;18;129;81    1;38;5;22
## ===============  ==========  ===================  ===========  ==================  ===========
##
## ``portable16`` (depth 16, or the background unknown) uses only 16-colour
## codes that read on dark and on light backgrounds. The tuned palettes
## keep cargo's hues (green headings, cyan literals and placeholders, red
## errors, amber offending words) at a lightness chosen for contrast: at
## least 7:1 against common dark terminal backgrounds and 4.5:1 against
## light ones.
##
## Users' overrides
## ----------------
##
## Only when the ``clispec_user_colors`` knob is on (it is off by default):
## ``CLISPEC_COLORS`` and ``<PROGRAM>_COLORS`` (the program's name
## upper-cased, every character other than a letter or a digit written
## ``_``: ``cliProgramColorsVariable``) restyle elements. Each holds
## ``name=value`` entries separated by ``:``, where ``name`` is an element
## (above) or ``bg``. An element's value is SGR parameters (digits and
## ``;``), used at every depth; an empty value leaves the element unstyled.
## ``bg`` takes ``dark`` or ``light``. The program's variable applies over
## ``CLISPEC_COLORS``, which applies over the palette. An unknown name or a
## malformed entry is ignored, entry by entry, so a page always prints. The
## overrides never turn styling on or off.
##
## Compile-time knobs
## ------------------
##
## Each policy above can be fixed, and each run-time input switched off, at
## compile time with a define (validated when the program is built; a bad
## value is an error naming the define and its allowed values). A knob that
## is off or fixed leaves no code: no read of its variables, no query, no
## palette table that can never be chosen.
##
## ============================  ===========================  ===========  ===============================================
## Define                        Values                       Default      When fixed or off
## ============================  ===========================  ===========  ===============================================
## ``clispec_colors``            ``auto always never``        ``auto``     ``never``: nothing is styled and
##                                                                         ``CliOptions.color`` is ignored; ``always``: no
##                                                                         detection (rules 2 to 6), ``CliOptions.color``
##                                                                         still applies
## ``clispec_color_env``         on/off                       on           rules 2 to 5 and ``FORCE_COLOR``'s depth are gone
## ``clispec_color_depth``       ``auto 16 256 24``           ``auto``     that depth, nothing read to detect it
## ``clispec_background``        ``auto dark light unknown``  ``auto``     that background, no source read; ``unknown``
##                                                                         keeps ``portable16`` alone
## ``clispec_colorfgbg``         on/off                       on           source 3 is gone
## ``clispec_background_query``  on/off                       on           source 4 is gone: no terminal I/O beyond the page
## ``clispec_user_colors``       on/off                       **off**      ``CLISPEC_COLORS``, ``<PROGRAM>_COLORS`` and
##                                                                         source 1 exist only when it is on
## ``clispec_palette``           entries as the users'        empty        the developer's restyling, over every palette and
##                                                                         under the users' overrides; checked at compile
##                                                                         time (``bg`` is not accepted: that is
##                                                                         ``clispec_background``)
## ============================  ===========================  ===========  ===============================================
##
## On/off values are ``on``, ``yes``, ``true``, ``1`` and ``off``, ``no``,
## ``false``, ``0``, ``none``. ``cliColorDefaults`` holds the build's
## configuration (``CliColorConfig``); every proc that decides takes it as a
## ``static`` parameter defaulting to it, so a caller can decide with
## another configuration, instantiated for it. ``CliOptions.color``,
## ``colorDepth`` and ``background`` act only where the configuration's
## policy is ``auto``.
##
## Deciding
## --------
##
## ``cliStreamStyle`` (and ``cliColorStyle(stream, options)`` in
## ``clispec/parser``) gives the ``CliStyle`` a page printed to a stream is
## rendered with: whether it is on and the SGR parameters of each element.
## ``cliDecideStyle`` is the same decision over inputs a caller provides
## (``CliColorInputs``: an environment lookup, whether the stream is a
## terminal, the terminal's answer to the query), for tests and for
## libraries that read their environment elsewhere. The procs that take
## ``styled: bool`` render with ``cliPortable16Style`` when it is true,
## without any detection.
##
## Width
## =====
##
## ``cliOutputWidth`` is the width a page printed to a stream gets: the
## environment variable ``COLUMNS`` when it is a positive integer, else the
## terminal's width when the stream is a terminal, else 80; at most 100.

import std/[macros, math, os, strutils, terminal]

when defined(windows):
  import std/winlean
elif defined(posix):
  import std/[monotimes, posix, termios, times]

type
  CliColorMode* = enum
    ## Whether help and errors are styled (``CliOptions.color``, and the
    ## ``clispec_colors`` define).
    ccmAuto = "auto"
      ## As the rules of the module documentation decide.
    ccmAlways = "always"
      ## Always, wherever the text goes.
    ccmNever = "never"
      ## Never.

  CliColorDepth* = enum
    ## The colours a terminal shows (``CliOptions.colorDepth``, and the
    ## ``clispec_color_depth`` define).
    ccdAuto = "auto"
      ## Not set: detected (see the module documentation).
    ccd16 = "16"
      ## The 16 standard colours.
    ccd256 = "256"
      ## The 256-colour palette.
    ccd24 = "24"
      ## 24-bit colour.

  CliBackground* = enum
    ## The terminal's background (``CliOptions.background``, and the
    ## ``clispec_background`` define).
    cbAuto = "auto"
      ## Not set: learned from the sources of the module documentation.
    cbDark = "dark"
    cbLight = "light"
    cbUnknown = "unknown"
      ## Unknown: the ``portable16`` palette.

  CliTextStyle* = enum
    ## The elements help and errors style (see the module documentation);
    ## each value's string is its name in the override variables.
    ctsHeading = "heading"
    ctsLiteral = "literal"
    ctsPlaceholder = "placeholder"
    ctsError = "error"
    ctsOffending = "invalid"
      ## The offending word in an error (the element ``invalid``).
    ctsTip = "tip"

  CliPalette* = array[CliTextStyle, string]
    ## The SGR parameters of each element (``1;34``); an empty one leaves
    ## the element unstyled.

  CliStyle* = object
    ## How a page is rendered: plain (``on`` false), or styled with
    ## ``sgr``. ``depth`` and ``background`` say what the decision found
    ## (``ccd16``/``cbUnknown`` for ``portable16``; ``ccdAuto``/``cbAuto``
    ## when plain or not looked for).
    on*: bool
    depth*: CliColorDepth
    background*: CliBackground
    sgr*: CliPalette

  CliColorOverrides* = object
    ## Entries of an override variable (or of ``clispec_palette``):
    ## ``background`` is ``cbAuto`` when no ``bg`` entry was given, and
    ## ``sgr`` holds the value of each element in ``elements``.
    background*: CliBackground
    elements*: set[CliTextStyle]
    sgr*: CliPalette

  CliColorConfig* = object
    ## The compile-time colour configuration (see "Compile-time knobs" in
    ## the module documentation). ``cliColorDefaults`` is the build's.
    colors*: CliColorMode
    colorEnv*: bool
    colorDepth*: CliColorDepth
    background*: CliBackground
    colorFgBg*: bool
    backgroundQuery*: bool
    userColors*: bool
    palette*: string

  CliEnvValue* = tuple[present: bool, value: string]
    ## An environment variable: whether it is set, and its value.

  CliEnvLookup* = proc (name: string): CliEnvValue {.closure, gcsafe,
    raises: [].}
    ## Reads an environment variable.

  CliColorInputs* = object
    ## What the colour decision reads besides the configuration and the
    ## program's choices (``cliDecideStyle``). ``cliStreamColorInputs``
    ## gives the real ones.
    env*: CliEnvLookup
      ## The environment.
    isTerminal*: proc (): bool {.closure, gcsafe, raises: [].}
      ## Whether the styled stream is a terminal (on Windows a console that
      ## now interprets escape sequences); called only when a rule needs
      ## it.
    queryBackground*: proc (): string {.closure, gcsafe, raises: [].}
      ## The terminal's answer to the background query, empty when none;
      ## called only when the query is to be made. Nil: no query.
    program*: string
      ## The program's name, for ``<PROGRAM>_COLORS``.

const
  CliStyleReset* = "\e[0m"
    ## Ends every styled span.
  CliDefaultWidth* = 80
    ## The page width when neither ``COLUMNS`` nor a terminal gives one.
  CliMaxWidth* = 100
    ## The widest a page is, whatever ``COLUMNS`` or the terminal says.
  CliBackgroundQueryTimeout* = 100
    ## How long, in milliseconds, the background query waits for the
    ## terminal's answer.
  CliBackgroundQuery* = "\e]11;?\e\\\e]10;?\e\\\e[c"
    ## What the background query writes to the terminal.

  cliPortable16*: CliPalette = ["1;34", "1", "35", "1;31", "4;35", "1;34"]
    ## Depth 16, or the background unknown.
  cliDark24*: CliPalette = ["1;38;2;82;198;137", "1;38;2;83;192;210",
    "38;2;150;183;189", "1;38;2;255;147;139", "38;2;227;168;1",
    "1;38;2;82;198;137"]
    ## A dark background, 24-bit.
  cliDark256*: CliPalette = ["1;38;5;42", "1;38;5;44", "38;5;152",
    "1;38;5;217", "38;5;178", "1;38;5;42"]
    ## A dark background, 256 colours.
  cliLight24*: CliPalette = ["1;38;2;18;129;81", "1;38;2;9;125;140",
    "38;2;87;118;124", "1;38;2;214;47;53", "38;2;145;107;2",
    "1;38;2;18;129;81"]
    ## A light background, 24-bit.
  cliLight256*: CliPalette = ["1;38;5;22", "1;38;5;23", "38;5;242",
    "1;38;5;160", "38;5;94", "1;38;5;22"]
    ## A light background, 256 colours.

  cliPortable16Style* = CliStyle(on: true, depth: ccd16,
    background: cbUnknown, sgr: cliPortable16)
    ## What ``styled = true`` renders with.

# ---------------------------------------------------------------------------
# The override grammar.
# ---------------------------------------------------------------------------

func cliParseColors*(text: string; into: var CliColorOverrides): seq[string] =
  ## Applies the entries of ``text`` (``name=value`` separated by ``:``, see
  ## "Users' overrides") over ``into``, and returns one problem per entry
  ## it ignored. Empty entries are skipped without a problem.
  for entry in text.split(':'):
    if entry.len == 0:
      continue
    let eq = entry.find('=')
    if eq < 0:
      result.add("'" & entry & "' is not name=value")
      continue
    let name = entry[0 ..< eq]
    let value = entry[eq + 1 .. ^1]
    if name == "bg":
      case value
      of "dark": into.background = cbDark
      of "light": into.background = cbLight
      else: result.add("'" & entry & "': bg is dark or light")
      continue
    var known = false
    for element in CliTextStyle:
      if name == $element:
        known = true
        if value.allCharsInSet({'0' .. '9', ';'}):
          into.elements.incl(element)
          into.sgr[element] = value
        else:
          result.add("'" & entry & "': the value of " & name &
            " is SGR parameters (digits and ';')")
    if not known:
      result.add("'" & entry & "': unknown name '" & name &
        "' (heading, literal, placeholder, error, invalid, tip or bg)")

func cliApply*(palette: CliPalette; overrides: CliColorOverrides): CliPalette =
  ## ``palette`` with the elements ``overrides`` sets.
  result = palette
  for element in overrides.elements:
    result[element] = overrides.sgr[element]

func cliProgramColorsVariable*(program: string): string =
  ## ``<PROGRAM>_COLORS``: ``program`` upper-cased, every character other
  ## than an ASCII letter or digit written ``_``.
  for c in program:
    result.add(if c in {'a' .. 'z'}: char(ord(c) - 32)
               elif c in {'A' .. 'Z', '0' .. '9'}: c
               else: '_')
  result.add("_COLORS")

# ---------------------------------------------------------------------------
# The compile-time configuration.
# ---------------------------------------------------------------------------

const
  clispec_colors {.strdefine.} = "auto"
  clispec_color_env {.strdefine.} = "on"
  clispec_color_depth {.strdefine.} = "auto"
  clispec_background {.strdefine.} = "auto"
  clispec_colorfgbg {.strdefine.} = "on"
  clispec_background_query {.strdefine.} = "on"
  clispec_user_colors {.strdefine.} = "off"
  clispec_palette {.strdefine.} = ""

proc cliOnOffOption*(name, value: string): bool {.compileTime.} =
  ## An on/off knob's value, as chronicles takes it; a compile-time error
  ## naming ``name`` for anything else.
  case value.toLowerAscii()
  of "on", "yes", "true", "1": true
  of "off", "no", "false", "0", "none": false
  else:
    error("clispec: '" & value & "' is not a value of '" & name &
      "'; allowed values are on, yes, true, 1 and off, no, false, 0, none")

proc cliEnumOption*[E: enum](name, value: string): E {.compileTime.} =
  ## An enum knob's value (one of ``E``'s strings); a compile-time error
  ## naming ``name`` and the allowed values for anything else.
  var allowed: seq[string] = @[]
  for v in E:
    if value.toLowerAscii() == $v:
      return v
    allowed.add($v)
  error("clispec: '" & value & "' is not a value of '" & name &
    "'; allowed values are " & allowed.join(", "))

proc cliPaletteOption*(name, value: string): string {.compileTime.} =
  ## A developer palette (``clispec_palette``): ``value`` when every entry
  ## is well formed, else a compile-time error naming ``name`` and the
  ## entry. A ``bg`` entry is refused: the background is fixed with
  ## ``clispec_background``.
  var parsed = CliColorOverrides()
  let problems = cliParseColors(value, parsed)
  if problems.len > 0:
    error("clispec: '" & name & "': " & problems[0])
  if parsed.background != cbAuto:
    error("clispec: '" & name & "': a bg entry is not accepted here; " &
      "fix the background with clispec_background")
  value

const cliColorDefaults* = CliColorConfig(
  colors: cliEnumOption[CliColorMode]("clispec_colors", clispec_colors),
  colorEnv: cliOnOffOption("clispec_color_env", clispec_color_env),
  colorDepth: cliEnumOption[CliColorDepth]("clispec_color_depth",
    clispec_color_depth),
  background: cliEnumOption[CliBackground]("clispec_background",
    clispec_background),
  colorFgBg: cliOnOffOption("clispec_colorfgbg", clispec_colorfgbg),
  backgroundQuery: cliOnOffOption("clispec_background_query",
    clispec_background_query),
  userColors: cliOnOffOption("clispec_user_colors", clispec_user_colors),
  palette: cliPaletteOption("clispec_palette", clispec_palette))
  ## The build's colour configuration, from the defines.

# ---------------------------------------------------------------------------
# Styling text.
# ---------------------------------------------------------------------------

func cliStyled*(text: string; element: CliTextStyle; style: CliStyle): string =
  ## ``text`` as ``element`` under ``style``: ``text`` itself when the
  ## style is off, ``text`` is empty or the element has no SGR parameters.
  if style.on and text.len > 0 and style.sgr[element].len > 0:
    "\e[" & style.sgr[element] & "m" & text & CliStyleReset
  else:
    text

func cliStyleOf*(styled: bool): CliStyle =
  ## ``cliPortable16Style`` when ``styled``, else plain.
  if styled: cliPortable16Style else: CliStyle()

func cliStyled*(text: string; style: CliTextStyle; on: bool): string =
  ## ``text`` in ``style`` of the ``portable16`` palette when ``on``.
  cliStyled(text, style, cliStyleOf(on))

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

func cliStyleUsage*(text: string; style: CliStyle): string =
  ## A usage line (``tool build [options] <target>``) or a command line
  ## shown in prose (``tool build --help``): each word that starts with
  ## ``<`` or ``[`` is a placeholder, every other word a literal. Spaces
  ## are kept as they are.
  if not style.on:
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
                                else: ctsLiteral), style))
    i = j

func cliStyleUsage*(text: string; on: bool): string =
  ## ``cliStyleUsage`` in the ``portable16`` palette when ``on``.
  cliStyleUsage(text, cliStyleOf(on))

func cliStyleNames*(text: string; style: CliStyle): string =
  ## A list of names separated by ``", "`` (``build, b``): each name a
  ## literal.
  if not style.on:
    return text
  var parts: seq[string] = @[]
  for name in text.split(", "):
    parts.add(cliStyled(name, ctsLiteral, style))
  parts.join(", ")

func cliStyleNames*(text: string; on: bool): string =
  ## ``cliStyleNames`` in the ``portable16`` palette when ``on``.
  cliStyleNames(text, cliStyleOf(on))

func cliStyleSpellings*(text: string; style: CliStyle): string =
  ## The left column of a flag or positional row (``-j, --jobs <N>``,
  ## ``--report[=<PATH>]``, ``--[no-]color``, ``[<packages>...]``): every
  ## spelling starting with ``-`` a literal, every ``<NAME>`` (with a
  ## following ``...``) and an optional positional (``[<NAME>...]``) a
  ## placeholder, the punctuation between them plain.
  if not style.on:
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
      result.add(cliStyled(text[i ..< j], ctsPlaceholder, style))
      i = j
    elif c == '<':
      var j = text.find('>', i)
      j = if j < 0: text.len else: j + 1
      if text.continuesWith("...", j):
        j += 3
      flush()
      result.add(cliStyled(text[i ..< j], ctsPlaceholder, style))
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
      result.add(cliStyled(text[i ..< j], ctsLiteral, style))
      i = j
    else:
      plain.add(c)
      inc i
  flush()

func cliStyleSpellings*(text: string; on: bool): string =
  ## ``cliStyleSpellings`` in the ``portable16`` palette when ``on``.
  cliStyleSpellings(text, cliStyleOf(on))

# ---------------------------------------------------------------------------
# The decision, over its inputs.
# ---------------------------------------------------------------------------

func cliForceColorOff(value: string): bool =
  value == "0" or value.toLowerAscii() == "false"

proc cliColorOn*(color: CliColorMode; inputs: CliColorInputs;
                 config: static CliColorConfig = cliColorDefaults): bool =
  ## Whether styling is on: the rules "On or off" of the module
  ## documentation, those ``config`` leaves.
  when config.colors == ccmNever:
    false
  elif config.colors == ccmAlways:
    color != ccmNever
  else:
    case color
    of ccmAlways: return true
    of ccmNever: return false
    of ccmAuto: discard
    when config.colorEnv:
      let noColor = inputs.env("NO_COLOR")
      if noColor.present and noColor.value.len > 0:
        return false
      let force = inputs.env("FORCE_COLOR")
      if force.present:
        return not cliForceColorOff(force.value)
      let clicolorForce = inputs.env("CLICOLOR_FORCE")
      if clicolorForce.present and clicolorForce.value.len > 0 and
          clicolorForce.value != "0":
        return true
      let clicolor = inputs.env("CLICOLOR")
      if clicolor.present and clicolor.value == "0":
        return false
    let term = inputs.env("TERM")
    let usable =
      when defined(windows):
        term.value != "dumb" or inputs.env("CI").present
      else:
        (term.value.len > 0 and term.value != "dumb") or
          inputs.env("CI").present
    usable and inputs.isTerminal != nil and inputs.isTerminal()

proc cliColorDepthOf*(requested: CliColorDepth; inputs: CliColorInputs;
                      config: static CliColorConfig = cliColorDefaults):
    CliColorDepth =
  ## The depth by the rules "Depth" of the module documentation (before
  ## an unknown background makes it 16): ``config.colorDepth`` when fixed,
  ## else ``requested`` when set, else what the environment says.
  when config.colorDepth != ccdAuto:
    config.colorDepth
  else:
    if requested != ccdAuto:
      return requested
    when config.colorEnv:
      let force = inputs.env("FORCE_COLOR")
      if force.present:
        case force.value
        of "2": return ccd256
        of "3": return ccd24
        else: discard
    let colorterm = inputs.env("COLORTERM").value
    if colorterm == "truecolor" or colorterm == "24bit":
      return ccd24
    let term = inputs.env("TERM").value
    if term.endsWith("-256color") or term.endsWith("256"):
      return ccd256
    ccd16

func cliColorFgBgBackground*(value: string): CliBackground =
  ## The background ``COLORFGBG`` names (``15;0``: dark): its last field,
  ## a palette index, 0 to 6 and 8 dark, 7 and 9 to 15 light;
  ## ``cbUnknown`` for anything else.
  let fields = value.split(';')
  let last = fields[^1]
  if last.len == 0 or last.len > 2 or not last.allCharsInSet({'0' .. '9'}):
    return cbUnknown
  var index = 0
  for c in last:
    index = index * 10 + ord(c) - ord('0')
  if index in 0 .. 6 or index == 8: cbDark
  elif index == 7 or index in 9 .. 15: cbLight
  else: cbUnknown

func cliQueryAllowed*(term: string): bool =
  ## Whether the background query may be made under ``TERM``: not for
  ## ``dumb`` or a ``screen*`` or ``tmux*`` terminal.
  not (term == "dumb" or term.startsWith("screen") or
    term.startsWith("tmux"))

func oscColor(answer, code: string): tuple[ok: bool, luminance: float] =
  ## The relative luminance (WCAG 2) of the colour in the answer to
  ## ``ESC]<code>;?``: ``ESC]<code>;rgb:R/G/B`` with 1 to 4 hex digits per
  ## channel, ended by BEL or ST.
  let head = "\e]" & code & ";rgb:"
  let at = answer.find(head)
  if at < 0:
    return
  var i = at + head.len
  var channels: array[3, float]
  for k in 0 .. 2:
    var digits = 0
    var v = 0
    while i < answer.len and answer[i] in HexDigits and digits < 5:
      let h = answer[i]
      v = v * 16 + (if h in {'0' .. '9'}: ord(h) - ord('0')
                    elif h in {'a' .. 'f'}: ord(h) - ord('a') + 10
                    else: ord(h) - ord('A') + 10)
      inc digits
      inc i
    if digits < 1 or digits > 4:
      return
    let c = v.float / (16.0 ^ digits - 1.0)
    channels[k] = if c <= 0.04045: c / 12.92
                  else: pow((c + 0.055) / 1.055, 2.4)
    if k < 2:
      if i >= answer.len or answer[i] != '/':
        return
      inc i
  if not (answer.continuesWith("\a", i) or answer.continuesWith("\e\\", i)):
    return
  (true, 0.2126 * channels[0] + 0.7152 * channels[1] +
    0.0722 * channels[2])

func cliParseBackgroundAnswer*(answer: string): CliBackground =
  ## The background a terminal's answer to ``CliBackgroundQuery`` gives:
  ## dark when the background's luminance is below the foreground's (below
  ## 0.5 when there is no foreground), else light; ``cbUnknown`` when the
  ## background's colour does not parse.
  let bg = oscColor(answer, "11")
  if not bg.ok:
    return cbUnknown
  let fg = oscColor(answer, "10")
  let limit = if fg.ok: fg.luminance else: 0.5
  if bg.luminance < limit: cbDark else: cbLight

proc cliUserColors*(inputs: CliColorInputs): CliColorOverrides =
  ## The users' overrides: ``CLISPEC_COLORS``, then
  ## ``<PROGRAM>_COLORS`` over it (when ``inputs.program`` is set).
  ## Malformed entries are ignored.
  discard cliParseColors(inputs.env("CLISPEC_COLORS").value, result)
  if inputs.program.len > 0:
    discard cliParseColors(
      inputs.env(cliProgramColorsVariable(inputs.program)).value, result)

proc cliDecideStyle*(color: CliColorMode; colorDepth: CliColorDepth;
                     background: CliBackground; inputs: CliColorInputs;
                     config: static CliColorConfig = cliColorDefaults):
    CliStyle =
  ## The style of a page: ``color``, ``colorDepth`` and ``background`` are
  ## the program's choices (``CliOptions``), ``inputs`` what is read from
  ## the process, and ``config`` the compile-time configuration; see the
  ## module documentation for the rules.
  when config.colors == ccmNever:
    return CliStyle()
  else:
    if not cliColorOn(color, inputs, config):
      return CliStyle()
    result.on = true
    when config.userColors:
      let user = cliUserColors(inputs)
    var depth = cliColorDepthOf(colorDepth, inputs, config)
    var bg = cbUnknown
    when config.background == cbAuto:
      if depth != ccd16:
        bg = cbAuto
        when config.userColors:
          bg = user.background
        if bg == cbAuto:
          bg = background
        when config.colorFgBg:
          if bg == cbAuto:
            let fgbg = inputs.env("COLORFGBG")
            if fgbg.present:
              let named = cliColorFgBgBackground(fgbg.value)
              if named != cbUnknown:
                bg = named
        when config.backgroundQuery and defined(posix):
          if bg == cbAuto and inputs.queryBackground != nil and
              cliQueryAllowed(inputs.env("TERM").value) and
              inputs.isTerminal != nil and inputs.isTerminal():
            bg = cliParseBackgroundAnswer(inputs.queryBackground())
        if bg == cbAuto:
          bg = cbUnknown
    elif config.background != cbUnknown:
      bg = config.background
    if bg == cbUnknown:
      depth = ccd16
    result.depth = depth
    result.background = bg
    const
      developer = block:
        var o = CliColorOverrides()
        discard cliParseColors(config.palette, o)
        o
      tuned = config.background != cbUnknown and config.colorDepth != ccd16
      canDark = config.background in {cbAuto, cbDark}
      canLight = config.background in {cbAuto, cbLight}
      can24 = config.colorDepth in {ccdAuto, ccd24}
      can256 = config.colorDepth in {ccdAuto, ccd256}
    result.sgr = cliApply(cliPortable16, developer)
    when tuned:
      when canDark and can24:
        if bg == cbDark and depth == ccd24:
          result.sgr = cliApply(cliDark24, developer)
      when canDark and can256:
        if bg == cbDark and depth == ccd256:
          result.sgr = cliApply(cliDark256, developer)
      when canLight and can24:
        if bg == cbLight and depth == ccd24:
          result.sgr = cliApply(cliLight24, developer)
      when canLight and can256:
        if bg == cbLight and depth == ccd256:
          result.sgr = cliApply(cliLight256, developer)
    when config.userColors:
      result.sgr = cliApply(result.sgr, user)

# ---------------------------------------------------------------------------
# The real inputs: the process's environment, the stream, the terminal.
# ---------------------------------------------------------------------------

when defined(windows):
  # Win32 console API, documented at
  # https://learn.microsoft.com/en-us/windows/console/getconsolemode and
  # https://learn.microsoft.com/en-us/windows/console/setconsolemode.
  proc getConsoleMode(console: Handle; mode: ptr DWORD): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "GetConsoleMode".}
  proc setConsoleMode(console: Handle; mode: DWORD): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "SetConsoleMode".}

  proc consoleHandle(stream: File): Handle =
    ## The Win32 handle behind ``stream``, for the console API: the C
    ## runtime's descriptor (``_fileno``) translated by ``_get_osfhandle``
    ## (https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/get-osfhandle),
    ## which answers ``INVALID_HANDLE_VALUE`` for a descriptor that is not
    ## open and -2 for a standard stream with no console or file behind it
    ## (a GUI program); the console API refuses both.
    ##
    ## The descriptor is converted to ``cint`` explicitly because the
    ## standard library's types differ between Nim versions: Nim 2.2 has
    ## ``FileHandle = cint`` and ``get_osfhandle(fd: FileHandle)``, later
    ## versions ``FileHandle = int`` on Windows and
    ## ``get_osfhandle(fd: cint)``. A C runtime descriptor is a C ``int``,
    ## so the conversion loses nothing, and the full-width ``Handle`` comes
    ## back without the narrowing ``getOsFileHandle`` does under Nim 2.2.
    get_osfhandle(cint(getFileHandle(stream)))

  proc enableEscapeSequences(stream: File): bool =
    ## Whether ``stream`` is a console that now interprets escape sequences:
    ## turns on its virtual terminal processing
    ## (``ENABLE_VIRTUAL_TERMINAL_PROCESSING``), false when it is not a
    ## console or the console refuses.
    ##
    ## ``GetConsoleMode`` fails on anything but a console handle (a pipe, a
    ## file, the ``NUL`` device, which ``_isatty`` counts as a terminal), so
    ## those get plain text. ``SetConsoleMode`` fails with
    ## ``ERROR_INVALID_PARAMETER`` for the flag on consoles older than
    ## Windows 10, which do not interpret escape sequences
    ## (https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences).
    const enableVirtualTerminalProcessing = DWORD(0x0004)
    let console = consoleHandle(stream)
    if console == INVALID_HANDLE_VALUE:
      return false
    var mode: DWORD = 0
    if getConsoleMode(console, addr mode) == 0:
      return false
    if (mode and enableVirtualTerminalProcessing) != 0:
      return true
    setConsoleMode(console, mode or enableVirtualTerminalProcessing) != 0

when defined(posix):
  proc daAnswered(answer: string): bool =
    ## Whether ``answer`` holds the answer to ``ESC[c``:
    ## ``ESC[?`` digits and ``;`` then ``c``.
    var at = answer.find("\e[?")
    while at >= 0:
      var i = at + 3
      while i < answer.len and answer[i] in {'0' .. '9', ';'}:
        inc i
      if i < answer.len and answer[i] == 'c':
        return true
      at = answer.find("\e[?", at + 1)
    false

  proc cliQueryTerminal*(timeoutMs = CliBackgroundQueryTimeout): string {.
      gcsafe, raises: [].} =
    ## Asks the controlling terminal for its colours: writes
    ## ``CliBackgroundQuery`` to ``/dev/tty`` with canonical mode and echo
    ## off, and returns what it reads until the answer to ``ESC[c`` arrives
    ## or ``timeoutMs`` milliseconds have passed; the terminal's settings
    ## are restored, and what the terminal sent unread is discarded
    ## (``TCSAFLUSH``). Empty when there is no controlling terminal or the
    ## process is not in its foreground process group. Not cached: see
    ## ``cliTerminalColorsAnswer``.
    let fd = posix.open("/dev/tty", O_RDWR or O_NOCTTY or O_CLOEXEC)
    if fd < 0:
      return ""
    defer: discard posix.close(fd)
    if tcgetpgrp(fd) != getpgrp():
      return ""
    var saved: Termios
    if tcGetAttr(fd, addr saved) != 0:
      return ""
    var raw = saved
    raw.c_lflag = raw.c_lflag and not (ICANON or ECHO)
    raw.c_cc[VMIN] = typeof(raw.c_cc[0])(0)
    raw.c_cc[VTIME] = typeof(raw.c_cc[0])(0)
    if tcSetAttr(fd, TCSANOW, addr raw) != 0:
      return ""
    try:
      let query = CliBackgroundQuery
      if posix.write(fd, unsafeAddr query[0], query.len) != query.len:
        return ""
      let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
      var buf: array[256, char]
      while not daAnswered(result):
        let left = (deadline - getMonoTime()).inMilliseconds
        if left <= 0:
          break
        var fds = [TPollfd(fd: fd, events: POLLIN)]
        let ready = poll(addr fds[0], 1, cint(left))
        if ready < 0:
          if errno == EINTR:
            continue
          break
        if ready == 0:
          break
        let n = posix.read(fd, addr buf[0], buf.len)
        if n <= 0:
          break
        for k in 0 ..< n:
          result.add(buf[k])
    finally:
      # TCSAFLUSH discards what the terminal sent and was not read (an
      # answer that came after the deadline, or after the sentinel's), so
      # it does not reach the shell or the program as typed input.
      discard tcSetAttr(fd, TCSAFLUSH, addr saved)

  var queried = false
  var queryAnswer = ""

  proc cliTerminalColorsAnswer*(): string {.gcsafe, raises: [].} =
    ## ``cliQueryTerminal()``, asked at most once per process: later calls
    ## return the first answer.
    {.cast(gcsafe).}:
      if not queried:
        queried = true
        queryAnswer = cliQueryTerminal()
      result = queryAnswer

proc cliProcessEnv*(name: string): CliEnvValue {.gcsafe, raises: [].} =
  ## The process's environment variable ``name``.
  (existsEnv(name), getEnv(name))

proc cliStreamColorInputs*(stream: File; program = "";
                           config: static CliColorConfig = cliColorDefaults):
    CliColorInputs =
  ## The real inputs of the decision for a page written to ``stream``: the
  ## process's environment, whether ``stream`` is a terminal (on Windows,
  ## a console on which virtual terminal processing is or can be turned on,
  ## which this turns on when asked) and, on POSIX when ``config`` allows
  ## the query, the terminal's answer to it.
  result.env = cliProcessEnv
  result.program = program
  result.isTerminal = proc (): bool {.closure, gcsafe, raises: [].} =
    when defined(windows):
      isatty(stream) and enableEscapeSequences(stream)
    else:
      isatty(stream)
  when config.backgroundQuery and config.background == cbAuto and
      config.colorDepth != ccd16 and config.colors != ccmNever and
      defined(posix):
    result.queryBackground = cliTerminalColorsAnswer

proc cliStreamStyle*(stream: File; color = ccmAuto; colorDepth = ccdAuto;
                     background = cbAuto; program = "";
                     config: static CliColorConfig = cliColorDefaults):
    CliStyle =
  ## The style of a page written to ``stream``, for the program's choices
  ## (``CliOptions.color``, ``colorDepth``, ``background``) and its name
  ## (for ``<PROGRAM>_COLORS``), under ``config``.
  when config.colors == ccmNever:
    CliStyle()
  else:
    cliDecideStyle(color, colorDepth, background,
      cliStreamColorInputs(stream, program, config), config)

proc cliUseColor*(stream: File; mode = ccmAuto;
                  config: static CliColorConfig = cliColorDefaults): bool =
  ## Whether text written to ``stream`` is styled under ``mode`` (the
  ## rules "On or off"). On Windows the terminal must be a console that
  ## accepts virtual terminal processing, which this turns on.
  when config.colors == ccmNever:
    false
  else:
    cliColorOn(mode, cliStreamColorInputs(stream, "", config), config)

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
        # The visible window's width, from the console screen buffer
        # (``srWindow``, https://learn.microsoft.com/en-us/windows/console/console-screen-buffer-info-str);
        # 0 when the handle is not a console screen buffer (``NUL``).
        result = terminalWidthIoctl([consoleHandle(stream)])
      else:
        result = terminalWidthIoctl([int(getFileHandle(stream))])
    except CatchableError:
      result = 0
  if result <= 0:
    result = CliDefaultWidth
  result = min(result, CliMaxWidth)
