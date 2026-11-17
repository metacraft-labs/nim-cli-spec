## A program's own command line: the typed configuration object, its parser
## and its help, generated from one ``cli:`` description.
##
## .. code-block:: nim
##   import clispec
##
##   cliProgram(Tool, "tool"):
##     help "Builds things"
##     boolFlag verbose is bool, short = 'v', help = "Talk more"
##     subcmd "build", help = "Build a project":
##       flag jobs is int, short = 'j', default = 4
##       pos target is string
##
##   let conf = Tool.load(@["-v", "build", "-j8", "app"])
##   assert conf.verbose and conf.command == ToolCommand.build
##   assert conf.build.jobs == 8 and conf.build.target == "app"
##
## The configuration object
## ========================
##
## Each command gets an object type with one field per parameter it
## declares, named and typed as declared. The root's type is the name given
## to ``cliProgram``; a subcommand's is its parent's name followed by its
## word in CamelCase (``ToolBuild``, ``ToolBuildTarget``; ``debug-dump`` is
## ``DebugDump``).
##
## A command with subcommands holds the chosen one in a case object branch:
## a discriminator ``command`` of the pure enum ``<Type>Command``, with one
## value per subcommand word (in camelCase), and a branch field of the same
## name holding that subcommand's object. Nested objects keep each
## command's fields in its own namespace, so two subcommands may both
## declare ``--output``, which one flat case object could not hold (Nim
## requires field names to be unique across all branches); the case branch
## means only the chosen subcommand's object exists, and reading another is
## a run-time error instead of a silently empty value.
##
## A ``call:`` (what a command runs when no subcommand word follows) adds its
## parameters to the object of the command that holds it when that command
## has no subcommands. When it has some, the ``call:`` is one more branch,
## with the discriminator value and field ``call`` and the type
## ``<Type>Call``.
##
## A parameter declared at an outer command is a field of that command's
## object only, even though nested commands accept it too, so it has one
## value wherever it was written.
##
## What a field holds
## ==================
##
## The value the command line supplies, else the value an ``implies`` of a
## parameter the command line supplied sets, else its ``default``, else the
## type's zero value (``none`` for an ``Option``). A ``required`` parameter
## that gets no value is a usage error. A ``counted`` parameter holds the number of occurrences; a list
## collects every occurrence. ``values`` entries must be constant
## expressions: they are evaluated at compile time for help and completion.
##
## Generated procedures
## ====================
##
## For a type ``Tool`` (exported when written
## ``cliProgram(Tool, "tool", exported = true)``):
##
## * ``Tool.load(argv, options)`` parses ``argv`` (without the program
##   name) and returns a ``Tool``. ``Tool.load(options)`` parses the
##   process's own arguments. It raises ``CliUsageError`` for a command line
##   it rejects and ``CliHelpRequest`` when help is asked for (its subtype
##   ``CliVersionRequest`` when the version is); it never ends the process.
##   A program prints them with ``Tool.printHelp(e)`` and
##   ``Tool.printError(e)``.
## * ``Tool.printHelp(e, stream = stdout)`` and ``Tool.printError(e, stream
##   = stderr)`` print a help request and a usage error as
##   ``cliPrintHelp`` and ``cliPrintError`` (``clispec/errors``) do,
##   deciding colour and width for the stream, under the program's own
##   colour configuration (below).
## * ``Tool.helpText(path)`` and ``Tool.helpJson(path)`` render the help of
##   the command reached by the subcommand words ``path`` (see
##   ``clispec/help``; ``helpText(path, long = true)`` is the long page
##   ``--help`` prints); an unknown word is a ``CliUsageError``.
## * ``Tool.complete``, ``Tool.completionReply`` and
##   ``Tool.completionScript`` are the shell completion of
##   ``clispec/completion`` and ``clispec/completion_scripts``.
## * ``Tool.cliGrammar`` is the grammar and ``Tool.cliModel`` the model, both
##   constants.
##
## A consumer whose model carries an extension generates the same code from
## its own macro with ``cliProgramCode``.
##
## Colour parameters
## =================
##
## The colour knobs of ``clispec/styles`` can be fixed for one program with
## named arguments before the body, named as the knobs' parameters:
## ``colors``, ``colorEnv``, ``colorDepth``, ``background``, ``colorFgBg``,
## ``backgroundQuery``, ``userColors`` and ``palette``, with the values the
## ``clispec_*`` defines take (a word, a number or a string literal):
##
## .. code-block:: nim
##   cliProgram(Tool, "tool", colors = auto, colorDepth = 24,
##              userColors = on, palette = "heading=1;35"):
##     flag jobs is int, default = 4
##
## A parameter applies over its define, which applies over the default; a
## value the knob does not allow is a compile-time error naming the
## parameter and listing the allowed values. The program's configuration
## (``CliProgramArgs.colorConfig``) is a constant
## (``cliColorConfigName``) that ``load`` passes to the parser, which builds
## a help request's renderers for it, and that ``printHelp`` and
## ``printError`` pass to the library's printers. A program that prints
## only through them carries only the code its configuration needs: with
## ``colors = never``, none of the styling or detection code; with a knob
## off or fixed, none of that knob's code (see "Compile-time knobs" in
## ``clispec/styles``).
##
## Configuration files and the environment
## =======================================
##
## The description also declares what other sources need per parameter
## (``env``, ``key``, ``sources``, ``merge``, ``configSchema``, the naming
## conventions), but reading them is not this library's job:
## `confutils <https://github.com/metacraft-labs/nim-confutils>`_ is
## instantiated over a clispec description and adds configuration-file
## layers, the environment, the merge rules and an origin object for every
## value, delegating the command line to the code generated here. For a
## library that generates such code beside ``cliProgramCode``'s, the names
## and shapes it generates are exported: ``cliGeneratedNames``,
## ``cliObjectHolds``, ``cliHasObject``, ``cliBranches``,
## ``cliBuilderName``, ``cliCompletersName``, ``cliColorConfigName``,
## ``cliFieldBare`` and ``cliFieldAllowed``.

