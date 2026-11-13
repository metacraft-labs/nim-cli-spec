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
## itself where to print it and how to exit. Nothing in clispec ever ends the
## process.

import std/strutils

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
      ## ``<target>``) for a missing one.
    value*: string
      ## The rejected value (``cekInvalidValue``).
    expected*: string
      ## What would have been accepted: ``an integer``,
      ## ``one of: red, green``, ``no value``, or for a subcommand error the
      ## list of subcommand words.
    detail*: string
      ## The sources in conflict (``cekConflictingSources``).
    source*: string
      ## Where a rejected value came from when it was not the command line
      ## (``environment variable TOOL_JOBS``, ``/etc/tool.toml:3 (layer
      ## 'system')``); empty for the command line, which ``argvIndex`` and
      ## ``spelling`` locate.
    exitCode*: int
      ## The code the program should exit with (``CliOptions.usageExitCode``).

  CliHelpRequest* = object of CatchableError
    ## ``--help`` (or ``-h``) was given. Not a failure: ``text`` holds the
    ## help of the command it was given to, rendered as asked (human text,
    ## or JSON for ``--help=json``), and the program prints it.
    commandPath*: seq[string]
    json*: bool
    text*: string

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

type
  CliConfigErrorKind* = enum
    ## The kinds of configuration-file error. Each has one wording
    ## (``cliConfigErrorMessage``), and every wording names the file, and
    ## the line and key when there is one.
    cfeUnreadable = "unreadable file"
      ## A layer the program requires is missing, or a file cannot be read.
    cfeSyntax = "syntax error"
      ## The format adapter rejected the file (``detail`` is its message).
    cfeMissingSchema = "missing schema"
      ## The file has no top-level ``schema`` string.
    cfeWrongSchema = "wrong schema"
      ## The file's ``schema`` is not the identifier the program declares.
    cfeUnknownKey = "unknown key"
      ## A key that names no parameter (and is not under ``extensions``).
    cfeWrongType = "wrong type"
      ## A value of the wrong type for its key (``expected`` says which).
    cfeNoSchemaDeclared = "no schema declared"
      ## The program loads a configuration file but its description
      ## declares no ``configSchema``, so no file can be valid.
    cfeNoFormat = "no format"
      ## The program declares layers but no format to read them with.

  CliConfigError* = object of CatchableError
    ## A configuration file that cannot be accepted. ``msg`` is
    ## ``cliConfigErrorMessage`` of the other fields.
    kind*: CliConfigErrorKind
    path*: string
      ## The file.
    line*: int
      ## The line the error is about; 0 when it is about the whole file.
    key*: string
      ## The key the error is about, as written in the file, or empty.
    layer*: string
      ## The name of the layer the file was loaded as.
    expected*: string
      ## What would have been accepted (``cfeWrongType``,
      ## ``cfeWrongSchema``).
    detail*: string
      ## The format's own message (``cfeSyntax``, ``cfeUnreadable``), or
      ## the value found (``cfeWrongSchema``, ``cfeWrongType``).

func cliConfigErrorMessage*(kind: CliConfigErrorKind; path: string;
                            line: int; key, layer, expected,
                            detail: string): string =
  ## The one wording of each kind of configuration-file error:
  ## ``<file>[:<line>]: <what> (layer '<name>')``.
  let at = (if path.len > 0: path else: "<no file>") &
    (if line > 0: ":" & $line else: "")
  let what = case kind
    of cfeUnreadable: "cannot be read: " & detail
    of cfeSyntax: "is not valid: " & detail
    of cfeMissingSchema:
      "has no top-level `schema` string; expected schema = \"" &
        expected & "\""
    of cfeWrongSchema:
      "declares schema \"" & detail & "\"; expected \"" & expected & "\""
    of cfeUnknownKey: "unknown key '" & key & "'"
    of cfeWrongType:
      "key '" & key & "' has " & detail & "; expected " & expected
    of cfeNoSchemaDeclared:
      "cannot be loaded: the program declares no configSchema"
    of cfeNoFormat:
      "cannot be loaded: no configuration format was given"
  at & ": " & what & (if layer.len > 0: " (layer '" & layer & "')" else: "")

proc newCliConfigError*(kind: CliConfigErrorKind; path: string; line = 0;
                        key = ""; layer = ""; expected = "";
                        detail = ""): ref CliConfigError =
  ## A configuration-file error with its message filled in.
  result = (ref CliConfigError)(kind: kind, path: path, line: line, key: key,
    layer: layer, expected: expected, detail: detail)
  result.msg = cliConfigErrorMessage(kind, path, line, key, layer, expected,
    detail)
