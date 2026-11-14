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
## The value its sources supply (the command line, and, when the program
## passes ``CliSources``, its configuration layers and the environment,
## merged as ``clispec/parser`` and ``clispec/sources`` describe), else the
## value an ``implies`` of a parameter some source supplied sets, else its
## ``default``, else the type's zero value (``none`` for an ``Option``). A ``required`` parameter that gets no value is a usage
## error. A ``counted`` parameter holds the number of occurrences; a list
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
##   it rejects and ``CliHelpRequest`` when help is asked for; it never ends
##   the process.
## * ``Tool.helpText(path)`` and ``Tool.helpJson(path)`` render the help of
##   the command reached by the subcommand words ``path`` (see
##   ``clispec/help``); an unknown word is a ``CliUsageError``.
## * ``Tool.load(argv, sources, options)`` (and ``Tool.load(sources,
##   options)`` for the process's arguments) also reads the configuration
##   layers and the environment of a ``CliSources``; it raises
##   ``CliConfigError`` for a file that does not fit the program's schema.
## * ``Tool.loadWithOrigins(argv, sources, options)`` returns
##   ``tuple[config: Tool, origins: ToolOrigins]``: the origin object has the
##   configuration object's shape (``ToolOrigins``, ``ToolBuildOrigins``,
##   the same ``command`` discriminator) with a ``CliOrigin`` per field.
## * ``Tool.configSchema`` is the configuration-file schema, and
##   ``Tool.configSchema(source)`` the same with its keys spelt as the named
##   file source ``source`` spells them.
## * ``Tool.cliGrammar`` is the grammar and ``Tool.cliModel`` the model, both
##   constants.
##
## A consumer whose model carries an extension generates the same code from
## its own macro with ``cliProgramCode``.

import std/[macros, os, strutils]

import ./[model, dsl, grammar, parser, help, sources, origins]

export parser, help, grammar, sources, origins

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
  ## (unknown subcommand) naming the command that does not know the word.
  result = 0
  var walked: seq[string] = @[]
  for word in path:
    let next = cliChildNamed(g, result, word)
    if next < 0:
      raise newCliUsageError(cekUnknownSubcommand, program, walked, -1, word,
        expected = cliSubcommandWords(g, result).join(", "))
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
  GenContext = object
    g: CliGrammar
    typeNames: seq[string]
    fieldOfChild: seq[string]
    exported: bool
    grammarConst: NimNode

proc problemAt(message, file: string; line: int) =
  let n = newEmptyNode()
  n.setLineInfo(file, line, 0)
  error(message, n)

proc objectHolds(g: CliGrammar; command: int): seq[int] =
  ## The parameter ids whose fields the object of ``command`` holds.
  result = g.commands[command].ownParams
  let call = g.commands[command].callChild
  if call >= 0 and g.commands[command].children.len == 0:
    for id in g.commands[call].ownParams:
      result.add(id)

proc hasObject(g: CliGrammar; command: int): bool =
  ## A call: has an object of its own only as a branch of a command with
  ## subcommands.
  not g.commands[command].isCall or
    g.commands[g.commands[command].parent].children.len > 0

proc branches(g: CliGrammar; command: int): seq[int] =
  result = g.commands[command].children
  if g.commands[command].children.len > 0 and
      g.commands[command].callChild >= 0:
    result.add(g.commands[command].callChild)

func originsName(ctx: GenContext; command: int): string =
  ctx.typeNames[command] & "Origins"

