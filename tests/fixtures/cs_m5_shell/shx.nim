## The program e2e_cs_m5_real_shell_completion completes in real shells.
##
## ``shx completion <shell>`` prints the shell's completion script, as a
## program built on clispec would offer it. Any other command line is parsed
## and its words are printed as ``ARGV:<word><word>...`` (each word in
## angle brackets, so spaces inside a word are visible), followed by
## ``OK`` or the usage error: the test reads that line to see what the
## shell completed. Completion requests (``shx __complete ...``) are
## answered through ``CliHelpRequest`` like help.

import std/os

import clispec

type
  Mode = enum
    debug, release

proc noteNames(ctx: CliCompletionContext): seq[CliCompletion] =
  ## A dynamic completer: a value a shell must quote, and a non-ASCII one.
  @[CliCompletion(value: "my file.txt", description: "A note"),
    CliCompletion(value: "\u00FCber.txt", description: "Another note")]

cliProgram(Shx, "shx"):
  help "A shell completion fixture"
  boolFlag verbose is bool, short = 'v', help = "Talk more"
  subcmd "build", help = "Build a project":
    flag jobs is int, help = "Parallel jobs"
    flag mode is Mode, help = "Build mode"
    flag note is string, complete = noteNames, help = "A note"
    pos target is string, required = false
  subcmd "remote", help = "Remotes":
    subcmd "add", help = "Add a remote":
      pos name is string

proc main(): int =
  let args = commandLineParams()
  if args.len == 2 and args[0] == "completion":
    var shell: CliShell
    if not cliParseShell(args[1], shell):
      stderr.writeLine "shx: unknown shell ", args[1]
      return 2
    stdout.write Shx.completionScript(shell)
    return 0
  try:
    discard Shx.load(args)
  except CliHelpRequest as e:
    stdout.write e.text
    return 0
  except CliUsageError as e:
    var shown = "ARGV:"
    for a in args:
      shown.add("<" & a & ">")
    echo shown, " ERROR ", e.msg
    return e.exitCode
  var shown = "ARGV:"
  for a in args:
    shown.add("<" & a & ">")
  echo shown, " OK"
  0

quit main()
