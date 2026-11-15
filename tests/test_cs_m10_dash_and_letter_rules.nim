## test_cs_m10_dash_and_letter_rules: two opt-in parsing rules for command
## lines that come from a getopt-style parser which reads every word
## starting with ``-`` as an option and compares one-letter option names
## exactly:
##
## * ``parsing loneDashesAreFlags``: a lone ``-`` or ``--`` where a flag may
##   stand is an unknown flag whose spelling is empty (so ``--`` ends
##   nothing and ``-`` is never a positional), while a flag's value and the
##   words a ``rest`` positional takes stay verbatim;
## * ``parsing exactOneLetterFlags``: under ``flagMatching ignoreCase`` or
##   ``ignoreStyle``, a spelling whose name is one character (``-T``,
##   ``--T``) is compared exactly; longer names are still compared in the
##   mode.
##
## ``Fork`` is a command line described for the getopt-based parser of the
## nim-confutils fork at commit 5395af1 (its ``confutils.nim`` and
## ``confutils/cli_parser.nim``). ``expectedParses`` is what that parser
## gave for the equivalent confutils type, loaded from a real process's
## arguments with ``load(quitOnFailure = false, envVarsPrefix = "",
## negatableSwitches = false)`` and printed in one normalised line,
## captured once and checked in; this test prints clispec's result the same
## way. (``-T=x`` and ``-vT``, which that parser reported as the unknown
## option ``T``, are checked on their own below: clispec reports an
## unknown letter in a cluster as the whole word.) The type was:
##
## .. code-block:: nim
##   type
##     Cmd = enum noCommand, run, remote, build
##     Conf = object
##       verbose {.abbr: "v", name: "verbose".}: bool
##       output {.abbr: "o", name: "output".}: Option[string]
##       traceFolder {.abbr: "t", name: "trace-folder".}: Option[string]
##       level {.abbr: "L", name: "level".}: Option[string]
##       x {.name: "x".}: Option[string]
##       mode {.implicitValue: "fast", name: "mode".}: Option[string]
##       case cmd {.command, defaultValue: noCommand.}: Cmd
##       of noCommand:
##         noCmdArgs {.ignore.}: string
##       of run:
##         program {.argument.}: string
##         args {.restOfArgs, defaultValue: @[].}: seq[string]
##       of remote:
##         remoteArgs {.restOfArgs, defaultValue: @[].}: seq[string]
##       of build:
##         jobs {.abbr: "j", name: "jobs".}: Option[int]
##         target {.argument, defaultValue: "".}: string
##
## That parser also matches a one-letter abbreviation written as a long
## option (``--t``); the description declares those spellings as aliases.
## ``Before`` is the same description without the two rules and pins
## today's answers to exactly the command lines the rules change.

import std/[json, options, strutils, unittest]

import clispec

cliProgram(Fork, "fork"):
  convention cli = kebabCase
  flagMatching ignoreStyle
  commandMatching ignoreStyle
  parsing equalsTakesNext, helpWord, loneDashesAreFlags, exactOneLetterFlags
  boolFlag verbose is bool, short = 'v'
  flag output is Option[string], short = 'o', alias = "--o"
  flag traceFolder is Option[string], short = 't', alias = "--t"
  flag level is Option[string], short = 'L', alias = "--L"
  flag x is Option[string], short = 'x'
  flag mode is Option[string], optionalValue = some("fast"),
    acceptsNextWord = true
  call:
    discard
  subcmd "run":
    pos program is string
    pos args is seq[string], rest = true, required = false
  subcmd "remote":
    pos remoteArgs is seq[string], rest = true, required = false
  subcmd "build":
    flag jobs is Option[int], short = 'j', alias = "--j"
    pos target is string, default = ""

