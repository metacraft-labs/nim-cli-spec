## test_cs_m6_render_argv: a parsed command line written back to argv words
## (``cliArgvOf``, ``Tool.canonicalArgv``) parses to the same command line.
##
## The property, for every command line ``argv`` a fixture's parser
## accepts: ``load(canonicalArgv(argv))`` holds the same values as
## ``load(argv)``, every parameter is decided the same way (from the command
## line, implied, its default, or unset), and the canonical form is a fixed
## point (``canonicalArgv`` of it is itself). It is checked over
##
## * a table of command lines that exercises every parameter kind and every
##   spelling the parser accepts, with the exact words expected where the
##   spelling is the point (the canonical spellings, ``--`` placement);
## * a few thousand random command lines per fixture, built from each
##   fixture's grammar with every spelling a flag has, values that look
##   like flags, ``--``, the empty word and subcommand words, keeping those
##   the parser accepts;
## * selections: by name, by group, the flags of one command rendered for
##   another (a command that runs another with the flags it shares), and
##   the errors for a name or group that does not exist.
##
## The fixtures are real ``cliProgram`` descriptions driven through the
## generated ``load`` and ``canonicalArgv``; nothing is mocked.

import std/[options, random, strutils, unittest]

import clispec

type Level = enum low, mid, high

cliProgram(Kit, "kit"):
  boolFlag verbose is bool, short = 'v', negatable = true
  flag quiet is int, counted = true, short = 'q'
  flag log is string, default = "info", short = 'L', alias = "--log-level"
  flag variant is seq[string]
  flag tags is seq[string], separator = ","
  flag level is Level, default = mid
  flag pick is string, values = ["a", "b"], optionalValue = "a",
    acceptsNextWord = true
  flag report is string, optionalValue = "report.json"
  flag fmt is string, format = equals, default = ""
  flag limit is Option[int]
  boolFlag release is bool, alsoSets = [variant = "buildType=release"]
  boolFlag loud is bool, short = 'l', alsoSets = [log = "summary"]
  boolFlag both is bool, alsoSets = [log = "both", variant = "both=1"]
  boolFlag noRunquota is bool
  boolFlag runquota is bool, alsoSets = [noRunquota = "false"]
  boolFlag marked is bool, sources = {}
  boolFlag mark is bool, alsoSets = [marked = "true"]
  flag token is string, visibility = internal, default = ""
  flag secret is string, visibility = hidden, default = ""
  flag jobs is int, default = 1, implies = [verbose = true]
  retired "--threads", replacement = "--jobs"
  call:
    boolFlag plain is bool
  group "Output", help = "What to print":
    flag color is string, default = "auto"
    boolFlag json is bool
  subcmd "build", aliases = ["b"]:
    flag workers is int, short = 'j', default = 4
    pos targets is seq[string], required = false
    pos command is seq[string], required = false, afterSeparator = true
  subcmd "exec":
    pos tool is string, required = false
    pos rest is seq[string], rest = true, required = false
  subcmd "first":
    pos all is seq[string], rest = true, required = false
  subcmd "wrap":
    call:
      pos words is seq[string], rest = true, required = false
  subcmd "launch":
    subcmd "list":
      boolFlag long is bool
    call:
      boolFlag dry is bool
      pos args is seq[string], required = false
  subcmd "pair":
    pos first is string, required = false
    pos second is string, required = false

cliProgram(Compat, "compat"):
  parsing colonValues, equalsTakesNext, lenientSwitchValues
  flag output is string, short = 'o', default = ""
  flag eq is string, format = equals, default = ""
  flag keepEnv is seq[string]
  boolFlag keep is bool, short = 'k'
  boolFlag color is bool, negatable = true
  flag trace is string, values = ["fast", "full"], optionalValue = "fast",
    acceptsNextWord = true
  pos rest is seq[string], required = false

cliProgram(Words, "words"):
  parsing helpWord, versionWord
  boolFlag verbose is bool, short = 'v'
  call:
    boolFlag quiet is bool
    pos args is seq[string], required = false
  subcmd "list":
    pos target is string, required = false
  subcmd "help", shadowedByWord = true, aliases = ["topics"]:
    flag depth is int, default = 1
  subcmd "show", shadowedByWord = true, aliases = ["version"]:
    boolFlag full is bool

