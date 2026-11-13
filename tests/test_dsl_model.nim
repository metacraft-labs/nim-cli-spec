## The ``cli:`` language parses into the model, construct by construct.
##
## Every test here runs the real compile-time parser on a real ``cli:`` body
## (through ``plainCliModel``, a constant) and checks the resulting model
## field by field. Nothing is mocked: the parser's only inputs are the
## compiler's AST and line information, and the test feeds it both.

import std/[macros, strutils, tables, unittest]

import clispec

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

proc paramNames(cmd: PlainCliCommand): seq[string] =
  for param in cmd.params:
    result.add(param.name)

const thisFile = currentSourcePath()

suite "parameter declarations":

  const model = plainCliModel:
    call:
      pos source is string
      pos extra is seq[string], position = 2, repeated = true
      pos(legacy, string)
      flag output is string, alias = "-o", required = true
      flag defines is seq[string], alias = "-D", format = concat,
        repeated = true
      flag config is string, alias = "--config", format = equals
      flag level is int, format = separate
      flag late is string, placement = before
      flag early is string, placement = global
      flag(oldStyle, string, alias = "--old")
      boolFlag verbose is bool, alias = "-v"
      boolFlag quiet

  let cmd = model.commands[0]

  test "pos records name, type, kind and the positional defaults":
    let p = cmd.paramNamed("source")
    check p.kind == cpkPositional
    check p.nimType == "string"
    check p.required
    check p.position == 0
    check not p.repeated
    check p.alias == ""

  test "pos takes position and repeated":
    let p = cmd.paramNamed("extra")
    check p.nimType == "seq[string]"
    check p.position == 2
    check p.repeated

  test "pos accepts the older `pos(<name>, <Type>)` spelling":
    let p = cmd.paramNamed("legacy")
    check p.kind == cpkPositional
    check p.nimType == "string"

  test "flag records alias and required":
    let p = cmd.paramNamed("output")
    check p.kind == cpkFlag
    check p.alias == "-o"
    check p.required
    check p.format == cafSeparate
    check p.placement == capAfterSubcommand

  test "flag is optional unless declared required":
    check not cmd.paramNamed("config").required

  test "format: concat, equals and separate":
    check cmd.paramNamed("defines").format == cafConcat
    check cmd.paramNamed("defines").repeated
    check cmd.paramNamed("config").format == cafEquals
    check cmd.paramNamed("level").format == cafSeparate
    check cmd.paramNamed("level").nimType == "int"

  test "placement: before and its `global` spelling":
    check cmd.paramNamed("late").placement == capBeforeSubcommand
    check cmd.paramNamed("early").placement == capBeforeSubcommand

  test "flag accepts the older `flag(<name>, <Type>)` spelling":
    let p = cmd.paramNamed("oldStyle")
    check p.nimType == "string"
    check p.alias == "--old"

  test "boolFlag is a bool flag, with or without `is bool`":
    let v = cmd.paramNamed("verbose")
    check v.kind == cpkFlag
    check v.nimType == "bool"
    check v.alias == "-v"
    let q = cmd.paramNamed("quiet")
    check q.nimType == "bool"
    check not q.required

  test "declaration order is kept":
    check cmd.paramNames == @["source", "extra", "legacy", "output",
      "defines", "config", "level", "late", "early", "oldStyle", "verbose",
      "quiet"]

  test "every declaration records its own source line":
    check cmd.paramNamed("source").sourceFile == thisFile
    check cmd.paramNamed("output").sourceLine >
      cmd.paramNamed("source").sourceLine
    check cmd.paramNamed("verbose").sourceLine >
      cmd.paramNamed("output").sourceLine

suite "flag-only and positional-only arguments":

  const model = plainCliModel:
    call:
      pos input is string, alias = "-i", format = concat, required = false,
        placement = before
      flag mode is string, position = 4

  let cmd = model.commands[0]

  test "a positional ignores the flag-only arguments":
    let p = cmd.paramNamed("input")
    check p.alias == ""
    check p.format == cafSeparate
    check p.placement == capAfterSubcommand

  test "a positional reads required":
    # ``required`` is not flag-only: a positional is required unless it says
    # ``required = false`` (or has a default).
    check not cmd.paramNamed("input").required

  test "a flag ignores position":
    check cmd.paramNamed("mode").position == 0

suite "commands and scopes":

  const model = plainCliModel:
    flag config is string, alias = "--config"
    boolFlag dryRun is bool
    call:
      pos script is string
    subcmd "build":
      flag jobs is int, alias = "-j"
      subcmd "target":
        pos name is string
      flag afterNested is string
      call:
        pos extra is string
    subcmd "clean":
      boolFlag all is bool

  test "flags directly under cli: are placed before the subcommand":
    check model.root.paramNamed("config").placement == capBeforeSubcommand
    check model.root.paramNamed("dryRun").placement == capBeforeSubcommand
    check model.root.path.len == 0
    check model.root.name == ""

  test "commands are listed after the scopes nested in them":
    var paths: seq[seq[string]] = @[]
    for cmd in model.commands:
      paths.add(cmd.path)
    check paths == @[@[], @["build", "target"], @["build"], @["build"],
      @["clean"]]

  test "call: is anonymous and adds no path segment":
    let call = model.commands[0]
    check call.name == ""
    check call.path.len == 0
    check call.paramNames == @["config", "dryRun", "script"]

  test "subcmd names the command and extends the path":
    let target = model.commandAt(["build", "target"])
    check target.name == "target"

  test "a nested scope sees what its parents declared before it opened":
    let target = model.commandAt(["build", "target"])
    check target.paramNames == @["config", "dryRun", "jobs", "name"]
    # `afterNested` is declared after `subcmd "target"` closed.
    check "afterNested" notin target.paramNames

  test "a call: nested in a subcmd takes the subcmd's path and name":
    # Listed before ``build`` itself, because it is nested in it.
    let nestedCall = model.commands[2]
    check nestedCall.path == @["build"]
    check nestedCall.name == "build"
    check nestedCall.paramNames == @["config", "dryRun", "jobs",
      "afterNested", "extra"]
    let build = model.commands[3]
    check build.path == @["build"]
    check build.paramNames == @["config", "dryRun", "jobs", "afterNested"]

  test "inherited parameters keep their placement":
    let clean = model.commandAt(["clean"])
    check clean.paramNamed("config").placement == capBeforeSubcommand
    check clean.paramNamed("all").placement == capAfterSubcommand

  test "a command records the line of its body":
    let clean = model.commandAt(["clean"])
    check clean.sourceFile == thisFile
    check clean.sourceLine == clean.paramNamed("all").sourceLine

