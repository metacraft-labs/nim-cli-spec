## The errors a command line can produce, from one taxonomy.
##
## Every usage error a clispec parser reports is a ``CliUsageError`` whose
## ``kind`` is one ``CliErrorKind``. Each kind has exactly one wording,
## produced by ``cliErrorMessage``, and every wording names the command it is
## about (``'tool build'``), so a user can tell which command rejected the
## argument even when several share a flag. A usage error also carries the
## exit code the program should end with: the code the program declared in
## ``CliOptions.usageExitCode`` (2 unless it says otherwise, the convention of
## most Unix tools for "incorrect usage").
##
## A request for help (``--help``) is not an error; it is reported as a
## ``CliHelpRequest`` carrying the rendered help, so a program decides
## itself where to print it and how to exit. A request for the version is
## its subtype ``CliVersionRequest``. Nothing in clispec ever ends the
## process.
##
## Printing them
## =============
##
## ``cliPrintHelp(e)`` writes a help request to standard output and
## ``cliPrintError(e)`` a usage error to standard error, each deciding for
## the stream it writes to whether to style the text and (for help) how wide
## the page is (``clispec/styles``):
##
## .. code-block:: nim
##   try:
##     let conf = Tool.load()
##     ...
##   except CliHelpRequest as e:
##     cliPrintHelp(e)
##     quit 0
##   except CliUsageError as e:
##     cliPrintError(e)
##     quit e.exitCode
##
## A usage error is printed as a block (``cliErrorText``)::
##
##   error: unknown subcommand 'biuld' for 'tool'; expected one of: build, run
##
##     tip: a similar subcommand exists: 'build'
##
##   Usage: tool [options] <command>
##
##   For more information, try 'tool --help'.
##
## The first line is ``msg``, the kind's one wording. The tip is there when
## the error has ``suggestions``: for an unknown subcommand ``a similar
## subcommand exists: 'build'``, for an unknown flag ``a similar flag
## exists: '--jobs'`` and for a value outside a closed set ``a similar value
## exists: 'release'``; with several, ``some similar subcommands exist:
## 'build', 'bump'`` (``flags``, ``values``), closest first. ``Usage:`` is
## the usage line of the command the error is about (``usage``) and the
## last line names the command that prints its help (``helpCommand``); each
## is left out when the error does not carry it.
##
## Suggestions
## ===========
##
## The parser fills ``suggestions`` for an unknown subcommand (the names of
## the subcommands the command lists in its help, an alias that matches
## offering its command's name once), an unknown flag (the long spellings,
## as written, of the flags the command accepts and lists, ``--help`` and
## ``--version`` where they apply; compared without their leading dashes)
## and a value outside a closed value set (its values): the candidates
## within a Damerau–Levenshtein distance (``cliEditDistance``) of 2 and of
## less than half the typed word's length, closest first (declaration order
## among equals), at most three (``cliSuggest``). A ``hidden`` item and an
## ``internal`` parameter are never offered, an ``internal`` subcommand only
## inside the command that holds it. Nothing is accepted by prefix and
## nothing prompts.

import std/strutils

import ./styles

export styles

