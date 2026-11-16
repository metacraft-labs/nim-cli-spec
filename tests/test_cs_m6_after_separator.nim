## test_cs_m6_after_separator: a positional that only the words after
## ``--`` fill (``afterSeparator = true``), the shape of ``env -- <command>``,
## ``cargo run -- <args>`` and ``nix develop -c``: ``[<selector>] --
## <command>...``.
##
## What it pins:
##
## * the words after the first ``--`` reach the positional exactly as
##   written: a later ``--``, words that look like flags, ``--help`` and the
##   empty word included;
## * a word before ``--`` never fills it: it goes to the other positionals,
##   and one that none of them takes is ``cekUnexpectedPositional``;
## * a ``--`` that is a flag's value (``--root --``, ``--root=--``, ``-r
##   --``) ends nothing, because the split happens where the tokenizer
##   already knows which words are values;
## * required and optional forms, a list positional before it, a nested
##   subcommand and a ``call:`` beside subcommands;
## * help (``[-- <command>...]``, ``-- <command>...`` when required), the
##   ``clispec-help/1`` JSON, the grammar, and completion after ``--``.
##
## The declaration errors are compile-time fixtures in
## ``tests/fixtures/cs_m2_invalid/after_separator_*.nim``, run by
## ``test_cs_m2_invalid_declarations_fail_to_compile``.
##
## Every fixture is a real ``cliProgram`` driven through the generated
## ``load``, ``helpText``, ``helpJson`` and ``complete``; nothing is mocked.

import std/[json, strutils, unittest]

import clispec

proc commandWords(ctx: CliCompletionContext): seq[CliCompletion] =
  ## The completer of the words after ``--``: a fixed list, so a test can
  ## tell its candidates from the selector's.
  cliCompletions(["ls", "-la", "make"])

cliProgram(Exec, "exec"):
  help "Run a command in an environment"
  boolFlag verbose is bool, short = 'v'
  flag root is string, short = 'r', default = "", help = "Work root"
  pos selector is string, required = false, values = ["proj", "lib"],
    help = "Which environment"
  pos command is seq[string], required = false, afterSeparator = true,
    complete = commandWords, help = "The command to run"

cliProgram(Run, "run"):
  boolFlag verbose is bool
  pos command is seq[string], afterSeparator = true,
    help = "The command to run"

cliProgram(Files, "files"):
  pos inputs is seq[string], required = false
  pos command is seq[string], required = false, afterSeparator = true

cliProgram(Tool, "tool"):
  boolFlag verbose is bool
  subcmd "dev":
    subcmd "exec":
      flag root is string, default = ""
      pos selector is string, required = false
      pos command is seq[string], required = false, afterSeparator = true,
        complete = commandWords
    subcmd "status":
      pos target is string, required = false

cliProgram(Launch, "launch"):
  subcmd "list":
    discard
  call:
    boolFlag dryRun is bool
    pos args is seq[string], required = false, afterSeparator = true,
      complete = commandWords

proc usageErrorOf(body: proc ()): ref CliUsageError =
  try:
    body()
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard
  nil

template usageError(body: proc ()): ref CliUsageError =
  ## The usage error ``body`` raises; a failed test (and a placeholder, so
  ## the checks after it still run) when it raises none.
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

proc idOf(g: CliGrammar; name: string): int =
  for id, p in g.params:
    if p.name == name:
      return id
  -1

