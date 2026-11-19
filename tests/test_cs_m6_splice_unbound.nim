## test_cs_m6_splice_unbound: ``cliUnbound`` turns a ``cli:`` body built with
## ``quote`` back into the tree the language reads, and a program generated
## from such a body, mounted under another program's command, parses its
## words.
##
## Each rule is checked on the tree ``quote`` really produces (no tree is
## built by hand to look like it), and the whole is checked end to end
## through ``cliProgram`` and the generated parser. Nothing is mocked.

import std/[macros, strutils, unittest]

import clispec

proc sharedFlags(): NimNode {.compileTime.} =
  quote do:
    boolFlag verbose is bool, alias = "-v"
    flag jobs is int, default = 2

proc toolBody(): NimNode {.compileTime.} =
  let shared = sharedFlags()
  cliUnbound(quote do:
    subcmd "run", help = "Run a command " & "under the tool":
      `shared`
      flag tags is seq[string], repeated = true
      pos command is seq[string], required = false, afterSeparator = true)

macro unboundRepr(): untyped =
  ## The body as ``cliUnbound`` returns it, as text.
  newLit(toolBody().repr)

macro hasSymbols(): untyped =
  ## Whether any node of the body is still a symbol or a symbol choice.
  proc walk(n: NimNode): bool =
    if n.kind in {nnkSym, nnkOpenSymChoice, nnkClosedSymChoice}:
      return true
    for child in n:
      if walk(child):
        return true
    false
  newLit(walk(toolBody()))

macro rawKinds(): untyped =
  ## What ``quote`` alone gives, so the test shows there was something to
  ## undo: the kind of ``required``'s value, and whether ``seq[string]`` is
  ## a call.
  let raw = quote do:
    flag tags is seq[string], required = false
  var valueKind = ""
  var typeKind = ""
  proc walk(n: NimNode) =
    if n.kind == nnkExprEqExpr and n[0].eqIdent("required"):
      valueKind = $n[1].kind
    if n.kind == nnkInfix and n[0].eqIdent("is"):
      typeKind = $n[2].kind
    for child in n:
      walk(child)
  walk(raw)
  newLit(valueKind & " " & typeKind)

macro unboundLine(): untyped =
  ## The line of the ``subcmd`` statement before and after: kept.
  let s = quote do:
    subcmd "x":
      boolFlag y is bool
  let u = cliUnbound(s)
  newLit(s[0].lineInfoObj.line == u[0].lineInfoObj.line and
    u[0].lineInfoObj.line > 0)

macro mountTool(): untyped =
  let body = toolBody()
  result = quote do:
    cliProgram(Host, "host"):
      subcmd "tool", help = "The tool's commands":
        `body`

mountTool()

suite "test_cs_m6_splice_unbound":

  test "quote binds what the language reads as written":
    check rawKinds() == "nnkSym nnkCall"

  test "no symbol is left, and the forms are the written ones":
    check not hasSymbols()
    let text = unboundRepr()
    check "required = false" in text
    check "is seq[string]" in text
    # The two literals joined with `&` are one literal.
    check "\"Run a command under the tool\"" in text
    # The spliced group is flattened into the command's body: no nested
    # statement list, so `verbose` is declared directly in `run`.
    check "boolFlag verbose is bool" in text

  test "line information is kept":
    check unboundLine()

  test "a program generated from the mounted body parses its words":
    let conf = Host.load(@["tool", "run", "-v", "--tags", "a", "--tags",
      "b", "--", "make", "all"])
    check conf.command == HostCommand.tool
    check conf.tool.command == HostToolCommand.run
    check conf.tool.run.verbose
    check conf.tool.run.jobs == 2
    check conf.tool.run.tags == @["a", "b"]
    check conf.tool.run.command == @["make", "all"]

  test "the help text is the folded literal":
    check Host.cliGrammar.commands.len > 0
    var found = false
    for c in Host.cliGrammar.commands:
      if c.help == "Run a command under the tool":
        found = true
    check found
