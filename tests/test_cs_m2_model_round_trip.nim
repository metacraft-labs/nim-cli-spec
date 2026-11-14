## test_cs_m2_model_round_trip: a command tree that uses every named
## argument a program declares about its own command line — ``help``,
## ``default``, ``short``, ``env``, ``values``, ``complete``, ``key``,
## ``sources``, ``merge``, ``separator``, ``optionalValue``, ``negatable``,
## ``counted``, ``implies``, ``visibility``, commands' ``aliases``, ``group``
## sections and parameter-group help — parses into the expected model.
##
## Every assertion reads a field of the model the real compile-time parser
## produced from a real ``cli:`` body (through ``plainCliModel``, which also
## places the generated type checks, so this fixture passes them too).
## Nothing is mocked. Each named argument is asserted on the parameter or
## command that declares it, and the parameters that exercise several
## arguments (``config``, ``verbose``) also have the fields they leave at
## their defaults checked, so an argument parsed into the wrong field fails
## here rather than going unnoticed.

import std/[macros, tables, unittest]

import clispec

type
  Color = enum
    red, green, blue

proc completeRepos(ctx: CliCompletionContext): seq[CliCompletion] =
  ## A completer (the signature ``cliModelTypeChecks`` requires), only
  ## referenced by the description.
  @[CliCompletion(value: ctx.prefix)]

proc strictest(candidates: openArray[CliSourcedValue[int]]): int =
  ## A combine proc (the signature ``cliModelTypeChecks`` requires), only
  ## referenced by the description.
  0

const defaultJobs = 4

const thisFile = currentSourcePath()

const model = plainCliModel:
  help "A fixture program"
  flag config is string, help = "configuration file", short = 'c',
    env = ["FIX_CONFIG", "FIX_CFG"], sources = {cli, env},
    visibility = internal
  boolFlag verbose is bool, negatable = true, help = "talk more"
  flag quiet is int, counted = true, short = 'q', visibility = hidden
  group "Output", help = "Where results go":
    flag writeReport is string, optionalValue = "report.json",
      key = "reports.path"
    flag color is Color, default = green, values = [red, green]
  subcmd "build", help = "Build things", aliases = ["b", "make"]:
    flag jobs is int, default = defaultJobs, merge = errorOnConflict,
      implies = [verbose = true, quiet = 2]
    flag tags is seq[string], separator = ",", merge = append,
      values = ["a", "b"], repeated = true
    flag level is int, merge = strictest, default = 1, sources = {file}
    flag repo is string, complete = completeRepos, merge = replace
    pos target is string, default = "all", help = "what to build",
      sources = {cli}
    group "Output":
      flag summary is string, env = "FIX_SUMMARY"
    subcmd "target", visibility = internal:
      flag deep is bool, visibility = shown
  subcmd "internal-helper", visibility = hidden, aliases = ["__helper"]:
    call(help = "the helper itself"):
      pos x is string
      pos rest is seq[string], required = false, repeated = true
      pos mode is string, required = true

proc commandAt(model: PlainCliModel; path: openArray[string]): PlainCliCommand =
  for cmd in model.commands:
    if cmd.path == @path:
      return cmd
  raise newException(KeyError, "no command at path " & $(@path))

proc paramNamed(cmd: PlainCliCommand; name: string): PlainCliParam =
  for param in cmd.params:
    if param.name == name:
      return param
  raise newException(KeyError, "no parameter " & name & " in " & $cmd.path)

proc checkExpr(e: CliExpr; code: string; param: PlainCliParam) =
  ## An expression is kept as its source text, attributed to the line it was
  ## written on (the declaration's line or a continuation line).
  check e.code == code
  check e.sourceFile == thisFile
  check e.sourceLine >= param.sourceLine
  check e.sourceLine <= param.sourceLine + 2
  check e.sourceColumn > 0

proc checkUnset(e: CliExpr) =
  check not e.isSet
  check e.code == ""

macro evalCode(code: static string): untyped =
  ## How a generator turns a kept expression back into code.
  parseExpr(code)

