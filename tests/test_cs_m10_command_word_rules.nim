## test_cs_m10_command_word_rules: the opt-in features that let a
## description keep the behaviour of a getopt-era command line (one migrated
## from confutils' type-based loader) in the places the flag rules of
## ``test_cs_m10_parse_compat_rules`` do not reach: how subcommand words are
## matched (``commandMatching``), a positional that takes the rest of the
## command line (``rest = true``), the bare words ``help`` and ``version``
## (``parsing helpWord, versionWord``), ``--version``
## (``CliOptions.versionText``), a subcommand those words shadow
## (``shadowedByWord = true``) and a help request without ``-h``
## (``parsing longHelpOnly``).
##
## Every fixture is a real ``cliProgram`` description driven through the
## generated ``load``, ``helpText``, ``helpJson`` and ``complete``.
## ``Plain`` is the same command tree with none of the features, and pins
## today's answers to exactly the command lines the features change.

import std/[json, options, sequtils, strutils, unittest]

import clispec

cliProgram(Plain, "plain"):
  boolFlag newTab is bool, perSource = [cli = "new-tab"]
  flag cwd is Option[string]
  call:
    boolFlag quiet is bool
  subcmd "list":
    pos listTarget is string, required = false
  subcmd "get-default-org":
    discard
  subcmd "start_backend":
    pos backendKind is string
  subcmd "arb":
    flag rpcUrl is string, default = "localhost", perSource = [cli = "rpc-url"]
    call:
      discard
    subcmd "explorer":
      discard
    subcmd "listRecentTx":
      discard
  subcmd "run":
    pos tracePath is string
    pos runArgs is seq[string], required = false
  subcmd "remote":
    pos remoteArgs is seq[string], required = false

cliProgram(Words, "words"):
  flagMatching ignoreStyle
  commandMatching ignoreStyle
  parsing helpWord, versionWord, longHelpOnly, helpWithAnyValue
  boolFlag newTab is bool, perSource = [cli = "new-tab"]
  flag cwd is Option[string]
  call:
    boolFlag quiet is bool
  subcmd "list":
    pos listTarget is string, required = false
  subcmd "get-default-org":
    discard
  subcmd "start_backend":
    pos backendKind is string
  subcmd "arb":
    flag rpcUrl is string, default = "localhost", perSource = [cli = "rpc-url"]
    call:
      discard
    subcmd "explorer":
      discard
    subcmd "listRecentTx":
      discard
  subcmd "run":
    pos tracePath is string
    pos runArgs is seq[string], rest = true, required = false
  subcmd "remote":
    pos remoteArgs is seq[string], rest = true, required = false

cliProgram(Cased, "cased"):
  commandMatching ignoreCase
  subcmd "list", aliases = ["ls"]:
    discard
  subcmd "start_backend":
    discard

cliProgram(HelpOnly, "helponly"):
  parsing helpWord, versionWord
  boolFlag verbose is bool, short = 'v'
  subcmd "build":
    pos target is string, required = false

cliProgram(OwnVersion, "ownversion"):
  parsing versionWord
  boolFlag version is bool
  subcmd "build":
    discard

cliProgram(Exec, "exec"):
  boolFlag verbose is bool, short = 'v'
  pos argv is seq[string], rest = true, required = false,
    values = ["alpha", "beta", "a,b", "--verbose"], separator = ","

cliProgram(LongOnly, "longonly"):
  parsing helpInCluster, longHelpOnly
  boolFlag edit is bool, short = 'e'

cliProgram(ClusterHelp, "clusterhelp"):
  parsing helpInCluster
  boolFlag edit is bool, short = 'e'

cliProgram(Shadow, "shadow"):
  commandMatching ignoreStyle
  parsing helpWord, versionWord
  boolFlag verbose is bool, short = 'v', help = "Talk more"
  subcmd "build":
    pos target is string, required = false
  subcmd "help", shadowedByWord = true, aliases = ["topics"],
      help = "Help topics":
    flag depth is int, default = 1
    pos topic is string, required = false
  subcmd "show", shadowedByWord = true, aliases = ["version"]:
    boolFlag full is bool
  subcmd "arb":
    subcmd "explorer":
      discard
    subcmd "HELP", shadowedByWord = true:
      discard

const version = "words 1.2.3"

