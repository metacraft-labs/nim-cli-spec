## test_cs_m3_parser_error_taxonomy: every kind of usage error has one
## wording, names the command it is about and carries the program's exit
## code.
##
## The golden table is an ``array[CliErrorKind, ...]``, so a kind added to
## the taxonomy without a case here is a compile error, and the loop over the
## enum runs every case. Each case drives the generated parser of a real
## description with a real argv, except ``cekConflictingSources``: only the
## command line is a source so far, so nothing can produce a conflict yet,
## and its wording is checked through the constructor every other kind goes
## through. The wordings are compared in full, so exchanging two kinds'
## messages fails, and a separate check requires the wordings to be pairwise
## distinct for the same inputs.

import std/[options, strutils, unittest]

import clispec

type
  Shade = enum
    light, dark

cliProgram(Tx, "tx"):
  boolFlag verbose is bool, short = 'v'
  subcmd "build":
    flag jobs is int, short = 'j'
    flag mode is string, values = ["debug", "release"]
    flag config is string, format = equals
    boolFlag dry is bool, negatable = true
    flag shade is Shade
    flag retries is range[0 .. 9]
    flag slots is Option[int], values = [1, 2]
    pos target is string
  subcmd "remote":
    flag url is string, required = true
    subcmd "add":
      pos name is string
  subcmd "secret", visibility = hidden:
    pos x is string

type
  Case = object
    argv: seq[string]
    message: string
    path: seq[string]
    argvIndex: int

const cases: array[CliErrorKind, Case] = [
  cekUnknownFlag: Case(argv: @["build", "--nope", "app"],
    message: "unknown flag '--nope' for 'tx build'",
    path: @["build"], argvIndex: 1),
  cekUnknownSubcommand: Case(argv: @["frob"],
    message: "unknown subcommand 'frob' for 'tx'; expected one of: " &
      "build, remote",
    path: @[], argvIndex: 0),
  cekMissingSubcommand: Case(argv: @["remote", "--url", "u"],
    message: "'tx remote' needs a subcommand; expected one of: add",
    path: @["remote"], argvIndex: -1),
  cekMissingValue: Case(argv: @["build", "app", "--jobs"],
    message: "flag '--jobs' of 'tx build' needs a value",
    path: @["build"], argvIndex: 2),
  cekInvalidValue: Case(argv: @["build", "-j", "many", "app"],
    message: "invalid value 'many' for '-j' of 'tx build'; expected an " &
      "integer",
    path: @["build"], argvIndex: 2),
  cekUnexpectedPositional: Case(argv: @["build", "app", "extra"],
    message: "unexpected argument 'extra' for 'tx build'",
    path: @["build"], argvIndex: 2),
  cekMissingRequired: Case(argv: @["remote", "add", "origin"],
    message: "missing required parameter '--url' of 'tx remote'",
    path: @["remote"], argvIndex: -1),
  cekConflictingSources: Case(argv: @[],
    message: "conflicting values for '--jobs' of 'tx build': " &
      "file a.toml:3 says 2, the command line says 4",
    path: @["build"], argvIndex: -1),
]

proc produce(kind: CliErrorKind; options = CliOptions()): ref CliUsageError =
  ## The error a case's argv produces (or, for the kind no source can
  ## produce yet, the error built as the parser builds every error).
  if kind == cekConflictingSources:
    let exitCode = if options.usageExitCode == 0: DefaultUsageExitCode
                   else: options.usageExitCode
    return newCliUsageError(cekConflictingSources, "tx", @["build"], -1,
      "--jobs", detail = "file a.toml:3 says 2, the command line says 4",
      exitCode = exitCode)
  try:
    discard Tx.load(cases[kind].argv, options)
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard
  nil

proc usageError(argv: seq[string]): ref CliUsageError =
  ## The usage error ``argv`` produces, or nil.
  try:
    discard Tx.load(argv)
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard
  nil

suite "test_cs_m3_parser_error_taxonomy":

  test "each kind produces its one wording, naming the command":
    for kind in CliErrorKind:
      let e = produce(kind)
      checkpoint($kind)
      check not e.isNil
      if e.isNil:
        continue
      check e.kind == kind
      check e.msg == cases[kind].message
      check e.commandPath == cases[kind].path
      check e.argvIndex == cases[kind].argvIndex
      # The default is 2 (spelt out, so changing the constant fails here).
      check e.exitCode == 2
      check cliCommandDisplay("tx", cases[kind].path) in e.msg

  test "usage errors carry the exit code the program declares":
    for kind in CliErrorKind:
      let e = produce(kind, CliOptions(usageExitCode: 64))
      checkpoint($kind)
      check not e.isNil
      if not e.isNil:
        check e.exitCode == 64

  test "the wordings are pairwise distinct":
    var seen: seq[string] = @[]
    for kind in CliErrorKind:
      let text = cliErrorMessage(kind, "tx", ["build"], "x", "v", "e", "d")
      checkpoint($kind & ": " & text)
      check text notin seen
      check "'tx build'" in text
      seen.add(text)

  test "invalid values name the allowed set":
    let e = usageError(@["build", "--mode=fast", "app"])
    check e.kind == cekInvalidValue
    check e.msg == "invalid value 'fast' for '--mode' of 'tx build'; " &
      "expected one of: debug, release"
    check e.argvIndex == 1
    let s = usageError(@["build", "--shade", "grey", "app"])
    check s.kind == cekInvalidValue
    check s.msg == "invalid value 'grey' for '--shade' of 'tx build'; " &
      "expected one of: light, dark"
    check s.argvIndex == 2
    let r = usageError(@["build", "--retries=10", "app"])
    check r.kind == cekInvalidValue
    check r.msg == "invalid value '10' for '--retries' of 'tx build'; " &
      "expected an integer from 0 to 9"
    let o = usageError(@["build", "--slots=3", "app"])
    check o.kind == cekInvalidValue
    check o.msg == "invalid value '3' for '--slots' of 'tx build'; " &
      "expected one of: 1, 2"
    check Tx.load(@["build", "--slots=2", "app"]).build.slots == some(2)
    let n = usageError(@["build", "--no-dry=1", "app"])
    check n.kind == cekInvalidValue
    check n.msg == "invalid value '1' for '--no-dry' of 'tx build'; " &
      "expected no value"

  test "an equals-only flag does not take the next word":
    let e = usageError(@["build", "--config", "a", "app"])
    check e.kind == cekMissingValue
    check e.msg == "flag '--config' of 'tx build' needs a value"

  test "hidden subcommands are accepted but not advertised":
    check Tx.load(@["secret", "s"]).secret.x == "s"
    let e = usageError(@[])
    check e.kind == cekMissingSubcommand
    check "secret" notin e.msg
    check e.msg == "'tx' needs a subcommand; expected one of: build, remote"

  test "the parser never ends the process: help is an exception too":
    var h: ref CliHelpRequest = nil
    try:
      discard Tx.load(@["build", "--help"])
    except CliHelpRequest as e:
      h = e
    check not h.isNil
    check h.commandPath == @["build"]
    check h.text.startsWith("Usage: tx build ")