cliProgram(Spliced, "spliced"):
  subcmd "build":
    flag jobs is int, default = 4
    flag variant is seq[string]
    boolFlag release is bool, alsoSets = [variant = "buildType=release"]
    boolFlag dryRun is bool
    pos selectors is seq[string], required = false
    pos actionArgs is seq[string], required = false, afterSeparator = true
  subcmd "test":
    flag shard is string, default = ""
    flag jobs is int, default = 4
    flag variant is seq[string]
    boolFlag release is bool, alsoSets = [variant = "buildType=release"]
    boolFlag dryRun is bool
    pos selectors is seq[string], required = false
    pos actionArgs is seq[string], required = false, afterSeparator = true

cliProgram(Next, "next"):
  flag pick is string, values = ["a", "b"], optionalValue = "a",
    acceptsNextWord = true
  boolFlag pickB is bool, alsoSets = [pick = "b"]
  boolFlag json is bool
  subcmd "pair":
    pos first is string, required = false
    pos second is string, required = false
  subcmd "build":
    pos targets is seq[string], required = false
    pos command is seq[string], required = false, afterSeparator = true

const wordsOptions = CliOptions(versionText: "words 1.0")

proc decisionKinds(g: CliGrammar; r: CliResolution): seq[CliDecisionKind] =
  for d in r.decisions:
    result.add(d.kind)

template checkRoundTrip(T: typedesc; argv: seq[string];
                        opt = CliOptions()) =
  ## The property, for one accepted command line.
  block:
    let g = T.cliGrammar()
    let opts = cliWithValueCheck(opt, `cliValueCheckOf T`)
    let words = T.canonicalArgv(argv, options = opt)
    checkpoint("argv:  " & $argv)
    checkpoint("words: " & $words)
    check $T.load(words, opt) == $T.load(argv, opt)
    let before = cliResolve(g, argv, opts)
    let after = cliResolve(g, words, opts)
    check after.selected == before.selected
    check decisionKinds(g, after) == decisionKinds(g, before)
    for id in 0 ..< g.params.len:
      for c in after.merged[id]:
        check c.source == csCli
    check T.canonicalArgv(words, options = opt) == words
    for w in words:
      check not w.startsWith("--threads")

template accepted(T: typedesc; argv: seq[string];
                  opt = CliOptions()): bool =
  var ok = true
  try:
    discard T.load(argv, opt)
  except CliUsageError, CliHelpRequest:
    ok = false
  ok

# ---------------------------------------------------------------------------
# Random command lines from a grammar.
# ---------------------------------------------------------------------------

const tricky = ["", "-", "--", "-x", "--help", "--log", "a=b", "a,b",
  "x y", "build", "list", "help", "version", "true", "false", "1", "0",
  "fast", "a", "b", "low", "high", "-1", "42", "buildType=release"]

proc randomValue(rng: var Rand; p: CliGrammarParam): string =
  if p.choices.len > 0 and rng.rand(3) > 0:
    return rng.sample(p.choices)
  if p.nimType in ["int", "Option[int]"] and rng.rand(3) > 0:
    return $rng.rand(-3 .. 99)
  rng.sample(tricky)

proc randomFlagWords(rng: var Rand; g: CliGrammar; id: int): seq[string] =
  ## One occurrence of flag ``id`` in one of the spellings it accepts.
  let p = g.params[id]
  var spellings = cliFlagSpellings(p)
  let spelling = rng.sample(spellings)
  if p.isSwitch or p.counted:
    case rng.rand(5)
    of 0:
      if p.negatable: return @["--no-" & cliLongName(p)]
      return @[spelling]
    of 1:
      if spelling.startsWith("--") and p.isSwitch:
        return @[spelling & "=" & rng.sample(["true", "false", "yes", "on"])]
      return @[spelling]
    else:
      return @[spelling]
  if p.hasOptionalValue and rng.rand(2) == 0:
    return @[spelling]
  let value = randomValue(rng, p)
  if spelling.startsWith("--"):
    if p.format == cafEquals or p.hasOptionalValue or rng.rand(1) == 0:
      return @[spelling & "=" & value]
    return @[spelling, value]
  if spelling.len == 2:
    if rng.rand(1) == 0 and value.len > 0:
      return @[spelling & value]
    return @[spelling, value]
  @[spelling & "=" & value]