proc typeDecls(ctx: GenContext; command: int; origins = false): seq[NimNode] =
  ## The object type of ``command`` and, when it has subcommands, its
  ## discriminator enum. With ``origins``, the origin object type of the
  ## same shape instead: a ``CliOrigin`` per parameter, the same
  ## discriminator (the enum is declared once, with the configuration
  ## object) and each branch holding the subcommand's origin object.
  let g = ctx.g
  let cmd = g.commands[command]
  let name = if origins: originsName(ctx, command)
             else: ctx.typeNames[command]
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
  for id in objectHolds(g, command):
    let p = g.params[id]
    if not origins:
      claim(p.name, "parameter '" & p.name & "'")
    fields.add(newIdentDefs(exportedName(p.name, ctx.exported),
      (if origins: ident("CliOrigin") else: parseExpr(p.nimType))))
  let kids = branches(g, command)
  if kids.len > 0:
    let enumName = ctx.typeNames[command] & "Command"
    if not origins:
      var enumTy = nnkEnumTy.newTree(newEmptyNode())
      for kid in kids:
        enumTy.add(quoted(ctx.fieldOfChild[kid]))
      result.add(nnkTypeDef.newTree(
        nnkPragmaExpr.newTree(exportedName(enumName, ctx.exported),
          nnkPragma.newTree(ident("pure"))),
        newEmptyNode(), enumTy))
      claim("command", "the subcommand discriminator")
    var caseNode = nnkRecCase.newTree(newIdentDefs(
      exportedName("command", ctx.exported), ident(enumName)))
    for kid in kids:
      let field = ctx.fieldOfChild[kid]
      if not origins:
        claim(field, "subcommand '" & field & "'")
      caseNode.add(nnkOfBranch.newTree(
        newDotExpr(ident(enumName), quoted(field)),
        nnkRecList.newTree(newIdentDefs(exportedName(field, ctx.exported),
          ident(if origins: originsName(ctx, kid)
                else: ctx.typeNames[kid])))))
    fields.add(caseNode)
  result.add(nnkTypeDef.newTree(exportedName(name, ctx.exported),
    newEmptyNode(), nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(),
      fields)))

proc fieldCode[P](ctx: GenContext; id: int; decls: seq[CliParam[P]];
                  target: NimNode): NimNode =
  ## Fills ``target`` (``result.<field>``) for parameter ``id`` from the
  ## decision phase 3 took.
  let g = ctx.g
  let p = g.params[id]
  let decl = decls[id]
  let fieldType = parseExpr(p.nimType)
  let r = ident("r")
  let gram = ident("g")
  let d = genSym(nskLet, "decision")
  # The bare value of an optional-value flag.
  let bareValue = if decl.optionalValue.isSet: parseExpr(decl.optionalValue.code)
                  else: newCall(ident("default"), fieldType)
  let bare = newProc(params = [fieldType], body = newStmtList(bareValue),
    procType = nnkLambda)
  bare.addPragma(nnkExprColonExpr.newTree(ident("raises"), nnkBracket.newTree()))
  let elemType = newCall(ident("cliElementType"), fieldType)
  var allowedLit = nnkBracket.newTree()
  for v in decl.values:
    allowedLit.add(parseExpr(v.code))
  let allowed = genSym(nskLet, "allowed")
  let allowedDecl = newLetStmt(allowed, newCall(ident("@"), allowedLit))
  allowedDecl[0][1] = nnkBracketExpr.newTree(ident("seq"), elemType)
  let convert = newCall(ident("cliConvert"), gram, r, newLit(id), target,
    bare, allowed)
  var sourceBranch = newStmtList(allowedDecl)
  if decl.merge == cmrCombine:
    # The combine proc receives one value per source, unless a binding
    # layer enforces the value.
    let inputs = genSym(nskLet, "inputs")
    let err = genSym(nskLet, "e")
    let combineCall = newCall(parseExpr(decl.combine.code), inputs)
    sourceBranch.add(newIfStmt((
      newCall(ident("cliCombines"), gram, r, newLit(id)),
      newStmtList(
        newLetStmt(inputs, newCall(ident("cliCombineInputs"), gram, r,
          newLit(id), bare, allowed)),
        nnkTryStmt.newTree(
          newStmtList(newAssignment(target, combineCall)),
          nnkExceptBranch.newTree(
            infix(ident("CatchableError"), "as", err),
            newStmtList(newCall(ident("cliCombineFailed"), gram, r,
              newLit(id), newDotExpr(err, ident("msg"))))))))).add(
      nnkElse.newTree(newStmtList(convert))))
  else:
    sourceBranch.add(convert)
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

proc builderName(ctx: GenContext; command: int): NimNode =
  ident("cliBuild" & ctx.typeNames[command])

proc originsBuilderName(ctx: GenContext; command: int): NimNode =
  ident("cliOriginsOf" & ctx.typeNames[command])