cliProgram(Before, "before"):
  convention cli = kebabCase
  flagMatching ignoreStyle
  commandMatching ignoreStyle
  parsing equalsTakesNext, helpWord
  boolFlag verbose is bool, short = 'v'
  flag output is Option[string], short = 'o', alias = "--o"
  flag traceFolder is Option[string], short = 't', alias = "--t"
  flag level is Option[string], short = 'L', alias = "--L"
  flag x is Option[string], short = 'x'
  flag mode is Option[string], optionalValue = some("fast"),
    acceptsNextWord = true
  call:
    discard
  subcmd "run":
    pos program is string
    pos args is seq[string], rest = true, required = false
  subcmd "remote":
    pos remoteArgs is seq[string], rest = true, required = false
  subcmd "build":
    flag jobs is Option[int], short = 'j', alias = "--j"
    pos target is string, default = ""

cliProgram(DashesOnly, "dashes"):
  # The dash rule alone, under exact flag matching and with ``--`` the
  # only way a word starting with ``-`` could have reached a positional.
  parsing loneDashesAreFlags
  boolFlag verbose is bool, short = 'v'
  flag output is Option[string], short = 'o'
  pos files is seq[string], required = false

cliProgram(Letters, "letters"):
  # The letter rule alone, under ignoreCase.
  flagMatching ignoreCase
  parsing exactOneLetterFlags
  boolFlag verbose is bool, short = 'v'
  boolFlag q is bool, negatable = true
  flag output is Option[string], short = 'o'
  flag outputDir is Option[string], perSource = [cli = "output-dir"],
    short = 'O'

cliProgram(Comp, "comp"):
  flagMatching ignoreStyle
  parsing loneDashesAreFlags, exactOneLetterFlags
  flag trace is Option[string], short = 't', values = ["fast", "full"]
  flag level is Option[string], short = 'L', values = ["low", "high"]
  call:
    pos files is seq[string], required = false, values = ["a.txt", "b.txt"]
  subcmd "build":
    pos target is string, required = false, values = ["lib", "app"]
  subcmd "run":
    pos program is string, values = ["prog"]
    pos args is seq[string], rest = true, required = false,
      values = ["-", "--", "arg"]

cliProgram(CompPlain, "compplain"):
  flagMatching ignoreStyle
  flag trace is Option[string], short = 't', values = ["fast", "full"]
  flag level is Option[string], short = 'L', values = ["low", "high"]
  call:
    pos files is seq[string], required = false, values = ["a.txt", "b.txt"]
  subcmd "build":
    pos target is string, required = false, values = ["lib", "app"]
  subcmd "run":
    pos program is string, values = ["prog"]
    pos args is seq[string], rest = true, required = false,
      values = ["-", "--", "arg"]