proc usageErrorOf(body: proc ()): ref CliUsageError =
  try:
    body()
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard
  nil

proc helpRequestOf(body: proc ()): ref CliHelpRequest =
  ## The help request ``body`` raises, not a version request.
  try:
    body()
  except CliVersionRequest:
    discard
  except CliHelpRequest as e:
    return e
  except CliUsageError:
    discard
  nil

proc versionRequestOf(body: proc ()): ref CliVersionRequest =
  try:
    body()
  except CliVersionRequest as e:
    return e
  except CliHelpRequest, CliUsageError:
    discard
  nil

template expectRaised(found, what, placeholder: untyped): untyped =
  ## ``found``, or, when ``body`` raised nothing of the kind, a failed test
  ## and ``placeholder``, so the checks that follow still run.
  block:
    var e = found
    if e.isNil:
      checkpoint("expected " & what)
      fail()
      e = placeholder
    e

template usageError(body: proc ()): ref CliUsageError =
  expectRaised(usageErrorOf(body), "a usage error",
    (ref CliUsageError)(argvIndex: -99, spelling: "<no error>"))

template helpRequest(body: proc ()): ref CliHelpRequest =
  expectRaised(helpRequestOf(body), "a help request",
    (ref CliHelpRequest)(text: "<no help request>"))

template versionRequest(body: proc ()): ref CliVersionRequest =
  expectRaised(versionRequestOf(body), "a version request",
    (ref CliVersionRequest)(text: "<no version request>"))

proc values(cs: seq[CliCompletion]): seq[string] =
  for c in cs:
    result.add(c.value)

proc idOf(g: CliGrammar; name: string): int =
  for id, p in g.params:
    if p.name == name:
      return id
  -1

let withVersion = CliOptions(versionText: version)