proc originsBuilderProc(ctx: GenContext; command: int): NimNode =
  ## ``proc cliOriginsOf<Type>(g: CliGrammar; r: CliResolution):
  ## <Type>Origins``: the origin object, copied from ``r.origins``.
  let g = ctx.g
  let typeName = ident(originsName(ctx, command))
  var body = newStmtList()
  let kids = branches(g, command)
  if kids.len > 0:
    let enumName = ident(ctx.typeNames[command] & "Command")
    var caseStmt = nnkCaseStmt.newTree(newCall(ident("cliSelectedChild"),
      ident("g"), ident("r"), newLit(command)))
    for kid in kids:
      let field = ctx.fieldOfChild[kid]
      caseStmt.add(nnkOfBranch.newTree(newLit(kid), newStmtList(
        newAssignment(ident("result"), nnkObjConstr.newTree(typeName,
          nnkExprColonExpr.newTree(ident("command"),
            newDotExpr(enumName, quoted(field))),
          nnkExprColonExpr.newTree(quoted(field),
            newCall(originsBuilderName(ctx, kid), ident("g"),
              ident("r"))))))))
    caseStmt.add(nnkElse.newTree(newStmtList(newCall(ident("raiseAssert"),
      newLit("clispec: no subcommand was selected")))))
    body.add(caseStmt)
  for id in objectHolds(g, command):
    body.add(newAssignment(
      newDotExpr(ident("result"), quoted(g.params[id].name)),
      nnkBracketExpr.newTree(newDotExpr(ident("r"), ident("origins")),
        newLit(id))))
  result = newProc(originsBuilderName(ctx, command),
    params = [typeName,
      newIdentDefs(ident("g"), ident("CliGrammar")),
      newIdentDefs(ident("r"), ident("CliResolution"))],
    body = body)
  result.addPragma(nnkExprColonExpr.newTree(ident("raises"),
    nnkBracket.newTree()))

