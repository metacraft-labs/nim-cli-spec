## test_retired_spellings: a spelling a program no longer accepts, declared
## with what replaced it (``retired "<spelling>", replacement = "<text>"``).
##
## What it pins:
##
## * a retired spelling is still unknown: the error has the kind any
##   unknown flag or subcommand word has (``cekUnknownFlag``,
##   ``cekUnknownSubcommand``), the program's usage exit code, and nothing
##   of it is accepted;
## * the error names the replacement, in its message and as structured
##   fields (``retired``, ``replacement``), and offers no suggestions;
## * the forms: a long flag, one value of a flag (``--report=none``,
##   preferred to the flag retired alone), a one-letter flag (alone and
##   with something attached), a subcommand word at the root and in a
##   nested command;
## * where they apply: a retired flag at its command and at every command
##   nested in it (``call:`` included), wherever in the body it is written,
##   and a ``call:``'s retired flag at its holder too; not at an enclosing
##   command or a sibling. A retired word only at its command;
## * matching follows ``flagMatching`` and ``commandMatching``;
## * a retired spelling is never offered: not by help (``-h``, ``--help``,
##   the classic layout), not among the machine-readable help's
##   parameters or commands (it has a ``retired`` list of its own), not by
##   completion, and never as a suggestion for a mistyped word;
## * the help path (``helpText(path)``) names the replacement of a retired
##   word too.
##
## The declaration errors (a collision with a live flag, alias, short,
## negation or subcommand word, duplicates, an empty replacement, ...) are
## compile-time fixtures in ``tests/fixtures/cs_m2_invalid/retired_*.nim``,
## run by ``test_cs_m2_invalid_declarations_fail_to_compile``.
##
## Every program is a real ``cliProgram`` driven through the generated
## ``load``, ``helpText``, ``helpJson`` and ``complete``; nothing is mocked.

import std/[json, strutils, unittest]

import clispec

cliProgram(Tool, "tool"):
  convention cli = kebabCase
  help "A tool"
  boolFlag verbose is bool, short = 'v'
  flag jobs is int, default = 1, short = 'j', help = "Parallel jobs"
  retired "--threads", replacement = "--jobs"
  retired "-t", replacement = "-j"
  retired "checkout", replacement = "tool switch <branch>"
  retired "co", replacement = "tool switch <branch>"
  boolFlag color is bool, help = "Colour the output"
  retired "--colour", replacement = "--color"
  subcmd "branch", help = "Fork a workspace":
    flag fromRole is string, default = "", perSource = [cli = "from"],
      help = "The role to fork from"
    flag writeReport is string, default = "", perSource = [cli = "write-report"]
    retired "--from-mainlines",
      replacement = "`--from=mainline`, or its shorthand `--mainline`"
    retired "--report=none", replacement = "--measure=none --no-write-report"
    retired "--report", replacement = "--write-report"
    pos path is string, help = "Where the workspace goes"
  subcmd "switch", help = "Switch the workspace":
    pos name is string
  subcmd "workspace", help = "Workspace commands":
    retired "start", replacement = "tool switch -b <name>"
    subcmd "status":
      boolFlag short is bool
    subcmd "projects":
      retired "remove", replacement = "tool workspace disable"
      subcmd "add":
        pos names is seq[string]
        retired "--default", replacement = "tool workspace enable --default"
      subcmd "list":
        discard
  subcmd "run", help = "Run something":
    subcmd "list":
      discard
    call:
      retired "--dry", replacement = "--dry-run"
      boolFlag dryRun is bool

cliProgram(Loose, "loose"):
  flagMatching ignoreCase
  commandMatching ignoreCase
  flag jobs is int, default = 1
  retired "--threads", replacement = "--jobs"
  retired "checkout", replacement = "loose switch"
  subcmd "switch":
    pos name is string

cliProgram(Late, "late"):
  # The retired flag is written after the subcommands it applies to.
  flag jobs is int, default = 1
  subcmd "build":
    subcmd "all":
      discard
  retired "--threads", replacement = "--jobs"