import std/[macros, os, strutils]

import ./[model, dsl, grammar, parser, help, completion, completion_scripts,
  styles]

export parser, help, grammar, completion, completion_scripts

proc cliCommandLineParams*(): seq[string] =
  ## The process's own arguments, without the program name.
  commandLineParams()

proc cliSelectedChild*(g: CliGrammar; r: CliResolution; command: int): int =
  ## The selected command directly inside ``command``, or -1.
  for i, c in r.selected:
    if c == command and i + 1 < r.selected.len:
      return r.selected[i + 1]
  -1

proc cliHelpCommand*(g: CliGrammar; path: openArray[string];
                     program: string): int {.raises: [CliUsageError].} =
  ## The command reached by the subcommand words ``path``, or a usage error
  ## (unknown subcommand) naming the command that does not know the word,
  ## with its suggestions.
  result = 0
  var walked: seq[string] = @[]
  for word in path:
    let next = cliChildNamed(g, result, word)
    if next < 0:
      let e = newCliUsageError(cekUnknownSubcommand, program, walked, -1,
        word, expected = cliSubcommandWords(g, result).join(", "))
      e.cliAddErrorContext(g, result)
      e.suggestions = cliSubcommandSuggestions(g, result, word)
      e.cliNameRetired(g, result)
      raise e
    walked.add(g.commands[next].name)
    result = next

# ---------------------------------------------------------------------------
# The generator.
# ---------------------------------------------------------------------------

func camelWord(word: string; upper: bool): string =
  ## ``debug-dump`` → ``debugDump`` (``DebugDump`` when ``upper``).
  var up = upper
  for ch in word:
    if ch in {'a'..'z', 'A'..'Z', '0'..'9'}:
      if up:
        result.add(ch.toUpperAscii)
        up = false
      else:
        result.add(ch)
    else:
      up = result.len > 0 or upper
  if result.len == 0 or result[0] in {'0'..'9'}:
    result = (if upper: "Cmd" else: "cmd") & result

func quoted(name: string): NimNode =
  nnkAccQuoted.newTree(ident(name))

proc exportedName(name: string; exported: bool): NimNode =
  if exported: postfix(quoted(name), "*") else: quoted(name)

type
  CliGeneratedNames* = object
    ## The names ``cliProgramCode`` gives what it generates for one
    ## description, for a library that generates code beside it.
    typeName*: string
      ## The root's type, as given to ``cliProgram``.
    typeNames*: seq[string]
      ## Per command index: the name of its configuration object type
      ## (``Tool``, ``ToolBuild``, ``ToolCall``). A ``call:`` without an
      ## object of its own (``cliHasObject``) has a name nothing uses.
    fieldOfChild*: seq[string]
      ## Per command index: its discriminator value and branch field in its
      ## parent's object (``build``, ``call``); empty for the root.

  GenContext = object
    g: CliGrammar
    names: CliGeneratedNames
    exported: bool
    grammarConst: NimNode

proc problemAt(message, file: string; line: int) =
  let n = newEmptyNode()
  n.setLineInfo(file, line, 0)
  error(message, n)

proc cliObjectHolds*(g: CliGrammar; command: int): seq[int] =
  ## The parameter ids whose fields the configuration object of ``command``
  ## holds: its own parameters, and those of its ``call:`` when it has no
  ## subcommands.
  result = g.commands[command].ownParams
  let call = g.commands[command].callChild
  if call >= 0 and g.commands[command].children.len == 0:
    for id in g.commands[call].ownParams:
      result.add(id)

proc cliHasObject*(g: CliGrammar; command: int): bool =
  ## Whether ``command`` has a configuration object type of its own: every
  ## command but a ``call:`` of a command without subcommands, whose
  ## parameters its parent's object holds.
  not g.commands[command].isCall or
    g.commands[g.commands[command].parent].children.len > 0

proc cliBranches*(g: CliGrammar; command: int): seq[int] =
  ## The commands that are branches of ``command``'s object: its
  ## subcommands, then its ``call:`` when it has subcommands.
  result = g.commands[command].children
  if g.commands[command].children.len > 0 and
      g.commands[command].callChild >= 0:
    result.add(g.commands[command].callChild)

proc cliGeneratedNames*(g: CliGrammar; typeName: string): CliGeneratedNames =
  ## The type and branch names ``cliProgramCode`` uses for ``g`` when the
  ## root's type is ``typeName``.
  result.typeName = typeName
  result.typeNames = newSeq[string](g.commands.len)
  result.fieldOfChild = newSeq[string](g.commands.len)
  for k, cmd in g.commands:
    if k == 0:
      result.typeNames[k] = typeName
    elif cmd.isCall:
      result.typeNames[k] = result.typeNames[cmd.parent] & "Call"
      result.fieldOfChild[k] = "call"
    else:
      result.typeNames[k] = result.typeNames[cmd.parent] &
        camelWord(cmd.name, true)
      result.fieldOfChild[k] = camelWord(cmd.name, false)

proc cliBuilderName*(names: CliGeneratedNames; command: int): NimNode =
  ## The generated ``proc (g: CliGrammar; r: CliResolution): <Type>`` that
  ## builds ``command``'s configuration object from a resolution (not
  ## exported: it is visible in the description's module).
  ident("cliBuild" & names.typeNames[command])