proc builderProc[P](ctx: GenContext; command: int;
                    decls: seq[CliParam[P]]): NimNode =
  ## ``proc cliBuild<Type>(g: CliGrammar; r: CliResolution): <Type>``.
  let g = ctx.g
  let typeName = ident(ctx.typeNames[command])
  var body = newStmtList()
  let kids = branches(g, command)
  if kids.len > 0:
    let enumName = ident(ctx.typeNames[command] & "Command")
    var caseStmt = nnkCaseStmt.newTree(newCall(ident("cliSelectedChild"),
      ident("g"), ident("r"), newLit(command)))
    for kid in kids:
      let field = ctx.fieldOfChild[kid]
      caseStmt.add(nnkOfBranch.newTree(newLit(kid), newStmtList(
        newAssignment(ident("result"), nnkObjConstr.newTree(typeName,
          nnkExprColonExpr.newTree(ident("command"),
            newDotExpr(enumName, quoted(field))),
          nnkExprColonExpr.newTree(quoted(field),
            newCall(builderName(ctx, kid), ident("g"), ident("r"))))))))
    caseStmt.add(nnkElse.newTree(newStmtList(newCall(ident("raiseAssert"),
      newLit("clispec: no subcommand was selected")))))
    body.add(caseStmt)
  for id in objectHolds(g, command):
    let target = newDotExpr(ident("result"), quoted(g.params[id].name))
    body.add(fieldCode(ctx, id, decls, target))
  result = newProc(builderName(ctx, command),
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

proc cliProgramCode*[C, P](model: CliModel[C, P]; typeName, program: string;
                           exported: bool): NimNode =
  ## The code ``cliProgram`` generates, for a consumer macro that builds its
  ## own model (with an extension): the model's type checks, the
  ## configuration object types, the grammar constant and the ``load``,
  ## ``helpText``, ``helpJson``, ``cliGrammar`` and ``cliModel`` procedures for
  ## ``typeName``. ``program`` is the name help and errors use. Place the
  ## result at the description's scope, which must import ``clispec``.
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
    grammarConst: genSym(nskConst, typeName & "Grammar"))
  ctx.typeNames = newSeq[string](g.commands.len)
  ctx.fieldOfChild = newSeq[string](g.commands.len)
  for k, cmd in g.commands:
    if k == 0:
      ctx.typeNames[k] = typeName
    elif cmd.isCall:
      ctx.typeNames[k] = ctx.typeNames[cmd.parent] & "Call"
      ctx.fieldOfChild[k] = "call"
    else:
      ctx.typeNames[k] = ctx.typeNames[cmd.parent] & camelWord(cmd.name, true)
      ctx.fieldOfChild[k] = camelWord(cmd.name, false)
  for k in 0 ..< g.commands.len:
    for kk in 0 ..< k:
      if hasObject(g, k) and hasObject(g, kk) and
          ctx.typeNames[k] == ctx.typeNames[kk]:
        problemAt("clispec: commands '" & g.commands[kk].path.join(" ") &
          "' and '" & g.commands[k].path.join(" ") & "' would both be " &
          "the type " & ctx.typeNames[k], g.commands[k].sourceFile,
          g.commands[k].sourceLine)
  # A command's origin object type must not be another command's type
  # (``subcmd "origins"`` of ``Tool`` would be ``ToolOrigins``).
  for k in 0 ..< g.commands.len:
    for kk in 0 ..< g.commands.len:
      if hasObject(g, k) and hasObject(g, kk) and
          originsName(ctx, k) == ctx.typeNames[kk]:
        problemAt("clispec: the origin object of " &
          (if k == 0: "the root command"
           else: "command '" & g.commands[k].path.join(" ") & "'") &
          " would be the type " & originsName(ctx, k) & ", which is " &
          "already the configuration object of command '" &
          g.commands[kk].path.join(" ") & "'", g.commands[kk].sourceFile,
          g.commands[kk].sourceLine)
  result = newStmtList()
  for check in cliModelTypeChecks(model):
    result.add(check)
  var typeSection = nnkTypeSection.newTree()
  for k in 0 ..< g.commands.len:
    if hasObject(g, k):
      for decl in typeDecls(ctx, k):
        typeSection.add(decl)
      for decl in typeDecls(ctx, k, origins = true):
        typeSection.add(decl)
  result.add(typeSection)
  result.add(grammarConstCode(ctx, decls))
  # Builders, innermost first so each one's callees are declared.
  for k in countdown(g.commands.high, 0):
    if hasObject(g, k):
      result.add(builderProc(ctx, k, decls))
      result.add(originsBuilderProc(ctx, k))
  let T = ident(typeName)
  let O = ident(originsName(ctx, 0))
  let gc = ctx.grammarConst
  let rootBuilder = builderName(ctx, 0)
  let rootOrigins = originsBuilderName(ctx, 0)
  let loadWithOriginsName = exportedName("loadWithOrigins", exported)
  let configSchemaName = exportedName("configSchema", exported)
  let loadName = exportedName("load", exported)
  let helpTextName = exportedName("helpText", exported)
  let helpJsonName = exportedName("helpJson", exported)
  let grammarName = exportedName("cliGrammar", exported)
  let prog = newLit(program)
  let modelName = exportedName("cliModel", exported)
  let modelConst = genSym(nskConst, typeName & "Model")
  result.add(nnkConstSection.newTree(nnkConstDef.newTree(modelConst,
    newEmptyNode(), newLit(model))))
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
      ## ``CliHelpRequest`` when help is asked for.
      var r = cliResolve(`gc`, argv, options)
      `rootBuilder`(`gc`, r)

    proc `loadName`(t: typedesc[`T`]; options = CliOptions()): `T` {.
        raises: [CliUsageError, CliHelpRequest].} =
      ## Parses the process's own arguments.
      `loadName`(t, cliCommandLineParams(), options)

    proc `loadName`(t: typedesc[`T`]; argv: openArray[string];
                    sources: CliSources; options = CliOptions()): `T` {.
        raises: [CliUsageError, CliHelpRequest, CliConfigError].} =
      ## Fills a configuration object from the configuration layers and the
      ## environment of ``sources`` and from ``argv``, merged as each
      ## parameter declares. Raises ``CliConfigError`` for a configuration
      ## file that does not fit the program's schema.
      var r = cliResolve(`gc`, argv, sources, options)
      `rootBuilder`(`gc`, r)

    proc `loadName`(t: typedesc[`T`]; sources: CliSources;
                    options = CliOptions()): `T` {.
        raises: [CliUsageError, CliHelpRequest, CliConfigError].} =
      ## ``load`` over ``sources`` and the process's own arguments.
      `loadName`(t, cliCommandLineParams(), sources, options)

    proc `loadWithOriginsName`(t: typedesc[`T`]; argv: openArray[string];
                               sources = CliSources();
                               options = CliOptions()):
        tuple[config: `T`, origins: `O`] {.
        raises: [CliUsageError, CliHelpRequest, CliConfigError].} =
      ## ``load``, and the origin object: for every field, where its value
      ## came from and every other value that was considered.
      var r = cliResolve(`gc`, argv, sources, options)
      (`rootBuilder`(`gc`, r), `rootOrigins`(`gc`, r))

    proc `configSchemaName`(t: typedesc[`T`]): CliConfigSchema =
      ## The schema of the program's configuration files: the identifier
      ## they declare and every valid key with its type, spelt as the
      ## ``file`` source spells it.
      cliConfigSchemaOf(`gc`)

    proc `configSchemaName`(t: typedesc[`T`]; source: string):
        CliConfigSchema =
      ## The schema with its keys spelt as the file source ``source`` (a
      ## named source the description declares) spells them.
      cliConfigSchemaOf(`gc`, source)

    proc `helpTextName`(t: typedesc[`T`]; path: openArray[string] = [];
                        program = `prog`): string {.
        raises: [CliUsageError].} =
      ## The human-readable help of the command reached by the subcommand
      ## words ``path``.
      cliHelpText(`gc`, cliHelpCommand(`gc`, path, program), program)

    proc `helpJsonName`(t: typedesc[`T`]; path: openArray[string] = [];
                        program = `prog`): string {.
        raises: [CliUsageError].} =
      ## The machine-readable help (``clispec-help/1``) of the command
      ## reached by the subcommand words ``path``.
      cliHelpJson(`gc`, cliHelpCommand(`gc`, path, program), program)