suite "test_cs_m2_model_round_trip":

  let root = model.root
  let build = model.commandAt(["build"])
  let target = model.commandAt(["build", "target"])
  # ``internal-helper`` holds a ``call:``, which has the same path and is
  # listed first; the subcmd itself is the last command.
  let helper = model.commands[3]

  test "commands: help, aliases and visibility":
    check root.help == "A fixture program"
    check root.aliases.len == 0
    check root.visibility == cvShown
    check build.help == "Build things"
    check build.aliases == @["b", "make"]
    check build.visibility == cvShown
    check target.help == ""
    check target.aliases.len == 0
    check target.visibility == cvInternal
    check helper.help == ""
    check helper.aliases == @["__helper"]
    check helper.visibility == cvHidden
    var paths: seq[seq[string]] = @[]
    for cmd in model.commands:
      paths.add(cmd.path)
    # The anonymous ``call`` inside the helper comes first: scopes are
    # listed after the scopes nested in them.
    check paths == @[@["build", "target"], @["build"],
      @["internal-helper"], @["internal-helper"]]
    let helperCall = model.commands[2]
    check helperCall.name == "internal-helper"
    check helperCall.help == "the helper itself"
    check helperCall.aliases.len == 0
    check helperCall.visibility == cvShown

  test "groups: declared once with their help":
    check model.groups.len == 1
    check model.groups[0].name == "Output"
    check model.groups[0].help == "Where results go"
    check model.groups[0].sourceFile == thisFile

  test "config: help, short, env, sources without file, internal":
    let p = root.paramNamed("config")
    check p.kind == cpkFlag
    check p.nimType == "string"
    check p.help == "configuration file"
    check p.short == 'c'
    check p.env == @["FIX_CONFIG", "FIX_CFG"]
    check p.sources == {csCli, csEnv}
    check p.configKey == ""
    check not p.keyDeclared
    check p.visibility == cvInternal
    check p.merge == cmrReplace
    checkUnset(p.default)
    checkUnset(p.optionalValue)
    checkUnset(p.complete)
    checkUnset(p.combine)
    check p.values.len == 0
    check p.implies.len == 0
    check p.separator == ""
    check not p.negatable
    check not p.counted
    check not p.required
    check p.group == ""
    check p.declaredIn.len == 0
    check p.placement == capBeforeSubcommand

  test "verbose: negatable bool with a derived key":
    let p = root.paramNamed("verbose")
    check p.nimType == "bool"
    check p.negatable
    check not p.counted
    check p.help == "talk more"
    check p.short == '\0'
    check p.env.len == 0
    check p.sources == {csFile, csEnv, csCli}
    check p.configKey == "verbose"
    check not p.keyDeclared
    check p.visibility == cvShown

  test "quiet: counted, short, hidden":
    let p = root.paramNamed("quiet")
    check p.nimType == "int"
    check p.counted
    check not p.negatable
    check p.short == 'q'
    check p.visibility == cvHidden
    check p.configKey == "quiet"

  test "writeReport: optionalValue and an explicit key, in a group":
    let p = root.paramNamed("writeReport")
    checkExpr(p.optionalValue, "\"report.json\"", p)
    check evalCode(model.root.params[3].optionalValue.code) == "report.json"
    check p.configKey == "reports.path"
    check p.keyDeclared
    check p.group == "Output"
    checkUnset(p.default)
    check not p.required

  test "color: an enum default and a closed value set":
    let p = root.paramNamed("color")
    check p.nimType == "Color"
    checkExpr(p.default, "green", p)
    check evalCode(model.root.params[4].default.code) == green
    check p.values.len == 2
    checkExpr(p.values[0], "red", p)
    checkExpr(p.values[1], "green", p)
    check p.group == "Output"
    check p.configKey == "color"

  test "jobs: an expression default, errorOnConflict and implications":
    let p = build.paramNamed("jobs")
    checkExpr(p.default, "defaultJobs", p)
    check p.merge == cmrErrorOnConflict
    checkUnset(p.combine)
    check p.implies.len == 2
    check p.implies[0].param == "verbose"
    checkExpr(p.implies[0].value, "true", p)
    check p.implies[1].param == "quiet"
    checkExpr(p.implies[1].value, "2", p)
    check p.configKey == "build.jobs"
    check p.declaredIn == @["build"]
    check p.placement == capAfterSubcommand

  test "tags: separator, append, values of the element type":
    let p = build.paramNamed("tags")
    check p.nimType == "seq[string]"
    check p.separator == ","
    check p.merge == cmrAppend
    check p.repeated
    check p.values.len == 2
    checkExpr(p.values[0], "\"a\"", p)
    checkExpr(p.values[1], "\"b\"", p)
    check p.configKey == "build.tags"

  test "level: a combine proc, file only":
    let p = build.paramNamed("level")
    check p.merge == cmrCombine
    checkExpr(p.combine, "strictest", p)
    checkExpr(p.default, "1", p)
    check p.sources == {csFile}
    check p.configKey == "build.level"
    check p.env.len == 0

  test "repo: a completer, merge spelled out as replace":
    let p = build.paramNamed("repo")
    checkExpr(p.complete, "completeRepos", p)
    check p.merge == cmrReplace
    checkUnset(p.combine)

  test "target: a positional with a default is optional; cli only":
    let p = build.paramNamed("target")
    check p.kind == cpkPositional
    checkExpr(p.default, "\"all\"", p)
    check not p.required
    check p.help == "what to build"
    check p.sources == {csCli}
    check p.configKey == ""
    check p.short == '\0'

  test "summary: a single env name, a group reopened without help":
    let p = build.paramNamed("summary")
    check p.env == @["FIX_SUMMARY"]
    check p.group == "Output"
    check p.configKey == "build.summary"

  test "nested commands inherit parameters with the declaring scope's key":
    let p = target.paramNamed("deep")
    check p.configKey == "build.target.deep"
    check p.declaredIn == @["build", "target"]
    check p.visibility == cvShown
    let inherited = target.paramNamed("jobs")
    check inherited.configKey == "build.jobs"
    check inherited.declaredIn == @["build"]
    let fromRoot = target.paramNamed("verbose")
    check fromRoot.configKey == "verbose"
    check fromRoot.declaredIn.len == 0

  test "a parameter of a call: takes the path of the enclosing subcmd":
    let p = model.commands[2].paramNamed("x")
    check p.configKey == "internal-helper.x"
    check p.declaredIn == @["internal-helper"]
    check p.required

  test "positionals: required unless they say otherwise":
    let call = model.commands[2]
    let rest = call.paramNamed("rest")
    check rest.kind == cpkPositional
    check not rest.required
    check rest.repeated
    checkUnset(rest.default)
    let mode = call.paramNamed("mode")
    check mode.required
    checkUnset(mode.default)