proc cliCompletersName*(names: CliGeneratedNames): NimNode =
  ## The generated ``proc (): seq[CliCompleter]`` that builds the
  ## completers, by parameter id (not exported).
  ident("cliCompletersOf" & names.typeName)

proc cliColorConfigName*(names: CliGeneratedNames): NimNode =
  ## The generated constant holding the program's colour configuration (a
  ## ``CliColorConfig``: its ``cliProgram`` parameters over the defines;
  ## not exported). The generated ``load``, ``printHelp`` and
  ## ``printError`` pass it as their ``config``; a library that calls the
  ## parser or the printers for the program passes it too, so the program
  ## carries only the code its configuration needs.
  ident("cliColorConfigOf" & names.typeName)

proc cliValueCheckName*(names: CliGeneratedNames): NimNode =
  ## The generated ``CliValueCheck`` of the description (not exported):
  ## ``proc (id: int; text: string): string``, which says whether a text is
  ## a valid value of parameter ``id``. A library that calls the parser
  ## itself passes it in ``CliOptions.valueCheck``
  ## (``cliWithValueCheck``), as the generated ``load`` does.
  ident("cliValueCheckOf" & names.typeName)

proc cliCommandEnumName*(names: CliGeneratedNames; command: int): string =
  ## The discriminator enum of ``command``'s object (``<Type>Command``).
  names.typeNames[command] & "Command"

proc cliShapedTypeDecls*(g: CliGrammar; names: CliGeneratedNames;
                         command: int; suffix: string; fieldType: NimNode;
                         exported: bool): seq[NimNode] =
  ## A type of the same shape as ``command``'s configuration object, named
  ## its type name followed by ``suffix``: one field of type ``fieldType``
  ## per parameter field, the same ``command`` discriminator (the enum the
  ## configuration object declares) and each branch holding the
  ## subcommand's type of that shape. For a library that records something
  ## per configuration value (where it came from, say).
  var fields = newNimNode(nnkRecList)
  for id in cliObjectHolds(g, command):
    fields.add(newIdentDefs(exportedName(g.params[id].name, exported),
      fieldType.copyNimTree))
  let kids = cliBranches(g, command)
  if kids.len > 0:
    let enumName = cliCommandEnumName(names, command)
    var caseNode = nnkRecCase.newTree(newIdentDefs(
      exportedName("command", exported), ident(enumName)))
    for kid in kids:
      let field = names.fieldOfChild[kid]
      caseNode.add(nnkOfBranch.newTree(
        newDotExpr(ident(enumName), quoted(field)),
        nnkRecList.newTree(newIdentDefs(exportedName(field, exported),
          ident(names.typeNames[kid] & suffix)))))
    fields.add(caseNode)
  result.add(nnkTypeDef.newTree(
    exportedName(names.typeNames[command] & suffix, exported),
    newEmptyNode(), nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(),
      fields)))

proc cliShapedBuilderProc*(g: CliGrammar; names: CliGeneratedNames;
                           command: int; suffix, procPrefix: string;
                           extraParams: seq[NimNode];
                           fieldValues: seq[NimNode]): NimNode =
  ## ``proc <procPrefix><Type>(g: CliGrammar; r: CliResolution;
  ## <extraParams>): <Type><suffix>``, which builds the value of
  ## ``cliShapedTypeDecls``' type for the commands ``r`` selected:
  ## ``fieldValues[id]`` is the expression (in ``g``, ``r`` and the extra
  ## parameters) each parameter's field gets. The builders of the branches
  ## must be declared first (innermost first).
  let typeName = ident(names.typeNames[command] & suffix)
  var forwarded = @[ident("g"), ident("r")]
  for p in extraParams:
    for k in 0 ..< p.len - 2:
      forwarded.add(ident($p[k]))
  var body = newStmtList()
  let kids = cliBranches(g, command)
  if kids.len > 0:
    let enumName = ident(cliCommandEnumName(names, command))
    var caseStmt = nnkCaseStmt.newTree(newCall(ident("cliSelectedChild"),
      ident("g"), ident("r"), newLit(command)))
    for kid in kids:
      let field = names.fieldOfChild[kid]
      caseStmt.add(nnkOfBranch.newTree(newLit(kid), newStmtList(
        newAssignment(ident("result"), nnkObjConstr.newTree(typeName,
          nnkExprColonExpr.newTree(ident("command"),
            newDotExpr(enumName, quoted(field))),
          nnkExprColonExpr.newTree(quoted(field),
            newCall(ident(procPrefix & names.typeNames[kid]), forwarded)))))))
    caseStmt.add(nnkElse.newTree(newStmtList(newCall(ident("raiseAssert"),
      newLit("clispec: no subcommand was selected")))))
    body.add(caseStmt)
  for id in cliObjectHolds(g, command):
    body.add(newAssignment(
      newDotExpr(ident("result"), quoted(g.params[id].name)),
      fieldValues[id]))
  var params = @[typeName,
    newIdentDefs(ident("g"), ident("CliGrammar")),
    newIdentDefs(ident("r"), ident("CliResolution"))]
  params.add(extraParams)
  result = newProc(ident(procPrefix & names.typeNames[command]),
    params = params, body = body)