suite "test_cs_m10_command_word_rules":

  test "without the features, today's answers stand":
    for word in ["LIST", "List", "l_ist", "help", "version", "HELP"]:
      checkpoint(word)
      let e = usageError(proc () = discard Plain.load(@[word]))
      check e.kind == cekUnknownSubcommand
      check e.spelling == word
      check e.argvIndex == 0
    check usageError(proc () =
      discard Plain.load(@["arb", "Explorer"])).kind == cekUnknownSubcommand
    let v = usageError(proc () = discard Plain.load(@["--version"]))
    check v.kind == cekUnknownFlag
    check v.spelling == "--version"
    check helpRequest(proc () = discard Plain.load(@["-h"])) != nil
    check helpRequest(proc () = discard Plain.load(@["run", "p", "--help"])) !=
      nil
    let r = Plain.load(@["remote", "--new-tab", "a"])
    check r.newTab
    check r.remote.remoteArgs == @["a"]
    check usageError(proc () =
      discard Plain.load(@["remote", "--bogus"])).kind == cekUnknownFlag
    check Plain.load(@["run", "p", "--", "-x"]).run.runArgs == @["-x"]
    check values(Plain.complete(@["LI"])).len == 0
    check values(Plain.complete(@["remote", "--ne"])) == @["--new-tab"]
    check values(Plain.complete(@["-"])) == @["--new-tab", "--cwd",
      "--quiet", "--help", "-h"]
    check Plain.optionsTable(layout = CliHelpLayout(helpFlag: "Help",
      versionFlag: "Version")) == "  --new-tab\n  --cwd <string>\n" &
      "  --quiet\n  -h, --help      Help\n  --version       Version\n"
    check not Plain.optionsTable(layout = CliHelpLayout(
      helpFlag: "Help")).contains("--version")
    let j = parseJson(Plain.helpJson())
    check j["parsing"] == %*{"flagMatching": "exact", "rules": []}
    for c in j["command"]["commands"]:
      for p in c["parameters"]:
        check not p.hasKey("rest")
    # The model and grammar carry the features' defaults.
    check Plain.cliModel.commandMatching == cfmExact
    check Plain.cliGrammar.commandMatching == cfmExact
    for p in Plain.cliGrammar.params:
      check not p.rest

  test "commandMatching ignoreStyle: subcommand words as cmpIgnoreStyle compares":
    check Words.load(@["list"]).command == WordsCommand.list
    for word in ["LIST", "List", "l_ist", "LI_ST"]:
      checkpoint(word)
      check Words.load(@[word]).command == WordsCommand.list
    check Words.load(@["GET-DEFAULT-ORG"]).command ==
      WordsCommand.getDefaultOrg
    for word in ["START_BACKEND", "StartBackend", "startbackend"]:
      checkpoint(word)
      let c = Words.load(@[word, "db"])
      check c.command == WordsCommand.startBackend
      check c.startBackend.backendKind == "db"
    check Words.load(@["arb", "Explorer"]).arb.command ==
      WordsArbCommand.explorer
    check Words.load(@["ARB", "listrecenttx"]).arb.command ==
      WordsArbCommand.listRecentTx
    # ``-`` is not ignored, ``_`` is; a word of another level is unknown.
    for word in ["get_default_org", "getdefaultorg", "start-backend",
                 "listrecenttx"]:
      checkpoint(word)
      let e = usageError(proc () = discard Words.load(@[word]))
      check e.kind == cekUnknownSubcommand
      check e.spelling == word
      check e.argvIndex == 0
      check e.commandPath.len == 0
      check e.expected == "list, get-default-org, start_backend, arb, run, " &
        "remote"
    let deep = usageError(proc () =
      discard Words.load(@["--new-tab", "arb", "list-recent-tx"]))
    check deep.kind == cekUnknownSubcommand
    check deep.commandPath == @["arb"]
    check deep.argvIndex == 2
    # Help and the machine-readable form find a command the same way.
    check Words.helpText(["LIST"]) == Words.helpText(["list"])
    check Words.helpJson(["Arb", "EXPLORER"]) ==
      Words.helpJson(["arb", "explorer"])
    let e = usageError(proc () = discard Words.helpText(["start-backend"]))
    check e.kind == cekUnknownSubcommand
    check parseJson(Words.helpJson())["parsing"]["commandMatching"].getStr ==
      "ignoreStyle"

  test "commandMatching ignoreCase: case only":
    check Cased.load(@["LIST"]).command == CasedCommand.list
    check Cased.load(@["LS"]).command == CasedCommand.list
    check Cased.load(@["Start_Backend"]).command == CasedCommand.startBackend
    for word in ["l_ist", "startbackend", "StartBackend"]:
      checkpoint(word)
      check usageError(proc () = discard Cased.load(@[word])).kind ==
        cekUnknownSubcommand
    check parseJson(Cased.helpJson())["parsing"]["commandMatching"].getStr ==
      "ignoreCase"

  test "commandMatching: completion offers the declared word for what was typed":
    check values(Words.complete(@["LI"])) == @["list"]
    check values(Words.complete(@["l_i"])) == @["list"]
    check values(Words.complete(@["START_"])) == @["start_backend"]
    check values(Words.complete(@["arb", "LISTR"])) == @["listRecentTx"]
    check values(Words.complete(@["get_d"])).len == 0
    # ``get_`` can still become ``get_-default-org``, which matches.
    check values(Words.complete(@["get_"])) == @["get-default-org"]
    # Words typed earlier are walked under the rule too.
    check values(Words.complete(@["ARB", "--rp"])) == @["--rpc-url"]
    check values(Cased.complete(@["L"])) == @["list"]
    check values(Cased.complete(@["l"])) == @["list"]
    check values(Cased.complete(@["LS"])) == @["ls"]
    check values(Cased.complete(@["l_"])).len == 0
    check values(Plain.complete(@["l"])) == @["list"]

  test "rest = true: every word from the first it takes, verbatim":
    let a = Words.load(@["run", "prog", "a", "b"])
    check a.command == WordsCommand.run
    check a.run.tracePath == "prog"
    check a.run.runArgs == @["a", "b"]
    let looks = Words.load(@["run", "prog", "-x", "--y=1", "--cwd", "/z"])
    check looks.run.runArgs == @["-x", "--y=1", "--cwd", "/z"]
    check looks.cwd.isNone
    check Words.load(@["run", "prog", "--", "a"]).run.runArgs == @["--", "a"]
    check Words.load(@["run", "prog", "a", "--help"]).run.runArgs ==
      @["a", "--help"]
    check Words.load(@["run", "prog", "version"]).run.runArgs == @["version"]
    check Words.load(@["run", "prog"]).run.runArgs.len == 0
    # Before it takes a word, flags (and ``--``) are read as usual.
    let before = Words.load(@["run", "--new-tab", "prog", "a"])
    check before.newTab
    check before.run.tracePath == "prog"
    check before.run.runArgs == @["a"]
    let term = Words.load(@["run", "--", "w", "prog"])
    check term.run.tracePath == "w"
    check term.run.runArgs == @["prog"]
    let bogus = usageError(proc () = discard Words.load(@["run", "--bogus",
      "prog"]))
    check bogus.kind == cekUnknownFlag
    check bogus.spelling == "--bogus"
    check bogus.argvIndex == 1
    check bogus.commandPath == @["run"]
    check usageError(proc () = discard Words.load(@["run", "-h", "prog"])).kind ==
      cekUnknownFlag
    check helpRequest(proc () = discard Words.load(@["run", "--help"])) != nil
    check versionRequest(proc () =
      discard Words.load(@["run", "--version", "prog"], withVersion)) != nil
    let missing = usageError(proc () = discard Words.load(@["run"]))
    check missing.kind == cekMissingRequired
    check missing.spelling == "<tracePath>"
    # The command's first positional: the rest starts right after its word.
    for argv in [@["--new-tab", "a"], @["--", "w"], @["--version"], @["-h"],
                 @["--help"], @["--bogus=1"], @["-"], @["help"]]:
      checkpoint(argv.join(" "))
      let r = Words.load(@["remote"] & argv, withVersion)
      check r.command == WordsCommand.remote
      check r.remote.remoteArgs == argv
      check not r.newTab
    check Words.load(@["remote"]).remote.remoteArgs.len == 0
    # Global flags before the subcommand word are still read.
    let g = Words.load(@["--new-tab", "remote", "--new-tab"])
    check g.newTab
    check g.remote.remoteArgs == @["--new-tab"]

  test "rest = true: candidates carry their argv index and are verbatim":
    let gr = Words.cliGrammar
    let t = cliTokenize(gr, @["--cwd", "/w", "run", "prog", "-x", "a,b"])
    let rest = t.candidates[idOf(gr, "runArgs")]
    check rest.len == 2
    check rest[0].text == "-x"
    check rest[0].argvIndex == 4
    check rest[0].verbatim
    check rest[1].argvIndex == 5
    check t.candidates[idOf(gr, "tracePath")][0].argvIndex == 3
    # A ``separator`` never splits a word of the rest.
    let e = Exec.load(@["a,b", "--verbose"])
    check e.argv == @["a,b", "--verbose"]
    check not e.verbose
    check usageError(proc () = discard Exec.load(@["gamma"])).kind ==
      cekInvalidValue
    check Exec.load(@["--verbose"]).argv == @["--verbose"]
    check Exec.load(@[]).argv.len == 0

  test "rest = true: completion offers only the rest's own values":
    check values(Words.complete(@["remote", ""])).len == 0
    check values(Words.complete(@["remote", "--"])).len == 0
    check values(Words.complete(@["remote", "a", "--ne"])).len == 0
    check values(Words.complete(@["run", "prog", "--ne"])).len == 0
    check values(Words.complete(@["run", "--ne"])) == @["--new-tab"]
    check values(Words.complete(@["--ne"])) == @["--new-tab"]
    check values(Exec.complete(@[""])) == @["alpha", "beta", "a,b",
      "--verbose"]
    check values(Exec.complete(@["-"])) == @["--verbose"]
    check values(Exec.complete(@["x", "al"])) == @["alpha"]

  test "rest = true: the model, the grammar and the JSON record it":
    let gr = Words.cliGrammar
    check gr.params[idOf(gr, "runArgs")].rest
    check not gr.params[idOf(gr, "tracePath")].rest
    check cliRestParam(gr, cliCommandAt(gr, ["run"])) ==
      (idOf(gr, "runArgs"), 1)
    check cliRestParam(gr, cliCommandAt(gr, ["list"])) == (-1, -1)
    var restInModel = false
    for c in Words.cliModel.commands:
      for p in c.params:
        if p.name == "remoteArgs":
          restInModel = p.rest
    check restInModel
    let j = parseJson(Words.helpJson(["run"]))
    for p in j["command"]["parameters"]:
      if p["name"].getStr == "runArgs":
        check p["rest"].getBool
      else:
        check not p.hasKey("rest")
    # Help text is unchanged by it: in the classic layout byte for byte; in
    # the standard one but for the help row, which under longHelpOnly is
    # ``--help`` alone.
    check Words.helpText(["run"], layout = cliClassicHelpLayout) ==
      Plain.helpText(["run"], layout = cliClassicHelpLayout).replace(
        "plain run", "words run")
    check Words.helpText(["run"]) ==
      Plain.helpText(["run"]).replace("plain run", "words run").replace(
        "  -h, --help  Print help\n", "  --help  Print help\n")

  test "parsing helpWord: the word help asks for the help of its level":
    for argv in [@["help"], @["HELP"], @["he_lp"], @["help", "list"],
                 @["help", "--bogus", "x"], @["--new-tab", "help"]]:
      checkpoint(argv.join(" "))
      let h = helpRequest(proc () = discard Words.load(argv))
      check h != nil
      check h.commandPath.len == 0
      check h.text == Words.helpText()
      check not h.json
    let arb = helpRequest(proc () = discard Words.load(@["arb", "help"]))
    check arb.commandPath == @["arb"]
    check arb.text == Words.helpText(["arb"])
    # Where no subcommand word is expected it is an ordinary word.
    let leaf = usageError(proc () =
      discard Words.load(@["arb", "explorer", "help"]))
    check leaf.kind == cekUnexpectedPositional
    check leaf.spelling == "help"
    check leaf.argvIndex == 2
    check Words.load(@["list", "help"]).list.listTarget == "help"
    check Words.load(@["run", "help"]).run.tracePath == "help"
    # An error before it wins; after ``--`` it is not a request.
    check usageError(proc () = discard Words.load(@["--bogus", "help"])).kind ==
      cekUnknownFlag
    let term = usageError(proc () = discard Words.load(@["--", "help"]))
    check term.kind == cekUnexpectedPositional
    # disableHelpFlag turns the word off too.
    let off = usageError(proc () =
      discard Words.load(@["help"], CliOptions(disableHelpFlag: true)))
    check off.kind == cekUnknownSubcommand
    # Compared under commandMatching: exactly in a description without it.
    check helpRequest(proc () = discard HelpOnly.load(@["help"])) != nil
    check usageError(proc () = discard HelpOnly.load(@["HELP"])).kind ==
      cekUnknownSubcommand
    check "helpWord" in $parseJson(Words.helpJson())["parsing"]["rules"]

  test "versionText and parsing versionWord: --version and the word version":
    for argv in [@["--version"], @["--VERSION"], @["--ver_sion"],
                 @["--version=1"], @["version"], @["VERSION"],
                 @["arb", "version"], @["arb", "--version"],
                 @["list", "--version"], @["--new-tab", "version", "x"]]:
      checkpoint(argv.join(" "))
      let v = versionRequest(proc () = discard Words.load(argv, withVersion))
      check v != nil
      check v.text == version
      check not v.json
    let arb = versionRequest(proc () =
      discard Words.load(@["arb", "version"], withVersion))
    check arb.commandPath == @["arb"]
    # A version request is a help request: a program that prints a help
    # request's text and exits 0 handles it unchanged.
    try:
      discard Words.load(@["version"], withVersion)
      check false
    except CliHelpRequest as e:
      check e.text == version
    # Where no subcommand word is expected, ``version`` is a word.
    check Words.load(@["list", "version"], withVersion).list.listTarget ==
      "version"
    check usageError(proc () = discard Words.load(@["arb", "explorer",
      "version"], withVersion)).kind == cekUnexpectedPositional
    # Without a version text neither means anything special.
    let flag = usageError(proc () = discard Words.load(@["--version"]))
    check flag.kind == cekUnknownFlag
    check flag.spelling == "--version"
    check usageError(proc () = discard Words.load(@["version"])).kind ==
      cekUnknownSubcommand
    # Without helpWithAnyValue an attached value is not a version request,
    # and without flagMatching the spelling is exact.
    let opts = CliOptions(versionText: "v9")
    check versionRequest(proc () = discard HelpOnly.load(@["--version"],
      opts)).text == "v9"
    check versionRequest(proc () = discard HelpOnly.load(@["version"],
      opts)).text == "v9"
    let attached = usageError(proc () = discard HelpOnly.load(
      @["--version=1"], opts))
    check attached.kind == cekUnknownFlag
    check attached.spelling == "--version"
    check attached.value == "1"
    check usageError(proc () = discard HelpOnly.load(@["--VERSION"],
      opts)).kind == cekUnknownFlag
    # Without versionWord the word is ordinary even with a version text.
    check usageError(proc () = discard Plain.load(@["version"],
      withVersion)).kind == cekUnknownSubcommand
    check versionRequest(proc () = discard Plain.load(@["--version"],
      withVersion)) != nil
    # A flag the description declares as ``--version`` keeps it.
    check OwnVersion.load(@["--version", "build"], withVersion).version
    check versionRequest(proc () = discard OwnVersion.load(@["version"],
      withVersion)) != nil
    # Help lists ``--version`` only when the layout asks for its row.
    check not Words.helpText().contains("--version")
    let table = Words.optionsTable(layout = CliHelpLayout(
      helpFlag: "Show this help", versionFlag: "Show the version"))
    check table.endsWith("  --help          Show this help\n" &
      "  --version       Show the version\n")
    check not OwnVersion.optionsTable(layout = CliHelpLayout(
      versionFlag: "Show the version")).contains("Show the version")

  test "parsing longHelpOnly: -h is not help, --help is":
    for argv in [@["-h"], @["list", "-h"], @["arb", "explorer", "-h"]]:
      checkpoint(argv.join(" "))
      let e = usageError(proc () = discard Words.load(argv))
      check e.kind == cekUnknownFlag
      check e.spelling == "-h"
      check e.argvIndex == argv.high
    check helpRequest(proc () = discard Words.load(@["--help"])) != nil
    check helpRequest(proc () = discard Words.load(@["--HELP"])) != nil
    check helpRequest(proc () = discard Words.load(@["--help=1"])) != nil
    check helpRequest(proc () = discard Words.load(@["list", "--help"])).
      commandPath == @["list"]
    check values(Words.complete(@["--he"])) == @["--help"]
    check values(Words.complete(@["-"])).find("-h") < 0
    check Words.optionsTable(layout = CliHelpLayout(helpFlag: "Help")).
      endsWith("\n  --help          Help\n")
    check Plain.optionsTable(layout = CliHelpLayout(helpFlag: "Help")).
      endsWith("\n  -h, --help      Help\n")
    # Without the rule, ``-h`` stays help.
    check helpRequest(proc () = discard HelpOnly.load(@["-h"])) != nil
    # Inside a cluster too, whatever helpInCluster says.
    for argv in [@["-help"], @["-eh"]]:
      checkpoint(argv.join(" "))
      let e = usageError(proc () = discard LongOnly.load(argv))
      check e.kind == cekUnknownFlag
      check e.spelling == argv[0]
    check helpRequest(proc () = discard ClusterHelp.load(@["-eh"])) != nil

  test "shadowedByWord: the word still asks for help, other words reach it":
    for argv in [@["help"], @["HELP"], @["he_lp"], @["help", "build"],
                 @["help", "--depth", "3"], @["help", "--help"],
                 @["help", "topics"], @["-v", "help", "x"]]:
      checkpoint(argv.join(" "))
      let h = helpRequest(proc () = discard Shadow.load(argv))
      check h.commandPath.len == 0
      check h.text == Shadow.helpText()
      check not h.json
    # One level down, the same: ``arb HELP`` is the help of ``arb``.
    let arb = helpRequest(proc () = discard Shadow.load(@["arb", "help"]))
    check arb.commandPath == @["arb"]
    check arb.text == Shadow.helpText(["arb"])
    # An alias that is not the reserved word reaches the subcommand.
    let t = Shadow.load(@["topics", "--depth", "3", "x"])
    check t.command == ShadowCommand.help
    check t.help.topic == "x"
    check t.help.depth == 3
    check Shadow.load(@["TOPICS"]).command == ShadowCommand.help
    check Shadow.load(@["arb", "explorer"]).arb.command ==
      ShadowArbCommand.explorer
    # Where the rule does not apply, the word reaches it.
    let off = Shadow.load(@["help", "x"], CliOptions(disableHelpFlag: true))
    check off.command == ShadowCommand.help
    check off.help.topic == "x"
    check Shadow.load(@["arb", "help"], CliOptions(disableHelpFlag: true)).
      arb.command == ShadowArbCommand.HELP
    # The flags still ask for help in it when they are on.
    let flagHelp = helpRequest(proc () = discard Shadow.load(@["topics",
      "--help"]))
    check flagHelp.commandPath == @["help"]
    check flagHelp.text == Shadow.helpText(["help"])

  test "shadowedByWord: the word version, with and without a version text":
    for argv in [@["version"], @["VERSION"], @["version", "--full"]]:
      checkpoint(argv.join(" "))
      check versionRequest(proc () = discard Shadow.load(argv,
        withVersion)).text == version
    check Shadow.load(@["show", "--full"], withVersion).show.full
    # Without a version text the word is the subcommand's alias.
    let v = Shadow.load(@["version", "--full"])
    check v.command == ShadowCommand.show
    check v.show.full
    check Shadow.load(@["show"]).command == ShadowCommand.show

  test "shadowedByWord: help, the JSON and the model keep the subcommand":
    let top = Shadow.helpText()
    check "  help, topics   Help topics\n" in top
    check "  show, version\n" in top
    # The help path names the subcommand: its own help.
    let own = Shadow.helpText(["help"])
    check own.startsWith(
      "Help topics\n\nUsage: shadow help [options] [<topic>]\n")
    check Shadow.helpText(["help"], layout = cliClassicHelpLayout).startsWith(
      "Usage: shadow help [options] [<topic>]\n")
    check "--depth <int>" in own
    check Shadow.helpText(["topics"]) == own
    check Shadow.helpText(["HELP"]) == own
    check Shadow.helpText(["arb", "help"]).startsWith("Usage: shadow arb HELP")
    let j = parseJson(Shadow.helpJson())
    var marked: seq[string] = @[]
    for c in j["command"]["commands"]:
      if c.hasKey("shadowedByWord"):
        check c["shadowedByWord"].getBool
        marked.add(c["name"].getStr)
      for k in c["commands"]:
        if k.hasKey("shadowedByWord"):
          marked.add(k["path"].getElems().mapIt(it.getStr).join(" "))
    check marked == @["help", "show", "arb HELP"]
    let own2 = parseJson(Shadow.helpJson(["help"]))["command"]
    check own2["shadowedByWord"].getBool
    check own2["aliases"] == %*["topics"]
    # Without the mark (and in Words, which has no such subcommand) the key
    # is absent.
    for c in parseJson(Words.helpJson())["command"]["commands"]:
      check not c.hasKey("shadowedByWord")
    var inModel: seq[string] = @[]
    for c in Shadow.cliModel.commands:
      if c.shadowedByWord:
        inModel.add(c.path.join(" "))
    check inModel == @["help", "show", "arb HELP"]
    var inGrammar = 0
    for c in Shadow.cliGrammar.commands:
      if c.shadowedByWord:
        inc inGrammar
    check inGrammar == 3
    # Usage errors name it among the subcommands.
    check usageError(proc () = discard Shadow.load(@["bogus"])).expected ==
      "build, help, show, arb"

  test "shadowedByWord: completion offers it and does not walk into it":
    check values(Shadow.complete(@[""])) == @["build", "help", "show", "arb"]
    check values(Shadow.complete(@["he"])) == @["help"]
    check values(Shadow.complete(@["to"])) == @["topics"]
    check values(Shadow.complete(@["ver"])) == @["version"]
    check values(Shadow.complete(@["arb", "H"])) == @["HELP"]
    # After the reserved word nothing of the subcommand is offered: the
    # parser reads no word after it.
    check values(Shadow.complete(@["help", "--"])) == @["--verbose", "--help"]
    check values(Shadow.complete(@["HELP", "--"])) == @["--verbose", "--help"]
    # Through its alias, or where the rule does not apply, it is walked.
    check values(Shadow.complete(@["topics", "--"])) == @["--verbose",
      "--depth", "--help"]
    check values(Shadow.complete(@["help", "--"],
      options = CliOptions(disableHelpFlag: true))) == @["--verbose",
      "--depth"]
    check values(Shadow.complete(@["version", "--f"])) == @["--full"]
    check values(Shadow.complete(@["version", "--f"],
      options = withVersion)).len == 0