const expectedParses: seq[tuple[argv: seq[string], line: string]] = @[
  (newSeq[string](), "cmd=noCommand verbose=false output=none trace=none level=none x=none mode=none"),
  (@["-"], "unknown ''"),
  (@["--"], "unknown ''"),
  (@["--=v"], "unknown ''"),
  (@["--="], "unknown ''"),
  (@["build", "-"], "unknown ''"),
  (@["build", "--"], "unknown ''"),
  (@["build", "-", "t"], "unknown ''"),
  (@["build", "t", "-"], "unknown ''"),
  (@["build", "--", "t"], "unknown ''"),
  (@["build", "-o", "-", "t"], "cmd=build verbose=false output=- trace=none level=none x=none mode=none jobs=none target=t"),
  (@["build", "--output", "--", "t"], "cmd=build verbose=false output=-- trace=none level=none x=none mode=none jobs=none target=t"),
  (@["run", "-", "prog"], "unknown ''"),
  (@["run", "--", "prog"], "unknown ''"),
  (@["run", "prog", "-", "a", "--"], "cmd=run verbose=false output=none trace=none level=none x=none mode=none program=prog args=-,a,--"),
  (@["run", "prog", "--", "-"], "cmd=run verbose=false output=none trace=none level=none x=none mode=none program=prog args=--,-"),
  (@["remote", "-", "a"], "cmd=remote verbose=false output=none trace=none level=none x=none mode=none remote=-,a"),
  (@["remote", "--", "a"], "cmd=remote verbose=false output=none trace=none level=none x=none mode=none remote=--,a"),
  (@["remote"], "cmd=remote verbose=false output=none trace=none level=none x=none mode=none remote="),
  (@["-o", "-", "build"], "cmd=build verbose=false output=- trace=none level=none x=none mode=none jobs=none target="),
  (@["-o", "--", "build"], "cmd=build verbose=false output=-- trace=none level=none x=none mode=none jobs=none target="),
  (@["--output", "-", "build"], "cmd=build verbose=false output=- trace=none level=none x=none mode=none jobs=none target="),
  (@["--output", "--", "build"], "cmd=build verbose=false output=-- trace=none level=none x=none mode=none jobs=none target="),
  (@["-vo", "-", "build"], "cmd=build verbose=true output=- trace=none level=none x=none mode=none jobs=none target="),
  (@["-vo", "--"], "cmd=noCommand verbose=true output=-- trace=none level=none x=none mode=none"),
  (@["--output=", "-", "build"], "unknown ''"),
  (@["--output=", "--"], "unknown ''"),
  (@["--output=", "x", "build"], "cmd=build verbose=false output=x trace=none level=none x=none mode=none jobs=none target="),
  (@["--mode", "-"], "unknown ''"),
  (@["--mode", "--"], "unknown ''"),
  (@["--mode", "x"], "cmd=noCommand verbose=false output=none trace=none level=none x=none mode=x"),
  (@["--mode", "build"], "cmd=noCommand verbose=false output=none trace=none level=none x=none mode=build"),
  (@["-v", "-"], "unknown ''"),
  (@["-v", "--", "build"], "unknown ''"),
  (@["-h", "-"], "help"),
  (@["-", "-h"], "unknown ''"),
  (@["--", "--help"], "unknown ''"),
  (@["--help", "--"], "help"),
  (@["help", "-"], "help"),
  (@["build", "-", "--help"], "unknown ''"),
  (@["build", "--help", "-"], "help"),
  (@["-", "--bogus"], "unknown ''"),
  (@["--bogus", "-"], "unknown 'bogus'"),
  (@["--=v", "-"], "unknown ''"),
  (@["-T", "x"], "unknown 'T'"),
  (@["-t", "x"], "cmd=noCommand verbose=false output=none trace=x level=none x=none mode=none"),
  (@["--T", "x"], "unknown 'T'"),
  (@["--t", "x"], "cmd=noCommand verbose=false output=none trace=x level=none x=none mode=none"),
  (@["--t_", "x"], "unknown 't_'"),
  (@["-L", "x"], "cmd=noCommand verbose=false output=none trace=none level=x x=none mode=none"),
  (@["-l", "x"], "unknown 'l'"),
  (@["--L", "x"], "cmd=noCommand verbose=false output=none trace=none level=x x=none mode=none"),
  (@["--l", "x"], "unknown 'l'"),
  (@["--x", "1"], "cmd=noCommand verbose=false output=none trace=none level=none x=1 mode=none"),
  (@["--X", "1"], "unknown 'X'"),
  (@["-x", "1"], "cmd=noCommand verbose=false output=none trace=none level=none x=1 mode=none"),
  (@["-X", "1"], "unknown 'X'"),
  (@["--X_", "1"], "unknown 'X_'"),
  (@["--x_", "1"], "unknown 'x_'"),
  (@["--Trace-Folder", "y"], "cmd=noCommand verbose=false output=none trace=y level=none x=none mode=none"),
  (@["--TRACE-FOLDER", "y"], "cmd=noCommand verbose=false output=none trace=y level=none x=none mode=none"),
  (@["--trace_folder", "y"], "unknown 'trace_folder'"),
  (@["--Trace_Folder", "y"], "unknown 'Trace_Folder'"),
  (@["--OUTPUT", "o"], "cmd=noCommand verbose=false output=o trace=none level=none x=none mode=none"),
  (@["--O", "o"], "unknown 'O'"),
  (@["--o", "o"], "cmd=noCommand verbose=false output=o trace=none level=none x=none mode=none"),
  (@["-O", "o"], "unknown 'O'"),
  (@["-o", "o"], "cmd=noCommand verbose=false output=o trace=none level=none x=none mode=none"),
  (@["build", "-J", "2"], "unknown 'J'"),
  (@["build", "--J", "2"], "unknown 'J'"),
  (@["build", "--j", "2"], "cmd=build verbose=false output=none trace=none level=none x=none mode=none jobs=2 target="),
  (@["build", "-j", "2"], "cmd=build verbose=false output=none trace=none level=none x=none mode=none jobs=2 target="),
  (@["build", "--JOBS", "2"], "cmd=build verbose=false output=none trace=none level=none x=none mode=none jobs=2 target="),
  (@["--Mode"], "cmd=noCommand verbose=false output=none trace=none level=none x=none mode=fast"),
  (@["--VERBOSE"], "cmd=noCommand verbose=true output=none trace=none level=none x=none mode=none"),
  (@["-V"], "unknown 'V'"),
  (@["-v"], "cmd=noCommand verbose=true output=none trace=none level=none x=none mode=none"),
  (@["--HELP"], "help"),
  (@["-H"], "unknown 'H'"),
  (@["--T=x"], "unknown 'T'"),
  (@["--t=x"], "cmd=noCommand verbose=false output=none trace=x level=none x=none mode=none"),
  (@["-vt", "x"], "cmd=noCommand verbose=true output=none trace=x level=none x=none mode=none"),
  (@["-vL", "x"], "cmd=noCommand verbose=true output=none trace=none level=x x=none mode=none"),
  ]
    ## What nim-confutils 5395af1's parser gives for each argv.