macro cliProgram*(args: varargs[untyped]): untyped =
  ## Generates a program's configuration object, parser and help from a
  ## ``cli:`` body (see the module documentation):
  ##
  ## .. code-block:: nim
  ##   cliProgram(Tool, "tool"):   # or: cliProgram Tool:
  ##     flag jobs is int, default = 4
  ##
  ## The second argument is the program's name in help and errors; it
  ## defaults to the type's name. ``exported = true`` (last, before the
  ## body) exports the generated types and procedures, so the description
  ## can live in a module of its own:
  ## ``cliProgram(Tool, "tool", exported = true):``.
  if args.len < 2 or args[^1].kind != nnkStmtList:
    error("clispec: cliProgram is written cliProgram(<Type>[, \"<name>\"]" &
      "[, exported = true]): <description>", args)
  var head = args[0]
  var exported = false
  var positional: seq[NimNode] = @[]
  for i in 1 ..< args.len - 1:
    let arg = args[i]
    if arg.kind == nnkExprEqExpr and arg[0].eqIdent("exported"):
      if arg[1].eqIdent("true"): exported = true
      elif arg[1].eqIdent("false"): exported = false
      else:
        error("clispec: exported must be true or false, got: " &
          arg[1].repr, arg[1])
    else:
      positional.add(arg)
  if head.kind == nnkPostfix and head[0].eqIdent("*"):
    exported = true
    head = head[1]
  if head.kind notin {nnkIdent, nnkSym}:
    error("clispec: cliProgram needs a type name, got: " & head.repr, head)
  let typeName = $head
  var program = typeName
  if positional.len == 1:
    program = cliStrLit(positional[0], "program name")
  elif positional.len > 1:
    error("clispec: cliProgram takes a type name, an optional program " &
      "name, `exported = true` and a body", args)
  let model = parseCliModel[NoCliExtension, NoCliExtension](args[^1],
    NoCliExtension())
  cliProgramCode(model, typeName, program, exported)
