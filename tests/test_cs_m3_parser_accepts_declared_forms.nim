## test_cs_m3_parser_accepts_declared_forms: every form a description lets a
## command line take parses into the typed configuration object.
##
## The fixture program below is a real ``cliProgram`` description; each test
## feeds a real argv to the generated ``load`` and asserts the typed fields.
## Where the form is about how a value was written (which spelling, which
## argv word) the test also reads the parser's candidates through
## ``cliResolve`` on the same generated grammar and asserts the argv index
## and the spelling recorded for the value. Nothing is mocked.

import std/[options, paths, unittest]

import clispec

type
  Color = enum
    red, green, blue

cliProgram(Fx, "fx"):
  help "A fixture program"
  boolFlag verbose is bool, short = 'v', negatable = true, help = "Talk more"
  flag quiet is int, counted = true, short = 'q'
  flag config is string, alias = "--cfg", format = equals
  flag level is Option[int]
  subcmd "build", help = "Build things", aliases = ["b", "make"]:
    flag jobs is int, short = 'j', default = 4, implies = [verbose = true]
    flag output is Path, alias = "-o"
    flag define is seq[string], alias = "-D", format = concat,
      repeated = true
    flag tags is seq[string], separator = ",",
      values = ["fast", "safe", "small"]
    flag color is Color, default = green
    flag report is string, optionalValue = "report.json"
    flag ratio is float
    flag retries is Natural
    flag cpu is uint8
    flag letter is char
    flag mode is string, values = ["debug", "release"], default = "debug"
    flag secret is string, visibility = hidden
    flag slots is Option[int], values = [1, 2, 4]
    pos target is string
  subcmd "run":
    boolFlag dry is bool
    call:
      pos script is string
      pos args is seq[string], repeated = true, required = false
  subcmd "debug-dump", visibility = hidden:
    pos what is string, default = "all"
  subcmd "remote":
    flag url is string, required = true
    subcmd "add":
      pos name is string
    call:
      boolFlag list is bool, short = 'l'
      boolFlag all is bool, short = 'a'

proc idOf(name: string; declaredIn: seq[string] = @[]): int =
  ## The parameter id of ``name`` declared in ``declaredIn`` (or anywhere,
  ## when that is empty and the name is unique).
  let g = Fx.cliGrammar
  for id, p in g.params:
    if p.name == name and (declaredIn.len == 0 or p.declaredIn == declaredIn):
      return id
  raise newException(KeyError, "no parameter " & name)

proc winners(argv: openArray[string]; name: string): seq[CliCandidate] =
  ## The merged command-line candidates of parameter ``name``.
  let r = cliResolve(Fx.cliGrammar, argv)
  r.merged[idOf(name)]