func show(o: Option[string]): string =
  if o.isNone: "none" else: o.get

func dashless(spelling: string): string =
  ## The option's name as that parser reports it: the spelling without its
  ## ``--`` or ``-``.
  if spelling.startsWith("--"): spelling[2 .. ^1]
  elif spelling.startsWith("-"): spelling[1 .. ^1]
  else: spelling

template lineOf(P: untyped; argv: seq[string]): string =
  ## One argv's result in the normalised form of the expected lines.
  block:
    var s: string
    try:
      let c = P.load(argv)
      let cmd = $c.command
      s = "cmd=" & (if cmd == "call": "noCommand" else: cmd) &
        " verbose=" & $c.verbose & " output=" & show(c.output) &
        " trace=" & show(c.traceFolder) & " level=" & show(c.level) &
        " x=" & show(c.x) & " mode=" & show(c.mode)
      if cmd == "run":
        s.add " program=" & c.run.program & " args=" & c.run.args.join(",")
      elif cmd == "remote":
        s.add " remote=" & c.remote.remoteArgs.join(",")
      elif cmd == "build":
        s.add " jobs=" & (if c.build.jobs.isNone: "none"
                          else: $c.build.jobs.get) &
          " target=" & c.build.target
    except CliUsageError as e:
      s = case e.kind
          of cekUnknownFlag: "unknown '" & dashless(e.spelling) & "'"
          else: "other " & $e.kind & " " & e.msg
    except CliHelpRequest:
      s = "help"
    s

proc usageErrorOf(body: proc ()): ref CliUsageError =
  try:
    body()
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard
  nil

template usageError(body: proc ()): ref CliUsageError =
  block:
    var e = usageErrorOf(body)
    if e.isNil:
      checkpoint("expected a usage error")
      fail()
      e = (ref CliUsageError)(argvIndex: -99, spelling: "<no error>")
    e

proc values(cs: seq[CliCompletion]): seq[string] =
  for c in cs:
    result.add(c.value)

