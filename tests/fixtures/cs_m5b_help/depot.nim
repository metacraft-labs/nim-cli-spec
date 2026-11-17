## The ``depot`` program: parses its arguments and prints help and usage
## errors the way the README tells a program to (``cliPrintHelp``,
## ``cliPrintError``), so a test can run it on a terminal and through a
## pipe. ``DEPOT_FIXTURE_COLOR`` (``auto``, ``always``, ``never``) sets
## ``CliOptions.color``, ``DEPOT_FIXTURE_DEPTH`` (``16``, ``256``, ``24``)
## ``CliOptions.colorDepth`` and ``DEPOT_FIXTURE_BACKGROUND`` (``dark``,
## ``light``, ``unknown``) ``CliOptions.background``; a command line it
## accepts prints ``OK``. The colour tests also build it with ``-d:``
## defines (``clispec/styles``).

import std/os

import clispec

import ./depot_cli

proc main(): int =
  var options = CliOptions()
  case getEnv("DEPOT_FIXTURE_COLOR")
  of "always": options.color = ccmAlways
  of "never": options.color = ccmNever
  else: discard
  case getEnv("DEPOT_FIXTURE_DEPTH")
  of "16": options.colorDepth = ccd16
  of "256": options.colorDepth = ccd256
  of "24": options.colorDepth = ccd24
  else: discard
  case getEnv("DEPOT_FIXTURE_BACKGROUND")
  of "dark": options.background = cbDark
  of "light": options.background = cbLight
  of "unknown": options.background = cbUnknown
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