proc cliShapedVisitorProc*(g: CliGrammar; names: CliGeneratedNames;
                           command: int; procPrefix: string;
                           extraParams: seq[NimNode];
                           fieldStmts: seq[NimNode];
                           raises: seq[NimNode]): NimNode =
  ## ``proc <procPrefix><Type>(g: CliGrammar; r: CliResolution;
  ## <extraParams>; target: var <Type>)``, which runs ``fieldStmts[id]``
  ## (statements in ``g``, ``r``, the extra parameters and ``target``,
  ## ``command``'s configuration object; an empty node for none) for every
  ## parameter field of the commands ``r`` selected, descending into the
  ## selected branch first. It raises what ``raises`` lists. The visitors
  ## of the branches must be declared first (innermost first).
  var forwarded = @[ident("g"), ident("r")]
  for p in extraParams:
    for k in 0 ..< p.len - 2:
      forwarded.add(ident($p[k]))
  var body = newStmtList()
  let kids = cliBranches(g, command)
  if kids.len > 0:
    var caseStmt = nnkCaseStmt.newTree(newDotExpr(ident("target"),
      ident("command")))
    for kid in kids:
      let field = names.fieldOfChild[kid]
      var args = forwarded
      args.add(newDotExpr(ident("target"), quoted(field)))
      caseStmt.add(nnkOfBranch.newTree(
        newDotExpr(ident(cliCommandEnumName(names, command)), quoted(field)),
        newStmtList(newCall(ident(procPrefix & names.typeNames[kid]), args))))
    body.add(caseStmt)
  for id in cliObjectHolds(g, command):
    if id < fieldStmts.len and fieldStmts[id].kind != nnkEmpty:
      body.add(fieldStmts[id])
  if body.len == 0:
    body.add(nnkDiscardStmt.newTree(newEmptyNode()))
  var params = @[newEmptyNode(),
    newIdentDefs(ident("g"), ident("CliGrammar")),
    newIdentDefs(ident("r"), ident("CliResolution"))]
  params.add(extraParams)
  params.add(newIdentDefs(ident("target"), nnkVarTy.newTree(
    ident(names.typeNames[command]))))
  result = newProc(ident(procPrefix & names.typeNames[command]),
    params = params, body = body)
  result.addPragma(nnkExprColonExpr.newTree(ident("raises"),
    nnkBracket.newTree(raises)))

proc typeDecls(ctx: GenContext; command: int): seq[NimNode] =
  ## The object type of ``command`` and, when it has subcommands, its
  ## discriminator enum.
  let g = ctx.g
  let cmd = g.commands[command]
  let name = ctx.names.typeNames[command]
  var fields = newNimNode(nnkRecList)
  var seen: seq[tuple[norm, what: string]] = @[]
  proc claim(field, what: string) =
    let norm = nimIdentNormalize(field)
    for s in seen:
      if s.norm == norm:
        problemAt("clispec: " & (if cmd.path.len == 0: "the root command"
          else: "command '" & cmd.path.join(" ") & "'") &
          ": the configuration object field '" & field & "' would hold " &
          "both " & s.what & " and " & what, cmd.sourceFile, cmd.sourceLine)
    seen.add((norm, what))
  for id in cliObjectHolds(g, command):
    let p = g.params[id]
    claim(p.name, "parameter '" & p.name & "'")
    fields.add(newIdentDefs(exportedName(p.name, ctx.exported),
      parseExpr(p.nimType)))
  let kids = cliBranches(g, command)
  if kids.len > 0:
    let enumName = cliCommandEnumName(ctx.names, command)
    var enumTy = nnkEnumTy.newTree(newEmptyNode())
    for kid in kids:
      enumTy.add(quoted(ctx.names.fieldOfChild[kid]))
    result.add(nnkTypeDef.newTree(
      nnkPragmaExpr.newTree(exportedName(enumName, ctx.exported),
        nnkPragma.newTree(ident("pure"))),
      newEmptyNode(), enumTy))
    claim("command", "the subcommand discriminator")
    var caseNode = nnkRecCase.newTree(newIdentDefs(
      exportedName("command", ctx.exported), ident(enumName)))
    for kid in kids:
      let field = ctx.names.fieldOfChild[kid]
      claim(field, "subcommand '" & field & "'")
      caseNode.add(nnkOfBranch.newTree(
        newDotExpr(ident(enumName), quoted(field)),
        nnkRecList.newTree(newIdentDefs(exportedName(field, ctx.exported),
          ident(ctx.names.typeNames[kid])))))
    fields.add(caseNode)
  result.add(nnkTypeDef.newTree(exportedName(name, ctx.exported),
    newEmptyNode(), nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(),
      fields)))

proc cliFieldBare*[P](decl: CliParam[P]; fieldType: NimNode): NimNode =
  ## A ``proc (): <fieldType> {.raises: [].}`` lambda giving the value of
  ## the parameter written bare: its ``optionalValue``, else the type's
  ## default. Generated code passes it to ``cliConvert``.
  let bareValue = if decl.optionalValue.isSet:
                    parseExpr(decl.optionalValue.code)
                  else: newCall(ident("default"), fieldType)
  result = newProc(params = [fieldType], body = newStmtList(bareValue),
    procType = nnkLambda)
  result.addPragma(nnkExprColonExpr.newTree(ident("raises"),
    nnkBracket.newTree()))

proc cliFieldAllowed*[P](decl: CliParam[P]; fieldType: NimNode):
    tuple[decl, sym: NimNode] =
  ## ``let <sym>: seq[cliElementType(<fieldType>)] = @[<values>]``: the
  ## parameter's closed value set (empty when it has none), which generated
  ## code passes to ``cliConvert``.
  let elemType = newCall(ident("cliElementType"), fieldType)
  var allowedLit = nnkBracket.newTree()
  for v in decl.values:
    allowedLit.add(parseExpr(v.code))
  result.sym = genSym(nskLet, "allowed")
  result.decl = newLetStmt(result.sym, newCall(ident("@"), allowedLit))
  result.decl[0][1] = nnkBracketExpr.newTree(ident("seq"), elemType)