suite "test_cs_m10_dash_and_letter_rules":

  test "every argv parses as nim-confutils 5395af1's parser parses it":
    check expectedParses.len >= 80
    for (argv, expected) in expectedParses:
      checkpoint(argv.join(" "))
      check lineOf(Fork, argv) == expected

  test "without the rules, today's answers stand":
    # The same argv, read as clispec reads them by default: ``--`` ends the
    # flags, ``-`` is a word, and a one-letter spelling matches in the mode.
    check lineOf(Before, @["run", "--", "prog"]) ==
      "cmd=run verbose=false output=none trace=none level=none x=none " &
      "mode=none program=prog args="
    check lineOf(Before, @["build", "-"]) ==
      "cmd=build verbose=false output=none trace=none level=none x=none " &
      "mode=none jobs=none target=-"
    check lineOf(Before, @["build", "--", "-t"]) ==
      "cmd=build verbose=false output=none trace=none level=none x=none " &
      "mode=none jobs=none target=-t"
    check lineOf(Before, @["--"]) ==
      "cmd=noCommand verbose=false output=none trace=none level=none " &
      "x=none mode=none"
    let dash = usageError(proc () = discard Before.load(@["-"]))
    check dash.kind == cekUnknownSubcommand
    check dash.spelling == "-"
    check lineOf(Before, @["-v", "--", "build"]) ==
      "other unexpected positional " &
      "unexpected argument 'build' for 'before'"
    for (argv, field) in [(@["-T", "x"], "trace=x"), (@["--T", "x"], "trace=x"),
                          (@["--t_", "x"], "trace=x"),
                          (@["-l", "x"], "level=x"), (@["--l", "x"], "level=x"),
                          (@["--X", "1"], "x=1"), (@["-X", "1"], "x=1"),
                          (@["--x_", "1"], "x=1"), (@["-O", "o"], "output=o"),
                          (@["--O", "o"], "output=o"), (@["-V"], "verbose=true"),
                          (@["-vT", "x"], "trace=x")]:
      checkpoint(argv.join(" "))
      check field in lineOf(Before, argv)
    # What the rules leave alone is the same with and without them.
    check lineOf(Before, @["--=v"]) == "unknown ''"
    check lineOf(Before, @["run", "prog", "-", "--"]) ==
      lineOf(Fork, @["run", "prog", "-", "--"])
    check lineOf(Before, @["-o", "-", "build"]) ==
      lineOf(Fork, @["-o", "-", "build"])
    check lineOf(Before, @["--TRACE-FOLDER", "y"]) ==
      lineOf(Fork, @["--TRACE-FOLDER", "y"])
    let gp = parseJson(Before.helpJson())["parsing"]
    check gp == %*{"flagMatching": "ignoreStyle",
      "rules": ["equalsTakesNext", "helpWord"],
      "commandMatching": "ignoreStyle"}
    check cprLoneDashesAreFlags notin Before.cliModel.parseRules
    check cprExactOneLetterFlags notin Before.cliGrammar.parseRules

  test "the rules change neither help nor the JSON beyond their names":
    check Fork.helpText().replace("fork", "before") == Before.helpText()
    check Fork.helpText(["build"]).replace("fork", "before") ==
      Before.helpText(["build"])
    let fj = parseJson(Fork.helpJson())
    let bj = parseJson(Before.helpJson())
    check fj["parsing"]["rules"] == %*["equalsTakesNext", "helpWord",
      "loneDashesAreFlags", "exactOneLetterFlags"]
    check fj["command"] == parseJson(($bj["command"]).replace("before",
      "fork"))
    check cprLoneDashesAreFlags in Fork.cliModel.parseRules
    check cprExactOneLetterFlags in Fork.cliGrammar.parseRules

  test "loneDashesAreFlags: an unknown flag with an empty spelling":
    for (argv, at, path) in [(@["-"], 0, newSeq[string]()),
                             (@["--"], 0, newSeq[string]()),
                             (@["build", "-"], 1, @["build"]),
                             (@["build", "t", "--"], 2, @["build"]),
                             (@["-v", "--", "build"], 1, newSeq[string]()),
                             (@["run", "--", "prog"], 1, @["run"]),
                             (@["--output=", "-"], 1, newSeq[string]())]:
      checkpoint(argv.join(" "))
      let e = usageError(proc () = discard Fork.load(argv))
      check e.kind == cekUnknownFlag
      check e.spelling == ""
      check e.value == ""
      check e.argvIndex == at
      check e.commandPath == path
    let msg = usageError(proc () = discard Fork.load(@["build", "-"])).msg
    check msg == "unknown flag '' for 'fork build'"
    # ``--=v`` was already an unknown flag named by ``--`` (the flag name
    # is empty), carrying its value; the rule does not change it.
    let eq = usageError(proc () = discard Fork.load(@["--=v"]))
    check eq.kind == cekUnknownFlag
    check eq.spelling == "--"
    check eq.value == "v"
    # The first problem in argv order is the one reported.
    check usageError(proc () =
      discard Fork.load(@["--bogus", "-"])).spelling == "--bogus"
    check usageError(proc () =
      discard Fork.load(@["-", "--bogus"])).spelling == ""

  test "loneDashesAreFlags: values, rest, clusters and help":
    # A flag's value is the next word verbatim, whatever it looks like.
    check Fork.load(@["-o", "-"]).output == some("-")
    check Fork.load(@["--output", "--"]).output == some("--")
    check Fork.load(@["-vo", "-"]).output == some("-")
    check Fork.load(@["build", "-j", "2", "-o", "--"]).output == some("--")
    # A value written in the word, or the rest of a cluster, is not a lone
    # dash either.
    check Fork.load(@["--output=-"]).output == some("-")
    check Fork.load(@["--output=--"]).output == some("--")
    check Fork.load(@["-o-"]).output == some("-")
    check Fork.load(@["-o--"]).output == some("--")
    # ``equalsTakesNext`` and ``acceptsNextWord`` never take a word starting
    # with ``-``, so the dash is read on its own and refused.
    check usageError(proc () =
      discard Fork.load(@["--output=", "--"])).argvIndex == 1
    check usageError(proc () =
      discard Fork.load(@["--mode", "-"])).argvIndex == 1
    check Fork.load(@["--mode"]).mode == some("fast")
    # A rest positional takes them, once it has started.
    let r = Fork.load(@["run", "prog", "-", "--", "--help"])
    check r.run.program == "prog"
    check r.run.args == @["-", "--", "--help"]
    check Fork.load(@["remote", "--", "-"]).remote.remoteArgs == @["--", "-"]
    let gr = Fork.cliGrammar
    let t = cliTokenize(gr, @["remote", "-"])
    var restId = -1
    for id, p in gr.params:
      if p.name == "remoteArgs":
        restId = id
    check t.candidates[restId].len == 1
    check t.candidates[restId][0].verbatim
    # Help: whichever comes first wins.
    for argv in [@["-h", "-"], @["--help", "--"], @["help", "-"],
                 @["build", "--help", "-"]]:
      checkpoint(argv.join(" "))
      expect CliHelpRequest:
        discard Fork.load(argv)
    for argv in [@["-", "-h"], @["--", "--help"], @["build", "-", "--help"],
                 @["--", "help"]]:
      checkpoint(argv.join(" "))
      check usageError(proc () = discard Fork.load(argv)).spelling == ""
    # Under exact matching and with a list positional: ``--`` does not
    # let a word starting with ``-`` through any more.
    check DashesOnly.load(@["a", "-o", "-", "b"]).files == @["a", "b"]
    check DashesOnly.load(@["a", "-o", "-", "b"]).output == some("-")
    for argv in [@["-"], @["a", "-"], @["--", "-v"], @["a", "--", "b"]]:
      checkpoint(argv.join(" "))
      let e = usageError(proc () = discard DashesOnly.load(argv))
      check e.kind == cekUnknownFlag
      check e.spelling == ""
    # Other words starting with ``-`` are read as before.
    check usageError(proc () =
      discard DashesOnly.load(@["-x"])).spelling == "-x"
    check DashesOnly.load(@["-vo", "a", "b"]).verbose

  test "exactOneLetterFlags: one-letter names compared exactly":
    for (argv, spelling, at) in [(@["-T", "x"], "-T", 0),
        (@["--T", "x"], "--T", 0), (@["--t_", "x"], "--t_", 0),
        (@["-l", "x"], "-l", 0), (@["--l", "x"], "--l", 0),
        (@["-X", "1"], "-X", 0), (@["--X", "1"], "--X", 0),
        (@["--x_", "1"], "--x_", 0), (@["--X_", "1"], "--X_", 0),
        (@["-O", "o"], "-O", 0), (@["--O", "o"], "--O", 0),
        (@["-V"], "-V", 0), (@["-H"], "-H", 0), (@["--T=x"], "--T", 0),
        (@["build", "-J", "2"], "-J", 1), (@["build", "--J", "2"], "--J", 1)]:
      checkpoint(argv.join(" "))
      let e = usageError(proc () = discard Fork.load(argv))
      check e.kind == cekUnknownFlag
      check e.spelling == spelling
      check e.argvIndex == at
    # In a cluster the whole word is reported, as for any unknown letter.
    for word in ["-vT", "-Tv"]:
      checkpoint(word)
      let e = usageError(proc () = discard Fork.load(@[word, "x"]))
      check e.kind == cekUnknownFlag
      check e.spelling == word
    check Fork.load(@["-vt", "x"]).traceFolder == some("x")
    # The same holds for ``-T=x``, which that parser reported as the
    # unknown option ``T`` (so ``expectedParses`` leaves it out): clispec
    # reads the word as a cluster and reports the whole of it.
    let te = usageError(proc () = discard Fork.load(@["-T=x"]))
    check te.kind == cekUnknownFlag
    check te.spelling == "-T=x"
    check te.argvIndex == 0
    # Longer names are still compared in the mode, help included.
    check Fork.load(@["--TRACE-FOLDER", "y"]).traceFolder == some("y")
    check Fork.load(@["--O_utput", "y"]).output == some("y")
    check Fork.load(@["build", "--JOBS", "3"]).build.jobs == some(3)
    expect CliHelpRequest:
      discard Fork.load(@["--HELP"])
    # Under ignoreCase.
    check Letters.load(@["--OUTPUT", "a"]).output == some("a")
    check Letters.load(@["--Output-Dir", "a"]).outputDir == some("a")
    check Letters.load(@["-o", "a"]).output == some("a")
    check Letters.load(@["-O", "a"]).outputDir == some("a")
    for argv in [@["-V"], @["--Q"], @["--no-Q"]]:
      checkpoint(argv.join(" "))
      check usageError(proc () = discard Letters.load(argv)).kind ==
        cekUnknownFlag
    check Letters.load(@["--q"]).q
    check not Letters.load(@["--q", "--no-q"]).q
    check Letters.load(@["--VERBOSE", "-v"]).verbose

  test "completion follows both rules":
    # A ``--`` before the cursor ends nothing; a lone ``-`` fills no
    # positional.
    check values(CompPlain.complete(@["--", "-"])).len == 0
    check values(Comp.complete(@["--", "-"])) == @["--trace", "-t", "--level",
      "-L", "--help", "-h"]
    check values(CompPlain.complete(@["build", "-", ""])).len == 0
    check values(Comp.complete(@["build", "-", ""])) == @["lib", "app"]
    check values(CompPlain.complete(@["-", ""])) == @["a.txt", "b.txt"]
    check values(Comp.complete(@["-", ""])) == @["build", "run", "a.txt",
      "b.txt"]
    # A flag's value and the rest are as before.
    check values(Comp.complete(@["-t", "-"])).len == 0
    check values(Comp.complete(@["-t", "f"])) == @["fast", "full"]
    check values(Comp.complete(@["run", "prog", "-", ""])) == @["-", "--",
      "arg"]
    check values(Comp.complete(@["run", "prog", "-"])) == @["-", "--"]
    check values(CompPlain.complete(@["run", "prog", "-"])) == @["-", "--"]
    # One-letter spellings: what the parser matches, completion walks.
    check values(CompPlain.complete(@["-T", ""])) == @["fast", "full"]
    check values(Comp.complete(@["-T", ""])) == @["build", "run", "a.txt",
      "b.txt"]
    check values(Comp.complete(@["-t", ""])) == @["fast", "full"]
    check values(Comp.complete(@["-L", "h"])) == @["high"]
    check values(CompPlain.complete(@["-l", "h"])) == @["high"]
    check values(Comp.complete(@["-l", "h"])).len == 0
    check values(CompPlain.complete(@["--Trace=f"])) == @["--Trace=fast",
      "--Trace=full"]
    check values(Comp.complete(@["--Trace=f"])) == @["--Trace=fast",
      "--Trace=full"]
    check values(Comp.complete(@["-"])) == values(CompPlain.complete(@["-"]))