suite "boolFlag without `is bool` reads every named argument":

  const bare = plainCliModel:
    call:
      boolFlag verbose, alias = "-v"
      boolFlag quiet, required = true, alias = "-q"
      boolFlag(debug, alias = "-d")

  test "the first named argument is no longer skipped":
    let cmd = bare.commands[0]
    check cmd.paramNamed("verbose").alias == "-v"
    check cmd.paramNamed("quiet").alias == "-q"
    check cmd.paramNamed("quiet").required
    check cmd.paramNamed("debug").alias == "-d"

macro groupedModel(body: untyped): untyped =
  ## A front end that shares declarations through parameter groups: it
  ## collects the group templates, expands the groups named directly in the
  ## body and parses the result.
  var groups: CliParamGroups
  var rest = newStmtList()
  for stmt in body:
    if stmt.kind == nnkTemplateDef:
      let group = collectCliParamGroup(stmt)
      groups[group.name] = group.statements
    else:
      var stack: seq[string] = @[]
      for expanded in expandCliParamGroups(stmt, groups, stack):
        rest.add(expanded)
  newLit(parseCliModel[NoCliExtension, NoCliExtension](rest,
    NoCliExtension()))

suite "parameter groups with help":

  const grouped = groupedModel:
    template inner() =
      flag depth is int
    template commonFlags() =
      help "Options every command takes"
      boolFlag verbose is bool
      inner()
    template plain() =
      flag other is string
    commonFlags()
    plain()

  test "a group template with help becomes a group section":
    check grouped.groups.len == 1
    check grouped.groups[0].name == "commonFlags"
    check grouped.groups[0].help == "Options every command takes"
    let root = grouped.root
    check root.paramNamed("verbose").group == "commonFlags"
    check root.paramNamed("depth").group == "commonFlags"
    check root.paramNamed("other").group == ""
    # The group's help is not the command's help.
    check root.help == ""