proc fieldCode[P](ctx: GenContext; id: int; decls: seq[CliParam[P]];
                  target: NimNode): NimNode =
  ## Fills ``target`` (``result.<field>``) for parameter ``id`` from the
  ## decision phase 3 took.
  let g = ctx.g
  let decl = decls[id]
  let fieldType = parseExpr(g.params[id].nimType)
  let r = ident("r")
  let gram = ident("g")
  let d = genSym(nskLet, "decision")
  let bare = cliFieldBare(decl, fieldType)
  let (allowedDecl, allowed) = cliFieldAllowed(decl, fieldType)
  let sourceBranch = newStmtList(allowedDecl, newCall(ident("cliConvert"),
    gram, r, newLit(id), target, bare, allowed))
  var impliedBranch = newStmtList()
  for src, other in decls:
    for k, implication in other.implies:
      if k < g.params[src].implies.len and g.params[src].implies[k] == id:
        impliedBranch.add(newIfStmt((
          infix(infix(newDotExpr(d, ident("impliedBy")), "==", newLit(src)),
            "and", infix(newDotExpr(d, ident("implication")), "==",
              newLit(k))),
          newStmtList(newAssignment(target,
            parseExpr(implication.value.code))))))
  if impliedBranch.len == 0:
    impliedBranch.add(nnkDiscardStmt.newTree(newEmptyNode()))
  let defaultBranch = if decl.default.isSet:
                        newStmtList(newAssignment(target,
                          parseExpr(decl.default.code)))
                      else:
                        newStmtList(nnkDiscardStmt.newTree(newEmptyNode()))
  result = newStmtList(
    newLetStmt(d, nnkBracketExpr.newTree(newDotExpr(r, ident("decisions")),
      newLit(id))),
    nnkCaseStmt.newTree(newDotExpr(d, ident("kind")),
      nnkOfBranch.newTree(ident("cdkSource"), sourceBranch),
      nnkOfBranch.newTree(ident("cdkImplied"), impliedBranch),
      nnkOfBranch.newTree(ident("cdkDefault"), defaultBranch),
      nnkOfBranch.newTree(ident("cdkUnset"),
        newStmtList(nnkDiscardStmt.newTree(newEmptyNode())))))
  result = nnkBlockStmt.newTree(newEmptyNode(), result)

proc builderProc[P](ctx: GenContext; command: int;
                    decls: seq[CliParam[P]]): NimNode =
  ## ``proc cliBuild<Type>(g: CliGrammar; r: CliResolution): <Type>``.
  let g = ctx.g
  let typeName = ident(ctx.names.typeNames[command])
  var body = newStmtList()
  let kids = cliBranches(g, command)
  if kids.len > 0:
    let enumName = ident(cliCommandEnumName(ctx.names, command))
    var caseStmt = nnkCaseStmt.newTree(newCall(ident("cliSelectedChild"),
      ident("g"), ident("r"), newLit(command)))
    for kid in kids:
      let field = ctx.names.fieldOfChild[kid]
      caseStmt.add(nnkOfBranch.newTree(newLit(kid), newStmtList(
        newAssignment(ident("result"), nnkObjConstr.newTree(typeName,
          nnkExprColonExpr.newTree(ident("command"),
            newDotExpr(enumName, quoted(field))),
          nnkExprColonExpr.newTree(quoted(field),
            newCall(cliBuilderName(ctx.names, kid), ident("g"),
              ident("r"))))))))
    caseStmt.add(nnkElse.newTree(newStmtList(newCall(ident("raiseAssert"),
      newLit("clispec: no subcommand was selected")))))
    body.add(caseStmt)
  for id in cliObjectHolds(g, command):
    let target = newDotExpr(ident("result"), quoted(g.params[id].name))
    body.add(fieldCode(ctx, id, decls, target))
  result = newProc(cliBuilderName(ctx.names, command),
    params = [typeName,
      newIdentDefs(ident("g"), ident("CliGrammar")),
      newIdentDefs(ident("r"), ident("CliResolution"))],
    body = body)
  result.addPragma(nnkExprColonExpr.newTree(ident("raises"),
    nnkBracket.newTree(ident("CliUsageError"))))

proc grammarConstCode[P](ctx: GenContext; decls: seq[CliParam[P]]): NimNode =
  ## The grammar as a constant, with the facts that need the types filled
  ## in: whether each parameter is a switch or a list, and its closed value
  ## set's texts.
  let g = ctx.g
  let gv = genSym(nskVar, "grammar")
  var body = newStmtList(newVarStmt(gv, newLit(g)))
  for id, decl in decls:
    let fieldType = parseExpr(g.params[id].nimType)
    let param = nnkBracketExpr.newTree(newDotExpr(gv, ident("params")),
      newLit(id))
    body.add(newAssignment(newDotExpr(param, ident("isSwitch")),
      infix(fieldType, "is", ident("bool"))))
    body.add(newAssignment(newDotExpr(param, ident("isList")),
      infix(fieldType, "is", ident("seq"))))
    body.add(newAssignment(newDotExpr(param, ident("configType")),
      newCall(ident("cliConfigTypeOf"), fieldType)))
    for (field, e) in [("help", decl.helpExpr),
                      ("longHelp", decl.longHelpExpr)]:
      if e.isSet:
        let value = parseExpr(e.code)
        value.setLineInfo(e.sourceFile, e.sourceLine, e.sourceColumn)
        body.add(newAssignment(newDotExpr(param, ident(field)), value))
    let elemType = newCall(ident("cliElementType"), fieldType)
    if decl.values.len > 0:
      var lit = nnkBracket.newTree()
      for v in decl.values:
        lit.add(parseExpr(v.code))
      let vs = genSym(nskLet, "values")
      let letVs = newLetStmt(vs, newCall(ident("@"), lit))
      letVs[0][1] = nnkBracketExpr.newTree(ident("seq"), elemType)
      body.add(newStmtList(letVs, newAssignment(
        newDotExpr(param, ident("choices")),
        newCall(ident("cliChoiceTextsOf"), vs))))
    else:
      body.add(nnkWhenStmt.newTree(nnkElifBranch.newTree(
        newCall(ident("cliIsEnum"), elemType),
        newStmtList(newAssignment(newDotExpr(param, ident("choices")),
          newCall(ident("cliChoiceTexts"), elemType))))))
  body.add(gv)
  nnkConstSection.newTree(nnkConstDef.newTree(ctx.grammarConst, newEmptyNode(),
    nnkBlockStmt.newTree(newEmptyNode(), body)))

