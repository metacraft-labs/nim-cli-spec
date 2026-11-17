## The ``knobs`` program of ``test_cs_m5c_compile_time_knobs_shrink``: the
## ``depot`` description (``../cs_m5b_help/depot_cli.nim``, read at compile
## time) under the type ``Knobs`` and the program name ``knobs``, with the
## colour parameters of its ``cliProgram`` call taken from the define
## ``knobs_params`` (``colors=never,userColors=on``: entries separated by
## ``,``, each ``name=value``; a value of digits is a number, one of letters
## a word, anything else a string). It prints help and usage errors only
## through the generated ``Knobs.printHelp`` and ``Knobs.printError``, so the
## binary holds the code of its own configuration and nothing else.
## ``KNOBS_FIXTURE_MODE`` (``always``, ``never``) sets ``CliOptions.color``;
## a command line it accepts prints ``OK``.

import std/[macros, os, strutils]

import clispec

const knobs_params {.strdefine.} = ""

type
  # The value types of the depot description.
  When = enum auto, always, never
  Profile = enum debug, release
  Format = enum table, json

macro knobsProgram(): untyped =
  ## ``cliProgram(Knobs, "knobs", <knobs_params>): <depot's description>``.
  const path = currentSourcePath().parentDir() / ".." / "cs_m5b_help" /
    "depot_cli.nim"
  let source = staticRead(path)
  let at = source.find("cliProgram(Depot")
  doAssert at >= 0, "depot_cli.nim has no cliProgram(Depot"
  # Parsed with the file's name, so the description's line information
  # (which clispec's diagnostics use) names a real file.
  let call = parseStmt(source[at .. ^1], path)[0]
  doAssert call.kind == nnkCall and call[^1].kind == nnkStmtList
  var program = newCall(ident("cliProgram"), ident("Knobs"), newLit("knobs"))
  for entry in knobs_params.split(','):
    if entry.len == 0:
      continue
    let eq = entry.find('=')
    doAssert eq > 0, "knobs_params: '" & entry & "' is not name=value"
    let value = entry[eq + 1 .. ^1]
    let node =
      if value.len > 0 and value.allCharsInSet(Digits): newLit(parseInt(value))
      elif value.len > 0 and value.allCharsInSet(Letters): ident(value)
      else: newLit(value)
    program.add(nnkExprEqExpr.newTree(ident(entry[0 ..< eq]), node))
  program.add(call[^1])
  result = program

knobsProgram()

proc main(): int =
  var options = CliOptions()
  case getEnv("KNOBS_FIXTURE_MODE")
  of "always": options.color = ccmAlways
  of "never": options.color = ccmNever
  else: discard
  try:
    discard Knobs.load(commandLineParams(), options)
    stdout.writeLine "OK"
  except CliHelpRequest as e:
    Knobs.printHelp(e)
  except CliUsageError as e:
    Knobs.printError(e)
    return e.exitCode

when isMainModule:
  quit main()