type
  CliErrorKind* = enum
    ## The kinds of usage error. Each has one wording (``cliErrorMessage``).
    cekUnknownFlag = "unknown flag"
      ## A word that looks like a flag is no spelling of any flag the command
      ## accepts.
    cekUnknownSubcommand = "unknown subcommand"
      ## A word where a subcommand word was expected names none.
    cekMissingSubcommand = "missing subcommand"
      ## A command that runs only through one of its subcommands (it has no
      ## ``call:``) was given none.
    cekMissingValue = "missing value"
      ## A flag that needs a value was given none.
    cekInvalidValue = "invalid value"
      ## A value does not convert to the parameter's type, is outside its
      ## closed value set, or was given to a flag that takes none.
    cekUnexpectedPositional = "unexpected positional"
      ## A bare word that no positional parameter accepts.
    cekMissingRequired = "missing required parameter"
      ## A required parameter was supplied by no source.
    cekSwitchFalseValue = "false value for a switch"
      ## A switch that refuses a false value (``refuseFalse``,
      ## ``switchesRefuseFalse``) was given one on the command line
      ## (``--split=false``); ``value`` is the value as written.
    cekConflictingSources = "conflicting sources"
      ## Two sources supplied different values to a parameter whose merge
      ## rule is ``errorOnConflict`` (``detail`` names both), or a combine
      ## proc rejected the values it was given (``detail`` is its message).

  CliUsageError* = object of CatchableError
    ## A command line that cannot be accepted. ``msg`` is
    ## ``cliErrorMessage`` of the other fields.
    kind*: CliErrorKind
    program*: string
      ## The program's name, as the error names it.
    commandPath*: seq[string]
      ## The subcommand words (canonical names) of the command the error is
      ## about; empty for the root command.
    argvIndex*: int
      ## The index in argv of the offending word, or -1 when the error is
      ## about something absent (a missing parameter or subcommand).
    spelling*: string
      ## The flag spelling or word the error is about (``--jobs``, ``-j``,
      ## ``frobnicate``), or the parameter's display name (``--output``,
      ## ``<target>``) for a missing one. Empty for the lone ``-`` or ``--``
      ## that ``parsing loneDashesAreFlags`` makes an unknown flag (a flag
      ## with an empty name; ``argvIndex`` locates the word).
    value*: string
      ## The rejected value (``cekInvalidValue``, ``cekSwitchFalseValue``).
      ## For ``cekUnknownFlag``, the value written with the flag
      ## (``--nope=v``, ``--nope:v`` under ``colonValues``, or the next word
      ## under ``equalsTakesNext``, ``--nope= v``), whose ``spelling`` is
      ## then the flag name alone (``--nope``); empty when none was
      ## written. The wording does not show it.
    expected*: string
      ## What would have been accepted: ``an integer``,
      ## ``one of: red, green``, ``no value``, or for a subcommand error the
      ## list of subcommand words. For a missing value, the flag's declared
      ## ``valueName`` (``path``), or empty when it declares none.
    detail*: string
      ## The sources in conflict (``cekConflictingSources``).
    source*: string
      ## Where a rejected value came from when it was not the command line
      ## (``environment variable TOOL_JOBS``, ``/etc/tool.toml:3 (layer
      ## 'system')``); empty for the command line, which ``argvIndex`` and
      ## ``spelling`` locate.
    exitCode*: int
      ## The code the program should exit with (``CliOptions.usageExitCode``).
    suggestions*: seq[string]
      ## What the user may have meant, closest first, at most three (see
      ## "Suggestions" above): subcommand names (``cekUnknownSubcommand``),
      ## flag spellings (``cekUnknownFlag``) or values
      ## (``cekInvalidValue``). Empty when nothing is close enough.
    usage*: string
      ## The usage line of the command the error is about
      ## (``tool build [options] <target>``), or empty when the error was
      ## made without its grammar.
    helpCommand*: string
      ## The command line that prints the help of the command the error is
      ## about (``tool build --help``), or empty when there is none (help is
      ## off, or the error was made without its grammar).
    color*: CliColorMode
      ## The program's ``CliOptions.color``, for ``cliPrintError``.

  CliHelpRender* = proc (width: int; styled: bool): string {.closure,
      gcsafe, raises: [].}
    ## Renders a help request's page again for a printer: at ``width``
    ## columns when the layout leaves the width to the printer (a standard
    ## layout whose ``width`` is 0), styled when ``styled`` (a classic
    ## layout only when the program set ``CliOptions.color`` to
    ## ``ccmAlways``).

  CliHelpRequest* = object of CatchableError
    ## ``--help`` (or ``-h``) was given. Not a failure: ``text`` holds the
    ## help of the command it was given to, rendered as asked (human text,
    ## or JSON for ``--help=json``), and the program prints it
    ## (``cliPrintHelp``).
    commandPath*: seq[string]
    json*: bool
    long*: bool
      ## The long page was asked for (``--help``, ``--help-all``, or the
      ## word ``help`` under ``parsing helpWord``) rather than the short one
      ## (``-h``).
    all*: bool
      ## The page lists the ``secondary`` subcommands too: ``--help-all``,
      ## or ``help --all`` under ``parsing helpWord``.
    text*: string
      ## The page, plain, at the layout's width (80 for the default
      ## layout, whose width is left to the printer): the same text
      ## wherever the program runs, for a program that captures it.
    render*: CliHelpRender
      ## Renders the page for the stream it is printed to (see
      ## ``CliHelpRender``); nil when ``text`` is printed as it is (JSON,
      ## the version text, a completion answer).
    color*: CliColorMode
      ## The program's ``CliOptions.color``, for ``cliPrintHelp``.

  CliVersionRequest* = object of CliHelpRequest
    ## ``--version`` (or, under ``parsing versionWord``, the word
    ## ``version`` where a subcommand word is expected) was given to a
    ## program that has a version text (``CliOptions.versionText``). Not a
    ## failure: ``text`` is that version text, exactly as the program gave
    ## it, and the program prints it and exits as it does for help. It is a
    ## ``CliHelpRequest``, so a program that handles help requests handles
    ## it too.