suite "test_cs_m3_parser_accepts_declared_forms":

  test "long flags: --flag value and --flag=value; a switch bare":
    let a = Fx.load(@["--verbose", "build", "--jobs", "8", "app"])
    check a.verbose
    check a.command == FxCommand.build
    check a.build.jobs == 8
    check a.build.target == "app"
    let b = Fx.load(@["build", "--jobs=9", "app"])
    check b.build.jobs == 9
    let c = winners(["build", "--jobs", "8", "app"], "jobs")
    check c.len == 1
    check c[0].spelling == "--jobs"
    check c[0].argvIndex == 1
    check c[0].valueArgvIndex == 2
    check c[0].text == "8"
    let d = winners(["build", "--jobs=9", "app"], "jobs")
    check d[0].argvIndex == 1
    check d[0].valueArgvIndex == -1
    check d[0].spelling == "--jobs"

  test "short flags: -j 8, -j8 and clusters of switches":
    check Fx.load(@["build", "-j", "8", "app"]).build.jobs == 8
    check Fx.load(@["build", "-j8", "app"]).build.jobs == 8
    let a = Fx.load(@["-vqq", "build", "app"])
    check a.verbose
    check a.quiet == 2
    let q = winners(["-vqq", "build", "app"], "quiet")
    check q.len == 2
    check q[0].spelling == "-q"
    check q[0].argvIndex == 0
    let j = winners(["build", "-j8", "app"], "jobs")
    check j[0].spelling == "-j"
    check j[0].text == "8"
    # A cluster ending in a letter that takes a value takes the next word.
    let b = Fx.load(@["-v", "build", "-j", "3", "app"])
    check b.build.jobs == 3

  test "aliases: an equals-only alias, a separate alias, a concat alias":
    check Fx.load(@["--cfg=a.toml", "run", "s"]).config == "a.toml"
    check Fx.load(@["--config=b.toml", "run", "s"]).config == "b.toml"
    let c = winners(["--cfg=a.toml", "run", "s"], "config")
    check c[0].spelling == "--cfg"
    check c[0].argvIndex == 0
    let o = Fx.load(@["build", "-o", "out/bin", "app"])
    check o.build.output == Path("out/bin")
    let d = Fx.load(@["build", "-DFOO", "-DBAR=1", "--define=BAZ", "app"])
    check d.build.define == @["FOO", "BAR=1", "BAZ"]
    let dc = winners(["build", "-DFOO", "-DBAR=1", "app"], "define")
    check dc.len == 2
    check dc[0].spelling == "-D"
    check dc[1].argvIndex == 2
    check dc[1].text == "BAR=1"

  test "optional-value flags never take the next word":
    let a = Fx.load(@["build", "--report", "app"])
    check a.build.report == "report.json"
    check a.build.target == "app"
    let b = Fx.load(@["build", "--report=r.json", "app"])
    check b.build.report == "r.json"
    let c = winners(["build", "--report", "app"], "report")
    check c[0].form == ccfBare
    check c[0].argvIndex == 1

  test "--no-* negation":
    let a = Fx.load(@["--no-verbose", "build", "app"])
    check not a.verbose
    let c = winners(["--no-verbose", "build", "app"], "verbose")
    check c[0].form == ccfNegated
    check c[0].spelling == "--no-verbose"
    # A switch also takes an explicit value.
    check not Fx.load(@["--verbose=false", "run", "s"]).verbose

  test "counted flags: -vv style and repeated":
    let a = Fx.load(@["-q", "-qq", "--quiet", "run", "s"])
    check a.quiet == 4
    check Fx.load(@["run", "s"]).quiet == 0

  test "-- ends the flags":
    let a = Fx.load(@["build", "--", "--weird"])
    check a.build.target == "--weird"
    let b = Fx.load(@["run", "s", "--", "-x", "--y"])
    check b.run.script == "s"
    check b.run.args == @["-x", "--y"]

  test "repeated and delimited lists collect every occurrence":
    let a = Fx.load(@["build", "--tags", "fast,safe", "--tags=small", "app"])
    check a.build.tags == @["fast", "safe", "small"]
    let c = winners(["build", "--tags", "fast,safe", "--tags=small", "app"],
      "tags")
    check c.len == 2
    check c[0].valueArgvIndex == 2
    check c[1].argvIndex == 3

  test "closed value sets: enums and values":
    check Fx.load(@["build", "--color", "blue", "app"]).build.color == blue
    check Fx.load(@["build", "--color=Red", "app"]).build.color == red
    check Fx.load(@["build", "--mode", "release", "app"]).build.mode ==
      "release"
    # The values of an Option are values of the type it holds.
    check Fx.load(@["build", "--slots=4", "app"]).build.slots == some(4)
    check Fx.load(@["build", "app"]).build.slots.isNone

  test "command aliases dispatch like the name":
    check Fx.load(@["b", "app"]).command == FxCommand.build
    check Fx.load(@["make", "-j2", "app"]).build.jobs == 2

  test "nested subcommands and a call: next to them":
    let a = Fx.load(@["remote", "--url", "u", "add", "origin"])
    check a.command == FxCommand.remote
    check a.remote.url == "u"
    check a.remote.command == FxRemoteCommand.add
    check a.remote.add.name == "origin"
    let b = Fx.load(@["remote", "--url=u", "-l"])
    check b.remote.command == FxRemoteCommand.call
    check b.remote.call.list
    let c = Fx.load(@["remote", "--url=u"])
    check c.remote.command == FxRemoteCommand.call
    check not c.remote.call.list
    # A cluster that needs a letter only the call: declares runs it too,
    # mixing in the inherited -v.
    let d = Fx.load(@["remote", "--url=u", "-vla"])
    check d.verbose
    check d.remote.command == FxRemoteCommand.call
    check d.remote.call.list
    check d.remote.call.all

  test "a call: in a command without subcommands fills that command":
    let a = Fx.load(@["run", "--dry", "x.sh", "a", "b"])
    check a.run.dry
    check a.run.script == "x.sh"
    check a.run.args == @["a", "b"]
    let s = winners(["run", "x.sh", "a"], "script")
    check s[0].argvIndex == 1
    check s[0].spelling == ""

  test "type conversion: float, ranges, unsigned, char, Option, distinct":
    let a = Fx.load(@["--level", "3", "build", "--ratio", "0.5",
      "--retries", "2", "--cpu", "200", "--letter", "x", "app"])
    check a.level == some(3)
    check a.build.ratio == 0.5
    check a.build.retries == 2
    check a.build.cpu == 200'u8
    check a.build.letter == 'x'
    check Fx.load(@["build", "app"]).level.isNone

  test "hidden items are accepted":
    let a = Fx.load(@["debug-dump", "graph"])
    check a.command == FxCommand.debugDump
    check a.debugDump.what == "graph"
    check Fx.load(@["debug-dump"]).debugDump.what == "all"
    check Fx.load(@["build", "--secret", "s", "app"]).build.secret == "s"

  test "defaults, and implications that yield to explicit values":
    let a = Fx.load(@["build", "app"])
    check a.build.jobs == 4
    check a.build.color == green
    check a.build.mode == "debug"
    check not a.verbose
    # ``--jobs`` implies ``--verbose`` ...
    check Fx.load(@["build", "-j2", "app"]).verbose
    # ... unless verbose was given explicitly.
    check not Fx.load(@["--no-verbose", "build", "-j2", "app"]).verbose
    let r = cliResolve(Fx.cliGrammar, ["build", "-j2", "app"])
    check r.decisions[idOf("verbose")].kind == cdkImplied
    check r.decisions[idOf("verbose")].impliedBy == idOf("jobs")
    check r.decisions[idOf("color")].kind == cdkDefault
    check r.decisions[idOf("jobs")].kind == cdkSource

  test "a scalar given twice keeps the last occurrence":
    let r = cliResolve(Fx.cliGrammar, ["build", "-j1", "--jobs=2", "app"])
    check r.merged[idOf("jobs")].len == 1
    check r.merged[idOf("jobs")][0].text == "2"
    check r.overridden[idOf("jobs")].len == 1
    check r.overridden[idOf("jobs")][0].argvIndex == 1
    check Fx.load(@["build", "-j1", "--jobs=2", "app"]).build.jobs == 2
