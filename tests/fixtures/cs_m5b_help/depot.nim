## The ``depot`` program: parses its arguments and prints help and usage
## errors the way the README tells a program to (``cliPrintHelp``,
## ``cliPrintError``), so a test can run it on a terminal and through a
## pipe. ``DEPOT_FIXTURE_COLOR`` (``auto``, ``always``, ``never``) sets
## ``CliOptions.color``; a command line it accepts prints ``OK``.

import std/os

import clispec

import ./depot_cli

proc main(): int =
  var options = CliOptions()
  case getEnv("DEPOT_FIXTURE_COLOR")
  of "always": options.color = ccmAlways
  of "never": options.color = ccmNever
  else: discard
  try:
    discard Depot.load(commandLineParams(), options)
    stdout.writeLine "OK"
  except CliHelpRequest as e:
    cliPrintHelp(e)
  except CliUsageError as e:
    cliPrintError(e)
    return e.exitCode

when isMainModule:
  quit main()