suite "test_cs_m6_after_separator":

  test "the words after -- are the positional's, exactly as written":
    let a = Exec.load(@["--", "ls", "-la"])
    check a.selector == ""
    check a.command == @["ls", "-la"]
    let b = Exec.load(@["proj", "--", "ls"])
    check b.selector == "proj"
    check b.command == @["ls"]
    for words in [@["sh", "-c", "echo -- x"], @["--", "a", "--"],
                  @["-x", "--verbose", "--root=/w", "-v"], @["--help"],
                  @["-h"], @[""], @["", "x", ""], @["--", "--"],
                  @["proj"], @["-"]]:
      checkpoint(words.join(" "))
      let c = Exec.load(@["proj", "--"] & words)
      check c.command == words
      check c.selector == "proj"
      check not c.verbose
      check c.root == ""
    # Flags before ``--`` are read as usual.
    let f = Exec.load(@["-v", "--root", "/w", "lib", "--", "make", "-j"])
    check f.verbose
    check f.root == "/w"
    check f.selector == "lib"
    check f.command == @["make", "-j"]
    # Nothing after ``--``, or no ``--`` at all: the optional list is empty.
    check Exec.load(@["proj", "--"]).command.len == 0
    check Exec.load(@["proj"]).command.len == 0
    check Exec.load(@[]).command.len == 0

  test "a word before -- never fills it":
    let extra = usageError(proc () =
      discard Exec.load(@["proj", "extra", "--", "ls"]))
    check extra.kind == cekUnexpectedPositional
    check extra.spelling == "extra"
    check extra.argvIndex == 1
    let none = usageError(proc () = discard Exec.load(@["proj", "ls"]))
    check none.kind == cekUnexpectedPositional
    check none.spelling == "ls"
    check none.argvIndex == 1
    let only = usageError(proc () = discard Run.load(@["ls", "--", "x"]))
    check only.kind == cekUnexpectedPositional
    check only.spelling == "ls"
    check only.argvIndex == 0
    # The selector's ``values`` still check the word before ``--``.
    check usageError(proc () = discard Exec.load(@["nope", "--"])).kind ==
      cekInvalidValue

  test "a -- that is a flag's value ends nothing":
    let sep = Exec.load(@["--root", "--", "--", "ls"])
    check sep.root == "--"
    check sep.command == @["ls"]
    let eq = Exec.load(@["--root=--", "--", "ls", "--"])
    check eq.root == "--"
    check eq.command == @["ls", "--"]
    let short = Exec.load(@["-r", "--", "proj", "--", "ls"])
    check short.root == "--"
    check short.selector == "proj"
    check short.command == @["ls"]
    let cluster = Exec.load(@["-vr", "--", "--", "ls"])
    check cluster.verbose
    check cluster.root == "--"
    check cluster.command == @["ls"]
    # Without a terminator of its own, ``--root --`` leaves nothing for the
    # command, and the word after the value is a positional before ``--``.
    let noSep = Exec.load(@["--root", "--", "proj"])
    check noSep.root == "--"
    check noSep.selector == "proj"
    check noSep.command.len == 0

  test "candidates carry their argv index and are verbatim":
    let gr = Exec.cliGrammar
    let t = cliTokenize(gr, @["-v", "proj", "--", "a,b", "--", ""])
    let words = t.candidates[idOf(gr, "command")]
    check words.len == 3
    check words[0].text == "a,b"
    check words[0].argvIndex == 3
    check words[0].verbatim
    check words[1].text == "--"
    check words[1].argvIndex == 4
    check words[2].text == ""
    check words[2].argvIndex == 5
    check t.candidates[idOf(gr, "selector")][0].argvIndex == 1

  test "required: the words after -- must be there":
    check Run.load(@["--", "ls"]).command == @["ls"]
    check Run.load(@["--verbose", "--", "--verbose"]).command ==
      @["--verbose"]
    for argv in [@[], @["--"], @["--verbose"]]:
      checkpoint(argv.join(" "))
      let e = usageError(proc () = discard Run.load(argv))
      check e.kind == cekMissingRequired
      check e.spelling == "<command>"

  test "a list positional before it takes the words before --":
    let a = Files.load(@["a", "b", "--", "c", "d"])
    check a.inputs == @["a", "b"]
    check a.command == @["c", "d"]
    let b = Files.load(@["a", "b"])
    check b.inputs == @["a", "b"]
    check b.command.len == 0
    let c = Files.load(@["--", "a", "b"])
    check c.inputs.len == 0
    check c.command == @["a", "b"]

  test "nested subcommands: the terminator is the deepest command's":
    let t = Tool.load(@["--verbose", "dev", "exec", "proj", "--", "dev",
      "status"])
    check t.verbose
    check t.command == ToolCommand.dev
    check t.dev.command == ToolDevCommand.exec
    check t.dev.exec.selector == "proj"
    check t.dev.exec.command == @["dev", "status"]
    let flagValue = Tool.load(@["dev", "exec", "--root", "--", "--", "x"])
    check flagValue.dev.exec.root == "--"
    check flagValue.dev.exec.command == @["x"]
    # A sibling without the positional reads ``--`` as before.
    check Tool.load(@["dev", "status", "--", "-x"]).dev.status.target == "-x"
    # Before the subcommand word, ``--`` makes the next word a positional,
    # which a command with subcommands and no call: does not take.
    check usageError(proc () =
      discard Tool.load(@["--", "dev", "exec"])).kind ==
      cekUnexpectedPositional
    # A call: beside subcommands: the words after ``--`` run the call:.
    let l = Launch.load(@["--", "list", "-x"])
    check l.command == LaunchCommand.call
    check l.call.args == @["list", "-x"]
    let d = Launch.load(@["--dryRun", "--", "--dryRun"])
    check d.command == LaunchCommand.call
    check d.call.dryRun
    check d.call.args == @["--dryRun"]
    check Launch.load(@["--"]).call.args.len == 0
    check Launch.load(@["list"]).command == LaunchCommand.list

  test "help shows it after its --":
    let page = Exec.helpText()
    check "Usage: exec [options] [<selector>] [-- <command>...]" in page
    check "  [-- <command>...]  The command to run" in page
    let classic = Exec.helpText(layout = cliClassicHelpLayout)
    check "Usage: exec [options] [<selector>] [-- <command>...]" in classic
    check "[-- <command>...]" in classic
    let required = Run.helpText()
    check "Usage: run [options] -- <command>..." in required
    check "  -- <command>...  The command to run" in required
    check "Usage: tool dev exec [options] [<selector>] [-- <command>...]" in
      Tool.helpText(["dev", "exec"])
    check "Usage: launch [options] [<command>] [-- <args>...]" in
      Launch.helpText()
    # A positional without it is shown as before.
    check "Usage: tool dev status [options] [<target>]" in
      Tool.helpText(["dev", "status"])

  test "the model, the grammar and the JSON record it":
    let gr = Exec.cliGrammar
    check gr.params[idOf(gr, "command")].afterSeparator
    check not gr.params[idOf(gr, "selector")].afterSeparator
    check cliAfterSeparatorParam(gr, 0) == idOf(gr, "command")
    check cliWordPositionals(gr, 0) == @[idOf(gr, "selector")]
    let tg = Tool.cliGrammar
    check cliAfterSeparatorParam(tg, cliCommandAt(tg, ["dev", "status"])) ==
      -1
    var inModel = false
    for p in Exec.cliModel.root.params:
      if p.name == "command":
        inModel = p.afterSeparator
      else:
        check not p.afterSeparator
    check inModel
    let j = parseJson(Exec.helpJson())
    var seen = 0
    for p in j["command"]["parameters"]:
      if p["name"].getStr == "command":
        check p["afterSeparator"].getBool
        check p["list"].getBool
        check not p["required"].getBool
        inc seen
      else:
        check not p.hasKey("afterSeparator")
    check seen == 1
    check j["command"]["usage"].getStr ==
      "exec [options] [<selector>] [-- <command>...]"

  test "completion after -- offers that positional's values only":
    check values(Exec.complete(@["--", ""])) == @["ls", "-la", "make"]
    check values(Exec.complete(@["--", "-"])) == @["-la"]
    check values(Exec.complete(@["proj", "--", "ls", "-"])) == @["-la"]
    check values(Exec.complete(@["--", "--", "m"])) == @["make"]
    # The value of a flag is not a terminator.
    check values(Exec.complete(@["--root", "--", ""])) == @["proj", "lib"]
    # Before ``--``: the selector's values and the flags, never the
    # command's.
    check values(Exec.complete(@[""])) == @["proj", "lib"]
    check values(Exec.complete(@["proj", ""])).len == 0
    check "--verbose" in values(Exec.complete(@["-"]))
    check "-la" notin values(Exec.complete(@["-"]))
    check values(Tool.complete(@["dev", "exec", "--", "l"])) == @["ls"]
    check values(Launch.complete(@["--", ""])) == @["ls", "-la", "make"]
    check values(Launch.complete(@[""])) == @["list"]