proc valueCheckProc[P](ctx: GenContext; decls: seq[CliParam[P]]): NimNode =
  ## ``proc cliValueCheckOf<Type>(id: int; text: string): string``: the
  ## ``CliValueCheck`` of every parameter that takes a value. Only the
  ## rules ``acceptsNextWord`` and ``valueErrorsBeforeHelp`` call it, so a
  ## description that uses neither gets one that accepts everything (and
  ## its types are not asked for anything new).
  let g = ctx.g
  let id = ident("id")
  let text = ident("text")
  var needed = cprValueErrorsBeforeHelp in g.parseRules
  for p in g.params:
    if p.acceptsNextWord:
      needed = true
  var caseStmt = nnkCaseStmt.newTree(id)
  for k, decl in decls:
    if g.params[k].counted or not needed:
      continue
    let fieldType = parseExpr(g.params[k].nimType)
    let (allowedDecl, allowed) = cliFieldAllowed(decl, fieldType)
    caseStmt.add(nnkOfBranch.newTree(newLit(k), newStmtList(allowedDecl,
      newAssignment(ident("result"), newCall(nnkBracketExpr.newTree(
        ident("cliCheckValue"), fieldType,
        newCall(ident("cliElementType"), fieldType.copyNimTree)),
        text, allowed)))))
  var body = newStmtList()
  if caseStmt.len > 1:
    caseStmt.add(nnkElse.newTree(newStmtList(nnkDiscardStmt.newTree(
      newEmptyNode()))))
    body.add(caseStmt)
  else:
    body.add(nnkDiscardStmt.newTree(id), nnkDiscardStmt.newTree(text))
  result = newProc(cliValueCheckName(ctx.names), params = [ident("string"),
    newIdentDefs(id, ident("int")), newIdentDefs(text, ident("string"))],
    body = body)
  result.addPragma(nnkExprColonExpr.newTree(ident("raises"),
    nnkBracket.newTree()))