const DefaultUsageExitCode* = 2
  ## The exit code of a usage error unless the program declares another.

func cliCommandDisplay*(program: string; path: openArray[string]): string =
  ## How an error names a command: the program name and the subcommand
  ## words, quoted (``'tool build target'``).
  var words: seq[string] = @[]
  if program.len > 0:
    words.add(program)
  for word in path:
    words.add(word)
  if words.len == 0: "the root command"
  else: "'" & words.join(" ") & "'"

func cliErrorMessage*(kind: CliErrorKind; program: string;
                      path: openArray[string]; spelling, value, expected,
                      detail: string; source = ""): string =
  ## The one wording of each kind of usage error. Every wording names the
  ## command; an invalid value that did not come from the command line also
  ## names where it came from (`` (from <source>)``).
  let command = cliCommandDisplay(program, path)
  case kind
  of cekUnknownFlag:
    "unknown flag '" & spelling & "' for " & command
  of cekUnknownSubcommand:
    "unknown subcommand '" & spelling & "' for " & command &
      "; expected one of: " & expected
  of cekMissingSubcommand:
    command & " needs a subcommand; expected one of: " & expected
  of cekMissingValue:
    "flag '" & spelling & "' of " & command & " needs a value"
  of cekInvalidValue:
    "invalid value '" & value & "' for '" & spelling & "' of " & command &
      (if source.len > 0: " (from " & source & ")" else: "") &
      "; expected " & expected
  of cekUnexpectedPositional:
    "unexpected argument '" & spelling & "' for " & command
  of cekMissingRequired:
    "missing required parameter '" & spelling & "' of " & command
  of cekSwitchFalseValue:
    "switch '" & spelling & "' of " & command & " takes no false value " &
      "(got '" & spelling & "=" & value & "'); it is on when given and " &
      "off when omitted"
  of cekConflictingSources:
    "conflicting values for '" & spelling & "' of " & command & ": " & detail

proc newCliUsageError*(kind: CliErrorKind; program: string;
                       path: seq[string]; argvIndex: int; spelling: string;
                       value = ""; expected = ""; detail = "";
                       exitCode = DefaultUsageExitCode;
                       source = ""): ref CliUsageError =
  ## A usage error with its message filled in from the other fields.
  result = (ref CliUsageError)(kind: kind, program: program,
    commandPath: path, argvIndex: argvIndex, spelling: spelling,
    value: value, expected: expected, detail: detail, source: source,
    exitCode: exitCode)
  result.msg = cliErrorMessage(kind, program, path, spelling, value,
    expected, detail, source)

func cliEditDistance*(a, b: string): int =
  ## The Damerau–Levenshtein distance between ``a`` and ``b``: the fewest
  ## insertions, deletions, substitutions and transpositions of two
  ## adjacent characters that turn one into the other.
  let n = a.len
  let m = b.len
  if n == 0:
    return m
  if m == 0:
    return n
  let most = n + m
  var last: array[char, int]
    ## The last row where each character occurs in ``a``.
  var d = newSeq[seq[int]](n + 2)
  for i in 0 .. n + 1:
    d[i] = newSeq[int](m + 2)
  d[0][0] = most
  for i in 0 .. n:
    d[i + 1][0] = most
    d[i + 1][1] = i
  for j in 0 .. m:
    d[0][j + 1] = most
    d[1][j + 1] = j
  for i in 1 .. n:
    var lastCol = 0
    for j in 1 .. m:
      let i1 = last[b[j - 1]]
      let j1 = lastCol
      var cost = 1
      if a[i - 1] == b[j - 1]:
        cost = 0
        lastCol = j
      d[i + 1][j + 1] = min(min(d[i][j] + cost, d[i + 1][j] + 1),
        min(d[i][j + 1] + 1, d[i1][j1] + (i - i1 - 1) + 1 + (j - j1 - 1)))
    last[a[i - 1]] = i
  d[n + 1][m + 1]

func cliIsSimilar*(typed: string; distance: int): bool =
  ## Whether a candidate at ``distance`` from the word ``typed`` is offered:
  ## a distance of at most 2 and of less than half the word's length.
  distance <= 2 and 2 * distance < typed.len

