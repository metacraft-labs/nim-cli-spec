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
      ## rule is ``errorOnConflict``. Only the command line is a source so
      ## far, so nothing raises this kind yet; configuration files and the
      ## environment will.

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
                      detail: string): string =
  ## The one wording of each kind of usage error. Every wording names the
  ## command.
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
                       exitCode = DefaultUsageExitCode): ref CliUsageError =
  ## A usage error with its message filled in from the other fields.
  result = (ref CliUsageError)(kind: kind, program: program,
    commandPath: path, argvIndex: argvIndex, spelling: spelling,
    value: value, expected: expected, detail: detail, exitCode: exitCode)
  result.msg = cliErrorMessage(kind, program, path, spelling, value,
    expected, detail)