proc cliProgramCode*[C, P](model: CliModel[C, P]; typeName, program: string;
                           exported: bool;
                           colorConfig = cliColorDefaults): NimNode =
  ## The code ``cliProgram`` generates, for a consumer macro that builds its
  ## own model (with an extension): the model's type checks, the
  ## configuration object types, the grammar constant and the ``load``,
  ## ``helpText``, ``helpJson``, ``printHelp``, ``printError``,
  ## ``cliGrammar`` and ``cliModel`` procedures for ``typeName``.
  ## ``program`` is the name help and errors use; ``colorConfig`` the
  ## program's colour configuration (``CliProgramArgs.colorConfig``), which
  ## ``load`` and the printers are compiled for. Place the result at the
  ## description's scope, which must import ``clispec``.
  var problems: seq[CliGrammarProblem] = @[]
  var decls: seq[CliParam[P]] = @[]
  let g = cliGrammarOf(model, program, problems, decls)
  for problem in problems:
    problemAt(problem.message, problem.sourceFile, problem.sourceLine)
  if model.configSchema.len > 0:
    # A program that loads configuration files: their top-level ``schema``
    # string and ``extensions`` table belong to the file itself, so no
    # parameter may use those keys. (A description that loads no file, an
    # external tool's for one, may name a parameter ``extensions``.)
    for p in decls:
      var keys = @[p.configKey]
      for k in p.sourceKeys:
        keys.add(k.spelling)
      for key in keys:
        if key.len > 0 and (key == "schema" or
            key.split('.')[0] == "extensions"):
          problemAt("clispec: parameter '" & p.name & "': configuration " &
            "key '" & key & "' is reserved: a configuration file's " &
            "`schema` string and its `extensions` table are not " &
            "parameters; give the parameter another `key`", p.sourceFile,
            p.sourceLine)
          break
  var ctx = GenContext(g: g, exported: exported,
    grammarConst: genSym(nskConst, typeName & "Grammar"),
    names: cliGeneratedNames(g, typeName))
  for k in 0 ..< g.commands.len:
    for kk in 0 ..< k:
      if cliHasObject(g, k) and cliHasObject(g, kk) and
          ctx.names.typeNames[k] == ctx.names.typeNames[kk]:
        problemAt("clispec: commands '" & g.commands[kk].path.join(" ") &
          "' and '" & g.commands[k].path.join(" ") & "' would both be " &
          "the type " & ctx.names.typeNames[k], g.commands[k].sourceFile,
          g.commands[k].sourceLine)
  result = newStmtList()
  for check in cliModelTypeChecks(model):
    result.add(check)
  var typeSection = nnkTypeSection.newTree()
  for k in 0 ..< g.commands.len:
    if cliHasObject(g, k):
      for decl in typeDecls(ctx, k):
        typeSection.add(decl)
  result.add(typeSection)
  result.add(grammarConstCode(ctx, decls))
  result.add(valueCheckProc(ctx, decls))
  # Builders, innermost first so each one's callees are declared.
  for k in countdown(g.commands.high, 0):
    if cliHasObject(g, k):
      result.add(builderProc(ctx, k, decls))
  # The completers, by parameter id: built on demand (a completer may be a
  # call that returns one), so a program pays for them only when it is
  # asked to complete.
  let completersName = cliCompletersName(ctx.names)
  var completersBody = newStmtList(newAssignment(ident("result"),
    newCall(nnkBracketExpr.newTree(ident("newSeq"), ident("CliCompleter")),
      newLit(g.params.len))))
  for id, decl in decls:
    if decl.complete.isSet:
      let e = genSym(nskLet, "e")
      completersBody.add(nnkTryStmt.newTree(
        newStmtList(newAssignment(nnkBracketExpr.newTree(ident("result"),
          newLit(id)), parseExpr(decl.complete.code))),
        nnkExceptBranch.newTree(infix(ident("CatchableError"), "as", e),
          newStmtList(nnkDiscardStmt.newTree(e)))))
  result.add(newProc(completersName,
    params = [nnkBracketExpr.newTree(ident("seq"), ident("CliCompleter"))],
    body = completersBody))
  let T = ident(typeName)
  let gc = ctx.grammarConst
  let rootBuilder = cliBuilderName(ctx.names, 0)
  let loadName = exportedName("load", exported)
  let helpTextName = exportedName("helpText", exported)
  let helpJsonName = exportedName("helpJson", exported)
  let optionsTableName = exportedName("optionsTable", exported)
  let grammarName = exportedName("cliGrammar", exported)
  let prog = newLit(program)
  let modelName = exportedName("cliModel", exported)
  let completeName = exportedName("complete", exported)
  let completionReplyName = exportedName("completionReply", exported)
  let completionScriptName = exportedName("completionScript", exported)
  let modelConst = genSym(nskConst, typeName & "Model")
  result.add(nnkConstSection.newTree(nnkConstDef.newTree(modelConst,
    newEmptyNode(), cliModelValue(model))))
  let valueCheck = cliValueCheckName(ctx.names)
  let colorConst = cliColorConfigName(ctx.names)
  let printHelpName = exportedName("printHelp", exported)
  let printErrorName = exportedName("printError", exported)
  result.add(nnkConstSection.newTree(nnkConstDef.newTree(colorConst,
    newEmptyNode(), newLit(colorConfig))))
  result.add quote do:
    proc `grammarName`(t: typedesc[`T`]): CliGrammar =
      ## The command line's grammar.
      `gc`

    proc `modelName`(t: typedesc[`T`]): auto =
      ## The model the description was parsed into.
      `modelConst`

    proc `loadName`(t: typedesc[`T`]; argv: openArray[string];
                    options = CliOptions()): `T` {.
        raises: [CliUsageError, CliHelpRequest].} =
      ## Parses ``argv`` (without the program name) into a configuration
      ## object. Raises ``CliUsageError`` for a command line it rejects and
      ## ``CliHelpRequest`` when help is asked for (and its subtypes
      ## ``CliCompletionRequest`` when a completion script asks and
      ## ``CliVersionRequest`` when the version is asked for).
      let opts = cliWithValueCheck(options, `valueCheck`)
      if cliIsCompletionRequest(argv, opts):
        cliCompletionCheck(`gc`, `completersName`(), argv, opts)
      var r = cliResolve(`gc`, argv, opts, `colorConst`)
      `rootBuilder`(`gc`, r)

    proc `loadName`(t: typedesc[`T`]; options = CliOptions()): `T` {.
        raises: [CliUsageError, CliHelpRequest].} =
      ## Parses the process's own arguments.
      `loadName`(t, cliCommandLineParams(), options)

    proc `printHelpName`(t: typedesc[`T`]; e: ref CliHelpRequest;
                         stream = stdout) {.raises: [IOError].} =
      ## Writes a help request ``load`` raised to ``stream``
      ## (``cliPrintHelp``), styled under the program's own colour
      ## configuration.
      cliPrintHelp(e, stream, `colorConst`)

    proc `printErrorName`(t: typedesc[`T`]; e: ref CliUsageError;
                          stream = stderr) {.raises: [IOError].} =
      ## Writes a usage error ``load`` raised to ``stream``
      ## (``cliPrintError``), styled under the program's own colour
      ## configuration.
      cliPrintError(e, stream, `colorConst`)

    proc `helpTextName`(t: typedesc[`T`]; path: openArray[string] = [];
                        program = `prog`; layout = cliDefaultHelpLayout;
                        long = false; styled = false;
                        all = false): string {.
        raises: [CliUsageError].} =
      ## The human-readable help of the command reached by the subcommand
      ## words ``path``, laid out by ``layout``: the short page (``-h``),
      ## or with ``long`` the long one (``--help``); ``all`` lists the
      ## ``secondary`` subcommands too (``--help-all`` is ``long`` and
      ## ``all``); ``styled`` adds the escape sequences of the
      ## ``portable16`` palette of ``clispec/styles`` (no detection).
      cliHelpText(`gc`, cliHelpCommand(`gc`, path, program), program,
        layout, long, styled, all)

    proc `helpTextName`(t: typedesc[`T`]; path: openArray[string];
                        style: CliStyle; program = `prog`;
                        layout = cliDefaultHelpLayout; long = false;
                        all = false): string {.
        raises: [CliUsageError].} =
      ## The same page rendered with ``style`` (``cliColorStyle``, or a
      ## ``CliStyle`` with a palette of ``clispec/styles``).
      cliHelpText(`gc`, cliHelpCommand(`gc`, path, program), program,
        style, layout, long, all)

    proc `optionsTableName`(t: typedesc[`T`]; path: openArray[string] = [];
                            layout = cliDefaultHelpLayout; group = "";
                            long = false; styled = false): string {.
        raises: [CliUsageError].} =
      ## The rows of the options table of the command reached by the
      ## subcommand words ``path`` (``cliOptionsTable``).
      cliOptionsTable(`gc`, cliHelpCommand(`gc`, path, `prog`), layout,
        group, long, styled)

    proc `completeName`(t: typedesc[`T`]; words: openArray[string];
                        cursor = -1; options = CliOptions()):
        seq[CliCompletion] =
      ## The completion candidates for ``words[cursor]`` (the last word
      ## when ``cursor`` is -1; an empty word when it is ``words.len``),
      ## ``words`` being the command line without the program name.
      let at = if cursor < 0: max(0, words.len - 1) else: cursor
      cliComplete(`gc`, `completersName`(), words, at,
        cliWithValueCheck(options, `valueCheck`))

    proc `completionReplyName`(t: typedesc[`T`]; args: openArray[string];
                               options = CliOptions()): string =
      ## The answer to ``<program> __complete <args...>`` (``args`` starts
      ## with the shell's name), which ``load`` also gives through
      ## ``CliCompletionRequest``.
      cliCompletionReply(`gc`, `completersName`(), args,
        cliWithValueCheck(options, `valueCheck`))

    proc `completionScriptName`(t: typedesc[`T`]; shell: CliShell;
                                program = `prog`; command = "";
                                options = CliOptions()): string =
      ## The completion script of ``shell`` for this program (see
      ## ``clispec/completion_scripts``).
      cliCompletionScript(shell, program, command, options)

    proc `helpJsonName`(t: typedesc[`T`]; path: openArray[string] = [];
                        program = `prog`): string {.
        raises: [CliUsageError].} =
      ## The machine-readable help (``clispec-help/1``) of the command
      ## reached by the subcommand words ``path``.
      cliHelpJson(`gc`, cliHelpCommand(`gc`, path, program), program)