proc randomArgv(rng: var Rand; g: CliGrammar): seq[string] =
  ## A command line over ``g``: a path, flags of the commands on it (some
  ## before the subcommand words), positionals, and words after ``--``.
  var node = 0
  var path = @[0]
  while g.commands[node].children.len > 0:
    var choices = g.commands[node].children
    if g.commands[node].callChild >= 0:
      choices.add(g.commands[node].callChild)
    if rng.rand(5) == 0:
      break
    node = rng.sample(choices)
    path.add(node)
  if g.commands[node].children.len == 0 and g.commands[node].callChild >= 0:
    node = g.commands[node].callChild
    path.add(node)
  for k, command in path:
    if k > 0 and not g.commands[command].isCall:
      result.add(g.commands[command].name)
    var flags: seq[int] = @[]
    for id in g.commands[command].params:
      if g.params[id].kind == cpkFlag and csCli in g.params[id].sources:
        flags.add(id)
    if flags.len > 0:
      for _ in 0 ..< rng.rand(4):
        result.add(randomFlagWords(rng, g, rng.sample(flags)))
  if rng.rand(2) > 0:
    for _ in 0 ..< rng.rand(3):
      result.add(rng.sample(tricky))
  if rng.rand(3) == 0:
    result.add("--")
    for _ in 0 ..< rng.rand(3):
      result.add(rng.sample(tricky))

template randomRoundTrips(T: typedesc; cases: int; seed: int64;
                          opt = CliOptions()) =
  block:
    var rng = initRand(seed)
    let g = T.cliGrammar()
    var acceptedCount = 0
    for _ in 0 ..< cases:
      let argv = randomArgv(rng, g)
      if accepted(T, argv, opt):
        inc acceptedCount
        checkRoundTrip(T, argv, opt)
    echo "  ", $T, ": ", acceptedCount, " of ", cases, " accepted"
    check acceptedCount >= cases div 10

