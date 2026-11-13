## A consumer attaches its own declarations through the model's extension
## slots, and the library parser fills them without knowing what they are.
##
## The extension below is a small documentation vocabulary — ``help = …`` on
## parameters, ``summary`` / ``example`` / ``needs`` statements on commands —
## chosen because it exercises every part of the hook contract: an argument
## the library does not take, a statement the library does not know,
## inheritance into nested scopes, validation against the parameters
## visible so far, and a compile error raised from inside a hook. It is a
## real extension driven through the real compile-time parser, not a stub.

import std/[macros, strutils, unittest]

import clispec

type
  DocParam = object
    help: string
    secret: bool

  DocCommand = object
    summary: string
    examples: seq[string]
    needs: seq[string]
    sawRootOnly: bool

  DocCli = CliCommand[DocCommand, DocParam]

proc parseCliParamExtension(ext: var DocParam; kind: CliParamKind;
                            arg: NimNode): bool =
  case cliIdentText(arg[0]).normalize
  of "help":
    ext.help = cliStrLit(arg[1], "help")
    true
  of "secret":
    if kind != cpkFlag:
      error("only a flag can be secret", arg)
    ext.secret = cliBoolLit(arg[1], ext.secret)
    true
  else:
    false

proc parseCliCommandExtension(cmd: var DocCli; stmt: NimNode;
                              scope: CliScope): bool =
  case cliCalleeName(stmt).normalize
  of "summary":
    cmd.ext.summary = cliStrLit(stmt[1], "summary")
    true
  of "example":
    cmd.ext.examples.add(cliStrLit(stmt[1], "example"))
    true
  of "needs":
    let name = cliIdentText(stmt[1])
    var visible = false
    for param in cmd.params:
      if param.name == name:
        visible = true
    if not visible:
      if name in cliDeclaredParamNames(scope.wholeBody):
        error("needs: '" & name & "' is declared, but not in this scope",
          stmt)
      else:
        error("needs: '" & name & "' does not exist", stmt)
    cmd.ext.needs.add(name)
    true
  of "rootonly":
    if not scope.isRoot:
      error("rootOnly belongs directly under cli:", stmt)
    cmd.ext.sawRootOnly = true
    true
  else:
    false

macro docModel(body: untyped): untyped =
  newLit(parseCliModel[DocCommand, DocParam](body,
    DocCommand(summary: "(no summary)")))

proc paramNamed(cmd: DocCli; name: string): CliParam[DocParam] =
  for param in cmd.params:
    if param.name == name:
      return param
  raise newException(KeyError, "no parameter " & name)

proc commandAt(model: CliModel[DocCommand, DocParam];
               path: openArray[string]): DocCli =
  for cmd in model.commands:
    if cmd.path == @path:
      return cmd
  raise newException(KeyError, "no command at " & $(@path))

suite "parameter extension":

  const model = docModel:
    call:
      flag output is string, alias = "-o", help = "where to write",
        secret = true, unclaimed = 1
      pos input is string, help = "what to read", position = 3

  let cmd = model.commands[0]

  test "the hook fills the parameter's extension":
    check cmd.paramNamed("output").ext.help == "where to write"
    check cmd.paramNamed("output").ext.secret
    check cmd.paramNamed("input").ext.help == "what to read"
    check not cmd.paramNamed("input").ext.secret

  test "the library still reads its own arguments around the extension's":
    check cmd.paramNamed("output").alias == "-o"
    check cmd.paramNamed("input").position == 3

suite "command extension":

  const model = docModel:
    rootOnly()
    flag verbose is bool
    summary "the tool"
    example "tool --verbose"
    subcmd "build":
      flag output is string
      summary "builds"
      example "tool build --output x"
      needs output
      subcmd "all":
        needs verbose
    subcmd "clean":
      unknownStatement 42

  test "the root starts from the consumer's defaults and reads its statements":
    check model.root.ext.summary == "the tool"
    check model.root.ext.sawRootOnly
    check model.root.ext.examples == @["tool --verbose"]

  test "a nested scope inherits the extension and extends it":
    let build = model.commandAt(["build"])
    check build.ext.summary == "builds"
    check build.ext.examples == @["tool --verbose", "tool build --output x"]
    check build.ext.needs == @["output"]
    let all = model.commandAt(["build", "all"])
    check all.ext.summary == "builds"
    check all.ext.needs == @["output", "verbose"]

  test "a scope that changes nothing keeps its parent's extension":
    let clean = model.commandAt(["clean"])
    check clean.ext.summary == "the tool"
    check clean.ext.examples == @["tool --verbose"]
    check clean.ext.needs.len == 0

template parses(body: untyped): bool =
  compiles(docModel(body))

suite "a hook rejects a declaration at compile time":

  test "a statement the hook validates against the visible parameters":
    let ok = parses:
      subcmd "a":
        flag x is string
      subcmd "b":
        needs x
    check not ok

  test "an argument the hook refuses for this parameter kind":
    let ok = parses:
      call:
        pos x is string, secret = true
    check not ok

  test "a statement the hook only allows at the root":
    let ok = parses:
      subcmd "a":
        rootOnly()
    check not ok

  test "the same declarations, made valid, parse (vacuity guard)":
    let ok = parses:
      rootOnly()
      subcmd "a":
        flag x is string, secret = true
        needs x
    check ok

suite "the empty extension":

  test "NoCliExtension claims nothing the documentation extension claims":
    const plain = plainCliModel:
      summary "ignored"
      call:
        flag output is string, help = "ignored"
    check plain.commands[0].params[0].name == "output"
    check plain.commands[0].params[0].alias == ""
    check ($plain.commands[0].params[0]).contains("ext: ()")