type
  CliProgramArgs* = object
    ## The arguments of a ``cliProgram``-style macro call:
    ## ``(<Type>[, "<program name>"][, exported = true][, <colour
    ## parameters>]): <description>``.
    typeName*: string
    program*: string
      ## The program's name in help and errors (the type's name when not
      ## given).
    exported*: bool
    colorConfig*: CliColorConfig
      ## The program's colour configuration: ``cliColorDefaults`` (the
      ## defines) with the colour parameters written in the call
      ## (``colors = never``, ``colorDepth = 24``, ...; see
      ## ``cliColorParameter``) applied over it.
    body*: NimNode
      ## The ``cli:`` description.

proc cliProgramArgs*(args: NimNode; macroName = "cliProgram"):
    CliProgramArgs =
  ## Reads the arguments of a macro written like ``cliProgram`` (``args``
  ## is its ``varargs[untyped]``), for a library whose own macro takes the
  ## same form. Errors name ``macroName``.
  if args.len < 2 or args[^1].kind != nnkStmtList:
    error("clispec: " & macroName & " is written " & macroName &
      "(<Type>[, \"<name>\"][, exported = true][, <colour parameters>]): " &
      "<description>", args)
  var head = args[0]
  var positional: seq[NimNode] = @[]
  result.colorConfig = cliColorDefaults
  for i in 1 ..< args.len - 1:
    let arg = args[i]
    if cliColorParameter(result.colorConfig, arg):
      continue
    if arg.kind == nnkExprEqExpr and arg[0].eqIdent("exported"):
      if arg[1].eqIdent("true"): result.exported = true
      elif arg[1].eqIdent("false"): result.exported = false
      else:
        error("clispec: exported must be true or false, got: " &
          arg[1].repr, arg[1])
    else:
      positional.add(arg)
  if head.kind == nnkPostfix and head[0].eqIdent("*"):
    result.exported = true
    head = head[1]
  if head.kind notin {nnkIdent, nnkSym}:
    error("clispec: " & macroName & " needs a type name, got: " & head.repr,
      head)
  result.typeName = $head
  result.program = result.typeName
  if positional.len == 1:
    result.program = cliStrLit(positional[0], "program name")
  elif positional.len > 1:
    error("clispec: " & macroName & " takes a type name, an optional " &
      "program name, `exported = true`, colour parameters (" &
      cliColorParameters.join(", ") & ") and a body", args)
  result.body = args[^1]

macro cliProgram*(args: varargs[untyped]): untyped =
  ## Generates a program's configuration object, parser and help from a
  ## ``cli:`` body (see the module documentation):
  ##
  ## .. code-block:: nim
  ##   cliProgram(Tool, "tool"):   # or: cliProgram Tool:
  ##     flag jobs is int, default = 4
  ##
  ## The second argument is the program's name in help and errors; it
  ## defaults to the type's name. ``exported = true`` (before the body)
  ## exports the generated types and procedures, so the description can
  ## live in a module of its own:
  ## ``cliProgram(Tool, "tool", exported = true):``. The colour parameters
  ## (``colors = never``, ``colorDepth = 24``, ...; see "Colour parameters"
  ## in the module documentation) fix the program's colour configuration.
  let a = cliProgramArgs(args)
  let model = parseCliModel[NoCliExtension, NoCliExtension](a.body,
    NoCliExtension())
  cliProgramCode(model, a.typeName, a.program, a.exported, a.colorConfig)