cliProgram(Plain, "plain"):
  flag jobs is int, default = 1
  subcmd "switch":
    pos name is string

proc usageErrorOf(argv: seq[string]): ref CliUsageError =
  try:
    discard Tool.load(argv)
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard

proc looseErrorOf(argv: seq[string]): ref CliUsageError =
  try:
    discard Loose.load(argv)
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard

proc values(cs: seq[CliCompletion]): seq[string] =
  for c in cs:
    result.add(c.value)

const retiredSpellings = ["--threads", "-t", "checkout", "co", "--colour",
  "--from-mainlines", "--report", "start", "remove", "--default", "--dry"]

suite "test_retired_spellings":

  test "a retired flag is an unknown flag that names its replacement":
    let e = usageErrorOf(@["branch", "--from-mainlines", "../x"])
    check not e.isNil
    check e.kind == cekUnknownFlag
    check e.exitCode == 2
    check e.argvIndex == 1
    check e.commandPath == @["branch"]
    check e.spelling == "--from-mainlines"
    check e.retired == "--from-mainlines"
    check e.replacement ==
      "`--from=mainline`, or its shorthand `--mainline`"
    check e.msg == "unknown flag '--from-mainlines' for 'tool branch' " &
      "(a retired spelling; use `--from=mainline`, or its shorthand " &
      "`--mainline`)"
    check e.suggestions.len == 0
    # The printed block carries it too, styled or not.
    check "(a retired spelling; use `--from=mainline`" in cliErrorText(e)
    check "a retired spelling" in cliErrorText(e, styled = true)

  test "an unknown flag that is not retired is worded as before":
    let e = usageErrorOf(@["branch", "--frobnicate", "../x"])
    check e.kind == cekUnknownFlag
    check e.retired == ""
    check e.replacement == ""
    check e.msg == "unknown flag '--frobnicate' for 'tool branch'"

  test "the live flags still work beside retired ones":
    let conf = Tool.load(@["branch", "--from=mainline", "--write-report=r",
      "../x"])
    check conf.branch.fromRole == "mainline"
    check conf.branch.writeReport == "r"
    check conf.branch.path == "../x"

  test "one value of a flag is preferred to the flag retired alone":
    let none = usageErrorOf(@["branch", "--report=none", "../x"])
    check none.kind == cekUnknownFlag
    check none.spelling == "--report"
    check none.value == "none"
    check none.retired == "--report=none"
    check none.replacement == "--measure=none --no-write-report"
    check none.msg == "unknown flag '--report' for 'tool branch' " &
      "('--report=none' is a retired spelling; use --measure=none " &
      "--no-write-report)"
    for argv in [@["branch", "--report=full", "../x"],
                 @["branch", "--report", "../x"]]:
      let e = usageErrorOf(argv)
      check e.kind == cekUnknownFlag
      check e.retired == "--report"
      check e.replacement == "--write-report"
      check e.msg == "unknown flag '--report' for 'tool branch' " &
        "(a retired spelling; use --write-report)"

  test "a one-letter flag, alone and with something attached":
    let alone = usageErrorOf(@["-t", "4", "switch", "x"])
    check alone.kind == cekUnknownFlag
    check alone.spelling == "-t"
    check alone.retired == "-t"
    check alone.msg == "unknown flag '-t' for 'tool' (a retired " &
      "spelling; use -j)"
    let attached = usageErrorOf(@["-t4", "switch", "x"])
    check attached.kind == cekUnknownFlag
    check attached.spelling == "-t4"
    check attached.retired == "-t"
    check attached.msg == "unknown flag '-t4' for 'tool' ('-t' is a " &
      "retired spelling; use -j)"
    # A cluster refused at a live letter's neighbour is not the retired one.
    let other = usageErrorOf(@["-vx", "switch", "x"])
    check other.retired == ""

  test "a retired subcommand word is an unknown subcommand":
    let e = usageErrorOf(@["checkout", "main"])
    check e.kind == cekUnknownSubcommand
    check e.exitCode == 2
    check e.argvIndex == 0
    check e.retired == "checkout"
    check e.replacement == "tool switch <branch>"
    check e.msg == "unknown subcommand 'checkout' for 'tool' (a retired " &
      "spelling; use tool switch <branch>); expected one of: branch, " &
      "switch, workspace, run"
    check e.suggestions.len == 0
    check usageErrorOf(@["co", "main"]).retired == "co"

  test "retired words of nested commands":
    let start = usageErrorOf(@["workspace", "start", "b"])
    check start.kind == cekUnknownSubcommand
    check start.commandPath == @["workspace"]
    check start.replacement == "tool switch -b <name>"
    let remove = usageErrorOf(@["workspace", "projects", "remove", "p"])
    check remove.kind == cekUnknownSubcommand
    check remove.commandPath == @["workspace", "projects"]
    check remove.replacement == "tool workspace disable"
    # A word is retired only where its command expects a subcommand word.
    let elsewhere = usageErrorOf(@["workspace", "projects", "start"])
    check elsewhere.kind == cekUnknownSubcommand
    check elsewhere.retired == ""
    let atRoot = usageErrorOf(@["start"])
    check atRoot.retired == ""

  test "a retired flag applies to its command and every command in it":
    # Declared at the root: refused there and in every nested command.
    for argv in [@["--threads", "2", "switch", "x"],
                 @["switch", "--threads", "x"],
                 @["workspace", "status", "--threads"],
                 @["workspace", "projects", "add", "--threads", "p"],
                 @["run", "--threads"],
                 @["run", "list", "--threads"]]:
      let e = usageErrorOf(argv)
      check e.kind == cekUnknownFlag
      check e.retired == "--threads"
      check e.replacement == "--jobs"
    # Declared by a nested command: not at the root nor at a sibling.
    let add = usageErrorOf(@["workspace", "projects", "add", "--default"])
    check add.retired == "--default"
    check add.replacement == "tool workspace enable --default"
    check usageErrorOf(@["workspace", "projects", "list",
      "--default"]).retired == ""
    check usageErrorOf(@["workspace", "--default"]).retired == ""
    check usageErrorOf(@["--from-mainlines", "branch", "x"]).retired == ""
    check usageErrorOf(@["switch", "--from-mainlines", "x"]).retired == ""

  test "a retired flag applies wherever in the body it is written":
    for argv in [@["--threads"], @["build", "--threads"],
                 @["build", "all", "--threads=2"]]:
      try:
        discard Late.load(argv)
        check false
      except CliUsageError as e:
        check e.kind == cekUnknownFlag
        check e.retired == "--threads"
        check e.replacement == "--jobs"

  test "a call:'s retired flag applies at its holder too":
    let atHolder = usageErrorOf(@["run", "--dry"])
    check atHolder.kind == cekUnknownFlag
    check atHolder.commandPath == @["run"]
    check atHolder.retired == "--dry"
    check atHolder.replacement == "--dry-run"
    # Not in the holder's other subcommands.
    check usageErrorOf(@["run", "list", "--dry"]).retired == ""
    # And the call: still runs.
    check Tool.load(@["run", "--dry-run"]).run.call.dryRun

  test "matching follows flagMatching and commandMatching":
    let flag = looseErrorOf(@["--THREADS", "switch", "x"])
    check flag.kind == cekUnknownFlag
    check flag.retired == "--threads"
    check flag.msg == "unknown flag '--THREADS' for 'loose' ('--threads' " &
      "is a retired spelling; use --jobs)"
    let word = looseErrorOf(@["CheckOut", "x"])
    check word.kind == cekUnknownSubcommand
    check word.retired == "checkout"
    check word.replacement == "loose switch"

  test "a custom usage exit code is kept":
    try:
      discard Tool.load(@["checkout"], options = CliOptions(
        usageExitCode: 64))
      check false
    except CliUsageError as e:
      check e.exitCode == 64
      check e.retired == "checkout"

  test "a retired spelling is never a suggestion":
    # Close only to retired spellings: nothing is suggested.
    let thread = usageErrorOf(@["--thread", "switch", "x"])
    check thread.retired == ""
    check thread.suggestions.len == 0
    let word = usageErrorOf(@["chekout"])
    check word.retired == ""
    check "checkout" notin word.suggestions
    let mainline = usageErrorOf(@["branch", "--from-mainline", "x"])
    check "--from-mainlines" notin mainline.suggestions
    # Close to a live spelling and a retired one: only the live one.
    let colr = usageErrorOf(@["--colr", "switch", "x"])
    check colr.suggestions == @["--color"]

  test "help never lists a retired spelling":
    var pages = @[Tool.helpText(), Tool.helpText(long = true),
      Tool.helpText(layout = cliClassicHelpLayout)]
    for path in [@["branch"], @["workspace"], @["workspace", "projects"],
                 @["workspace", "projects", "add"], @["run"]]:
      pages.add(Tool.helpText(path))
      pages.add(Tool.helpText(path, long = true))
    for page in pages:
      for spelling in retiredSpellings:
        let quoted = [" " & spelling & " ", " " & spelling & ",",
          " " & spelling & "\n", spelling & "=", spelling & "["]
        for q in quoted:
          check q notin page
      check "retired" notin page

  test "the help of a retired word names its replacement":
    try:
      discard Tool.helpText(@["checkout"])
      check false
    except CliUsageError as e:
      check e.kind == cekUnknownSubcommand
      check e.retired == "checkout"
      check e.replacement == "tool switch <branch>"

  test "the machine-readable help lists them apart from what is accepted":
    let doc = parseJson(Tool.helpJson(@["workspace", "projects", "add"]))
    let cmd = doc["command"]
    var spellings: seq[string] = @[]
    for p in cmd["parameters"]:
      for s in p["spellings"]:
        spellings.add(s.getStr)
    for spelling in retiredSpellings:
      check spelling notin spellings
    check cmd["retired"] == %*[
      {"spelling": "--default", "kind": "flag",
       "replacement": "tool workspace enable --default",
       "declaredIn": ["workspace", "projects", "add"]},
      {"spelling": "--threads", "kind": "flag", "replacement": "--jobs",
       "declaredIn": []},
      {"spelling": "-t", "kind": "flag", "replacement": "-j",
       "declaredIn": []},
      {"spelling": "--colour", "kind": "flag", "replacement": "--color",
       "declaredIn": []}]
    # The root's words, not its subcommands.
    let root = parseJson(Tool.helpJson())["command"]
    var words: seq[string] = @[]
    for c in root["commands"]:
      words.add(c["name"].getStr)
    check "checkout" notin words
    var retiredWords: seq[string] = @[]
    for r in root["retired"]:
      if r["kind"].getStr == "subcommand":
        retiredWords.add(r["spelling"].getStr)
    check retiredWords == @["checkout", "co"]
    # A call:'s retired flag is listed at its holder.
    let run = parseJson(Tool.helpJson(@["run"]))["command"]
    var runRetired: seq[string] = @[]
    for r in run["retired"]:
      runRetired.add(r["spelling"].getStr)
    check "--dry" in runRetired
    # A program without retired spellings has no such key anywhere.
    check "\"retired\"" notin Plain.helpJson()
    check "\"retired\"" notin Plain.helpJson(@["switch"])

  test "completion never offers a retired spelling":
    var offered: seq[string] = @[]
    for words in [@["-"], @["--"], @[""], @["c"], @["branch", "--"],
                  @["branch", "--fr"], @["branch", "--rep"],
                  @["workspace", ""], @["workspace", "s"],
                  @["workspace", "projects", ""],
                  @["workspace", "projects", "add", "--"],
                  @["run", "--"], @["run", "--d"], @["--th"], @["-"]]:
      offered.add(values(Tool.complete(words)))
    check offered.len > 0
    check "--jobs" in offered
    check "--dry-run" in offered
    for spelling in retiredSpellings:
      check spelling notin offered