type
  CliSuggestionCandidate* = tuple
    ## A candidate for ``cliSuggest``: the text the typed word is compared
    ## with, the text offered, and what it belongs to (two candidates with
    ## the same ``key``, a command's name and alias, offer one suggestion).
    compare, offer, key: string

func cliSuggest*(typed: string;
                 candidates: openArray[CliSuggestionCandidate]):
    seq[string] =
  ## The suggestions for ``typed``: the candidates ``cliIsSimilar`` accepts,
  ## one per ``key`` (its closest), closest first and in the given order
  ## among equals, at most three.
  var best: seq[tuple[distance, order: int, offer, key: string]] = @[]
  for k, c in candidates:
    let d = cliEditDistance(typed, c.compare)
    if not cliIsSimilar(typed, d):
      continue
    var seen = false
    for b in best.mitems:
      if b.key == c.key:
        seen = true
        if d < b.distance:
          b = (d, k, c.offer, c.key)
    if not seen:
      best.add((d, k, c.offer, c.key))
  # Insertion sort: stable, and the list is short.
  for i in 1 ..< best.len:
    var j = i
    while j > 0 and (best[j].distance, best[j].order) <
        (best[j - 1].distance, best[j - 1].order):
      swap(best[j], best[j - 1])
      dec j
  for b in best:
    if result.len == 3:
      break
    result.add(b.offer)

func suggestionNoun(kind: CliErrorKind): string =
  case kind
  of cekUnknownSubcommand: "subcommand"
  of cekUnknownFlag: "flag"
  else: "value"

func cliTipText*(kind: CliErrorKind; suggestions: openArray[string];
                 styled = false): string =
  ## The tip after ``tip:`` (``a similar flag exists: '--jobs'``), empty
  ## when there are no suggestions.
  if suggestions.len == 0:
    return ""
  var quoted: seq[string] = @[]
  for s in suggestions:
    quoted.add("'" & cliStyled(s, ctsLiteral, styled) & "'")
  let noun = suggestionNoun(kind)
  if suggestions.len == 1:
    "a similar " & noun & " exists: " & quoted[0]
  else:
    "some similar " & noun & "s exist: " & quoted.join(", ")

func offendingWord(e: CliUsageError): string =
  case e.kind
  of cekInvalidValue: e.value
  else: e.spelling

func cliErrorText*(e: ref CliUsageError; styled = false): string =
  ## The block ``cliPrintError`` writes (see "Printing them" above), styled
  ## when ``styled``: ``error:`` in bold bright red, the offending word in
  ## yellow, ``tip:`` in bold bright green, the usage line and the command
  ## lines as in help. Without ``styled`` it is the same text without
  ## escape sequences. No line is broken.
  var message = e.msg
  let word = offendingWord(e[])
  if styled and word.len > 0:
    let quoted = "'" & word & "'"
    let at = message.find(quoted)
    if at >= 0:
      message = message[0 .. at] & cliStyled(word, ctsOffending, true) &
        message[at + quoted.len - 1 .. ^1]
  var blocks = @[cliStyled("error:", ctsError, styled) & " " & message]
  let tip = cliTipText(e.kind, e.suggestions, styled)
  if tip.len > 0:
    blocks.add("  " & cliStyled("tip:", ctsTip, styled) & " " & tip)
  if e.usage.len > 0:
    blocks.add(cliStyled("Usage:", ctsHeading, styled) & " " &
      cliStyleUsage(e.usage, styled))
  if e.helpCommand.len > 0:
    blocks.add("For more information, try '" &
      cliStyleUsage(e.helpCommand, styled) & "'.")
  blocks.join("\n\n") & "\n"

proc cliPrintError*(e: ref CliUsageError; stream = stderr) {.
    raises: [IOError].} =
  ## Writes ``cliErrorText(e)`` to ``stream``, styled when
  ## ``cliUseColor(stream, e.color)`` says so.
  stream.write(cliErrorText(e, cliUseColor(stream, e.color)))

proc cliPrintHelp*(e: ref CliHelpRequest; stream = stdout) {.
    raises: [IOError].} =
  ## Writes the page of a help request to ``stream``: rendered again
  ## (``render``) at ``cliOutputWidth(stream)`` and styled when
  ## ``cliUseColor(stream, e.color)`` says so, or ``text`` as it is when the
  ## request carries no renderer (JSON help, a version request, a
  ## completion answer).
  if e.render.isNil:
    stream.write(e.text)
  else:
    stream.write(e.render(cliOutputWidth(stream),
      cliUseColor(stream, e.color)))