suite "test_cs_m6_render_argv":

  test "every parameter kind in its canonical spelling":
    check Kit.canonicalArgv(@["-vqq", "--log-level", "x", "-L", "y",
      "--variant", "a=1", "--release", "--tags=p,q", "--tags", "r",
      "--level=high", "--fmt=--", "--limit", "7", "--token=t",
      "--secret", "s", "--json"]) == @["--verbose", "--quiet", "--quiet",
      "--log=y", "--variant=a=1", "--release", "--tags=p,q", "--tags=r",
      "--level=high", "--fmt=--", "--limit=7", "--token=t", "--secret=s",
      "--json"]
    # A negated switch, a switch's explicit values, optional values.
    check Kit.canonicalArgv(@["--no-verbose", "--json=false",
      "--report", "--pick", "b"]) == @["--no-verbose", "--json=false",
      "--report", "--pick=b"]
    check Kit.canonicalArgv(@["--verbose=false", "--json=true"]) ==
      @["--no-verbose", "--json"]

  test "values that look like flags, --, and empty values stay values":
    for value in ["-", "--", "-x", "--help", "", "--log=1", "x y"]:
      let argv = @["--log", value, "--variant", value]
      check Kit.canonicalArgv(argv) == @["--log=" & value,
        "--variant=" & value]
      checkRoundTrip(Kit, argv)

  test "alsoSets: written as the flag that set it, at its position":
    check Kit.canonicalArgv(@["--variant=a=1", "--release",
      "--variant=b=2"]) == @["--variant=a=1", "--release", "--variant=b=2"]
    check Kit.load(@["--variant=a=1", "--release"]).variant ==
      @["a=1", "buildType=release"]
    checkRoundTrip(Kit, @["--variant=a=1", "--release", "--variant=b=2"])
    # A scalar target: the later occurrence wins either way round.
    check Kit.canonicalArgv(@["--log=x", "-l"]) == @["--loud"]
    check Kit.canonicalArgv(@["-l", "--log=x"]) == @["--loud", "--log=x"]
    checkRoundTrip(Kit, @["--log=x", "-l"])
    checkRoundTrip(Kit, @["-l", "--log=x"])
    # Two targets, one flag.
    check Kit.canonicalArgv(@["--variant=a", "--both", "--log=z"]) ==
      @["--variant=a", "--both", "--log=z"]
    checkRoundTrip(Kit, @["--variant=a", "--both", "--log=z"])
    # A false value set through another flag.
    check Kit.canonicalArgv(@["--noRunquota", "--runquota"]) ==
      @["--runquota"]
    check not Kit.load(@["--noRunquota", "--runquota"]).noRunquota
    # A target the command line cannot spell comes with its flag.
    check Kit.canonicalArgv(@["--mark"]) == @["--mark"]
    check Kit.load(Kit.canonicalArgv(@["--mark"])).marked
    # A switch given twice gives the value twice, so it is written twice;
    # its last occurrence still decides its own value.
    check Kit.canonicalArgv(@["--release", "--release"]) ==
      @["--release", "--release"]
    check Kit.canonicalArgv(@["--mark", "--mark=false"]) ==
      @["--mark", "--mark=false"]
    check Kit.load(@["--mark", "--mark=false"]).marked
    checkRoundTrip(Kit, @["--mark", "--mark=false"])
    checkRoundTrip(Kit, @["--release", "--release"])

  test "alsoSets: the value stays when its flag is not selected":
    check Kit.canonicalArgv(@["--release", "--variant=x"],
      only = ["variant"]) == @["--variant=buildType=release", "--variant=x"]
    check Kit.canonicalArgv(@["-l"], only = ["log"]) == @["--log=summary"]
    # ... and goes when the parameter cannot be spelt.
    check Kit.canonicalArgv(@["--mark"], only = ["marked"]).len == 0

  test "implied values and defaults are not written":
    check Kit.canonicalArgv(@["--jobs=3"]) == @["--jobs=3"]
    check Kit.load(@["--jobs=3"]).verbose
    checkRoundTrip(Kit, @["--jobs=3"])
    check Kit.canonicalArgv(@[]).len == 0
    check Kit.canonicalArgv(@["build"]) == @["build"]

  test "retired spellings are refused, so never written":
    expect CliUsageError:
      discard Kit.canonicalArgv(@["--threads=2"])

  test "subcommands: their words, flags after them, positionals, --":
    check Kit.canonicalArgv(@["-v", "b", "-j8", "x", "--", "-n", "--",
      ""]) == @["build", "--verbose", "--workers=8", "x", "--", "-n", "--",
      ""]
    checkRoundTrip(Kit, @["-v", "b", "-j8", "x", "--", "-n", "--", ""])
    # A positional that looks like a flag needs `--` before it, where `--`
    # does not start an afterSeparator positional.
    check Kit.canonicalArgv(@["pair", "--", "-a", "--"]) ==
      @["pair", "--", "-a", "--"]
    checkRoundTrip(Kit, @["pair", "--", "-a", "--"])
    check Kit.canonicalArgv(@["pair", "a", "b"]) == @["pair", "a", "b"]
    # A rest positional takes its words as they come.
    check Kit.canonicalArgv(@["exec", "-v", "tool", "-x", "--", "y"]) ==
      @["exec", "--verbose", "tool", "-x", "--", "y"]
    checkRoundTrip(Kit, @["exec", "-v", "tool", "-x", "--", "y"])
    # A rest positional that starts at the command's first word: the
    # inherited flags go before its word.
    check Kit.canonicalArgv(@["-v", "first", "-v", "--"]) ==
      @["--verbose", "first", "-v", "--"]
    checkRoundTrip(Kit, @["-v", "first", "-v", "--"])
    check Kit.canonicalArgv(@["-v", "wrap", "-x"]) ==
      @["--verbose", "wrap", "-x"]
    checkRoundTrip(Kit, @["-v", "wrap", "-x"])

  test "a call: beside subcommands":
    check Kit.canonicalArgv(@["launch", "--dry", "x"]) ==
      @["launch", "--dry", "x"]
    check Kit.canonicalArgv(@["launch", "--", "list", "-y"]) ==
      @["launch", "--", "list", "-y"]
    checkRoundTrip(Kit, @["launch", "--", "list", "-y"])
    check Kit.canonicalArgv(@["launch", "list", "--long"]) ==
      @["launch", "list", "--long"]
    check Words.canonicalArgv(@["--", "list"], options = wordsOptions) ==
      @["--", "list"]
    check Words.canonicalArgv(@["--", "help"], options = wordsOptions) ==
      @["--", "help"]
    check Words.canonicalArgv(@["x", "y"], options = wordsOptions) ==
      @["x", "y"]
    for argv in [@["--", "list"], @["--", "help"], @["--", "version"],
                 @["-v", "--quiet", "--", "-x"], @["x", "list"]]:
      checkRoundTrip(Words, argv, wordsOptions)

  test "a subcommand a request word shadows is written by its alias":
    check Words.canonicalArgv(@["topics", "--depth=2"],
      options = wordsOptions) == @["topics", "--depth=2"]
    check Words.canonicalArgv(@["version", "--full"]) == @["show", "--full"]
    checkRoundTrip(Words, @["topics", "--depth=2"], wordsOptions)
    checkRoundTrip(Words, @["version", "--full"])
    # With a version text, the word `version` is the request.
    expect CliVersionRequest:
      discard Words.canonicalArgv(@["version"], options = wordsOptions)

  test "a flag that may take the next word as its value":
    # Bare `--pick` would take `a` as its value: another flag goes after
    # it, else `--` ends the flags.
    checkRoundTrip(Kit, @["--pick", "--json", "pair", "a"])
    check Kit.canonicalArgv(@["pair", "--pick", "--", "a"]) ==
      @["pair", "--pick", "--", "a"]
    checkRoundTrip(Kit, @["pair", "--pick", "--", "a"])
    check Kit.canonicalArgv(@["pair", "--json", "--pick", "--", "a"]) ==
      @["pair", "--json", "--pick", "--", "a"]
    checkRoundTrip(Kit, @["pair", "--json", "--pick", "--", "a"])
    check Compat.canonicalArgv(@["--trace", "--", "fast"]) ==
      @["--trace", "--", "fast"]
    checkRoundTrip(Compat, @["--trace", "--", "fast"])

  test "a flag that may take the next word keeps the order of its values":
    # `--pickB` gives `pick` a value, so moving the bare `--pick` before it
    # would change which one wins: `--` ends the flags instead.
    check Next.canonicalArgv(@["pair", "--pickB", "--pick", "--", "a"]) ==
      @["pair", "--pickB", "--pick", "--", "a"]
    checkRoundTrip(Next, @["pair", "--pickB", "--pick", "--", "a"])
    # Where `--` starts an afterSeparator positional: another flag that
    # can move goes last, else the flags follow the positionals.
    check Next.canonicalArgv(@["build", "--json", "a", "--pick"]) ==
      @["build", "--pick", "--json", "a"]
    check Next.canonicalArgv(@["build", "a", "--pick"]) ==
      @["build", "a", "--pick"]
    check Next.canonicalArgv(@["build", "--pickB", "a", "--pick", "--",
      "c"]) == @["build", "a", "--pickB", "--pick", "--", "c"]
    for argv in [@["build", "--json", "a", "--pick"],
                 @["build", "a", "--pick"],
                 @["build", "--pickB", "a", "--pick", "--", "c"],
                 @["build", "--", "--", "x"]]:
      checkRoundTrip(Next, argv)
    check Next.load(@["build", "--", "--", "x"]).build.command ==
      @["--", "x"]

  test "unicode values and positionals are written as they were":
    check Kit.canonicalArgv(@["--log", "ünï", "pair", "日本", "—x"]) ==
      @["pair", "--log=ünï", "日本", "—x"]
    checkRoundTrip(Kit, @["--log", "ünï", "pair", "日本", "—x"])

  test "equalsTakesNext: an empty value is never joined to the next word":
    check Compat.canonicalArgv(@["--output", "", "x"]) ==
      @["--output", "", "x"]
    checkRoundTrip(Compat, @["--output", "", "x"])
    check Compat.canonicalArgv(@["--eq=", "--keep"]) == @["--eq=", "--keep"]
    checkRoundTrip(Compat, @["--eq=", "--keep"])
    check Compat.canonicalArgv(@["--eq=", "--", "x"]) == @["--eq=", "--", "x"]
    checkRoundTrip(Compat, @["--eq=", "--", "x"])
    # colonValues and lenient switch values read back the same.
    checkRoundTrip(Compat, @["--output:a:b", "-k", "--color=no",
      "--keepEnv=A", "--keepEnv", "B=1"])

  test "selections: by name, by group, and errors":
    let argv = @["-v", "--log=x", "--json", "--color=never", "build", "-j2",
      "t", "--", "c"]
    check Kit.canonicalArgv(argv, only = ["log", "workers"]) ==
      @["build", "--log=x", "--workers=2"]
    check Kit.canonicalArgv(argv, only = ["log", "workers"],
      commandWords = false) == @["--log=x", "--workers=2"]
    check Kit.canonicalArgv(argv, group = "Output") ==
      @["build", "--json", "--color=never"]
    check Kit.canonicalArgv(argv, only = ["targets", "command"],
      commandWords = false) == @["t", "--", "c"]
    expect ValueError:
      discard Kit.canonicalArgv(argv, only = ["nosuch"])
    expect ValueError:
      discard Kit.canonicalArgv(argv, group = "Nothing")

  test "one command's flags, rendered for another that shares them":
    # A `test` that runs a `build` with the build flags it was given: the
    # names of `build`'s flags select them, and `build` parses them back.
    let g = Spliced.cliGrammar()
    var buildFlags: seq[string] = @[]
    for id in g.commands[cliHelpCommand(g, ["build"], "spliced")].params:
      if g.params[id].kind == cpkFlag:
        buildFlags.add(g.params[id].name)
    let argv = @["test", "--shard=1/2", "--jobs", "8", "--release",
      "--variant=a=1", "--dryRun", "sel", "--", "-x", "a b"]
    let t = Spliced.load(argv)
    let words = Spliced.canonicalArgv(argv, only = buildFlags,
      commandWords = false)
    check words == @["--jobs=8", "--release", "--variant=a=1", "--dryRun"]
    let b = Spliced.load(@["build"] & words & t.test.selectors & @["--"] &
      t.test.actionArgs)
    check b.build.jobs == t.test.jobs
    check b.build.variant == t.test.variant
    check b.build.release == t.test.release
    check b.build.dryRun == t.test.dryRun
    check b.build.selectors == @["sel"]
    check b.build.actionArgs == @["-x", "a b"]

  test "random command lines round-trip (Kit)":
    randomRoundTrips(Kit, 4000, 20261117)

  test "random command lines round-trip (Compat)":
    randomRoundTrips(Compat, 2000, 7)

  test "random command lines round-trip (Words)":
    randomRoundTrips(Words, 2000, 11, wordsOptions)

  test "random command lines round-trip (Next)":
    randomRoundTrips(Next, 2000, 17)

  test "random command lines round-trip (Spliced)":
    randomRoundTrips(Spliced, 1000, 13)

  test "cliArgvOf over candidates a caller holds":
    # The non-generated entry point: a resolution's command-line candidates
    # (what confutils' origin object records) and a parameter selection.
    let g = Kit.cliGrammar()
    let r = cliResolve(g, @["-q", "build", "-j3", "x"])
    let params = cliRenderParams(g, r.selected, ["quiet", "targets"])
    check cliArgvOf(g, r.selected, r.merged, params) ==
      @["build", "--quiet", "x"]
    check cliArgvOf(g, r.selected, r.merged, params,
      commandWords = false) == @["--quiet", "x"]
    # A candidate from another source is not the command line's.
    var given = r.merged
    for c in given.mitems:
      for x in c.mitems:
        x.source = csEnv
    check cliArgvOf(g, r.selected, given, params).len == 1