suite "names that are Nim keywords":

  const model = plainCliModel:
    call:
      flag out is string, alias = "-o"
      flag `type` is string

  test "`out` and back-quoted names read as plain names":
    check model.commands[0].paramNames == @["out", "type"]

suite "statements without an extension":

  const model = plainCliModel:
    somethingElse "ignored"
    call:
      flag output is string, unknownArgument = 3
      outputs output

  test "an unknown statement and an unknown argument are ignored":
    check model.commands.len == 1
    check model.commands[0].paramNames == @["output"]

template parses(body: untyped): bool =
  ## Whether ``body`` is a ``cli:`` body the parser accepts. A rejected body
  ## is a compile error inside the macro, which ``compiles`` turns into
  ## ``false``.
  compiles(plainCliModel(body))

suite "invalid declarations are compile errors":

  test "an alias that is not a string literal":
    let ok = parses:
      call:
        flag x is string, alias = SomeConst
    check not ok

  test "boolFlag of a non-bool type":
    let ok = parses:
      call:
        boolFlag x is int
    check not ok

  test "a parameter without a type":
    let ok = parses:
      call:
        flag x
    check not ok

  test "an unsupported infix head":
    let ok = parses:
      call:
        flag x as string
    check not ok

  test "the same bodies without the error parse (vacuity guard)":
    let ok = parses:
      call:
        flag x is string, alias = "-x"
        boolFlag y is bool
        flag(z, string)
    check ok

macro headOf(stmt: untyped): untyped =
  newLit(parseCliParamHead(stmt))

macro declaredNames(body: untyped): untyped =
  newLit(cliDeclaredParamNames(body))

suite "lenient scanning":

  test "parseCliParamHead reads the typed and the bare forms":
    let typed = headOf(flag output is string)
    check typed.matched
    check typed.decl == cpdFlag
    check typed.typed
    check typed.name == "output"
    check typed.nimType == "string"
    let bare = headOf(boolFlag verbose)
    check bare.matched
    check bare.decl == cpdBoolFlag
    check not bare.typed
    check bare.nimType == ""

  test "parseCliParamHead does not match other statements":
    check not headOf(subcmd "x").matched
    check not headOf(outputs foo).matched
    check not headOf(pos "quoted" is string).matched

  test "cliDeclaredParamNames finds names in every scope":
    let names = declaredNames:
      flag a is string
      subcmd "x":
        pos b is string
        subcmd "y":
          boolFlag c
      call:
        flag(d, string)
    check names == @["a", "b", "c", "d"]

macro groupedParams(body: untyped): untyped =
  ## Expands every group a body names and returns the parameter names in
  ## order — the way a front end uses ``collectCliParamGroup`` and
  ## ``expandCliParamGroups``.
  var groups: CliParamGroups
  var names: seq[string] = @[]
  for stmt in body:
    if stmt.kind == nnkTemplateDef:
      let group = collectCliParamGroup(stmt)
      groups[group.name] = group.statements
  for stmt in body:
    if stmt.kind == nnkTemplateDef:
      continue
    var stack: seq[string] = @[]
    for expanded in expandCliParamGroups(stmt, groups, stack):
      names.add(parseCliParam[NoCliExtension](expanded).name)
  newLit(names)

suite "parameter groups":

  test "a group expands in place, nested groups included":
    let names = groupedParams:
      template inner() =
        flag b is string
      template outer() =
        flag a is string
        inner()
      outer()
      flag c is string
      inner()
    check names == @["a", "b", "c", "b"]

  test "a recursive group is a compile error":
    let ok = compiles(groupedParams do:
      template loop() =
        loop()
      loop())
    check not ok

  test "a group template with parameters is a compile error":
    let ok = compiles(groupedParams do:
      template g(x: int) =
        flag a is string
      g())
    check not ok

  test "the same groups without the error expand (vacuity guard)":
    let ok = compiles(groupedParams do:
      template g() =
        flag a is string
      g())
    check ok

  test "a group's name is style-insensitive":
    let names = groupedParams:
      template common_Flags() =
        flag a is string
      commonflags()
    check names == @["a"]

suite "the model is a plain value":

  test "a model is usable at run time and compares by value":
    const a = plainCliModel:
      call:
        flag x is string
    const b = plainCliModel:
      call:
        flag x is string
    check a.commands[0].params[0].name == b.commands[0].params[0].name
    check a.commands[0].params[0].ext == NoCliExtension()
    check ($a.commands[0].params[0].kind).startsWith("cpk")
