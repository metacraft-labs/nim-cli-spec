## The ``cli:`` description language, parsed at compile time into the typed
## model of ``clispec/model``.
##
## Grammar
## =======
##
## A ``cli:`` body is a list of statements:
##
## .. code-block:: nim
##   cli:
##     flag config is string, alias = "--config", format = equals
##     call:
##       boolFlag verbose is bool, alias = "-v"
##       pos sources is seq[string], repeated = true
##     subcmd "link":
##       flag output is string, alias = "-o", required = true
##       pos objects is seq[string], position = 1
##
## * ``pos <name> is <Type>`` declares a positional parameter,
##   ``flag <name> is <Type>`` a flag that takes a value, and
##   ``boolFlag <name> is bool`` (or plain ``boolFlag <name>``) a switch.
##   ``pos`` / ``flag`` also accept the older call spelling,
##   ``pos(<name>, <Type>, ...)``.
## * Named arguments follow the head. A flag accepts ``alias = "<spelling>"``,
##   ``required = true|false``, ``format = separate|concat|equals``,
##   ``placement = after|before`` and ``repeated = true|false``. A positional
##   accepts ``position = <int>`` and ``repeated = true|false``.
## * ``call:`` opens the anonymous command, ``subcmd "<name>":`` a named one;
##   both nest. A nested scope sees the parameters its enclosing scopes
##   declared before it opened.
## * A flag declared directly under ``cli:`` is placed before the subcommand
##   word (``placement = before``); everywhere else the default is after it.
##
## Anything else — an unknown statement, or a named argument the parameter
## kind does not take — is offered to the consumer's extension (below) and
## ignored when no extension claims it.
##
## Extensions
## ==========
##
## The parser is generic over the two extension types of the model,
## ``C`` (commands) and ``P`` (parameters), and calls two hooks through
## ``mixin``, so it resolves them where the consumer instantiates it:
##
## .. code-block:: nim
##   proc parseCliParamExtension(ext: var P; kind: CliParamKind;
##                               arg: NimNode): bool
##   proc parseCliCommandExtension(cmd: var CliCommand[C, P]; stmt: NimNode;
##                                 scope: CliScope): bool
##
## ``parseCliParamExtension`` receives each ``name = value`` argument
## (an ``nnkExprEqExpr``) of a parameter declaration that the library does
## not consume itself. ``parseCliCommandExtension`` receives each statement
## of a scope that is not a parameter, ``call:`` or ``subcmd``, in source
## order, together with the command as parsed so far (so it can check names
## against the parameters already visible). Both return ``true`` when they
## consumed their input. They run inside the consumer's macro, so they may
## call ``error`` to reject a declaration with a source location.
##
## Hooks are plain overloads rather than registered callbacks because
## compile-time code cannot hold a registry across macro invocations, and an
## overload keyed on the extension type is resolved statically: a consumer
## that forgets one gets a compile error naming the hook, not a silent
## no-op. ``NoCliExtension`` has both hooks, returning ``false``.

import std/[macros, strutils, tables]

import ./model

export model

type
  CliScope* = object
    ## What a command-extension hook is told about the scope a statement
    ## appears in.
    isRoot*: bool
      ## The statement sits directly under ``cli:``.
    path*: seq[string]
      ## The scope's lexical path (see ``CliCommand.path``).
    wholeBody*: NimNode
      ## The entire ``cli:`` body, for diagnostics that need to look beyond
      ## the current scope (for example to tell a name declared in a sibling
      ## scope from one declared nowhere).

  CliParamDecl* = enum
    ## The three declaration heads.
    cpdPos
    cpdFlag
    cpdBoolFlag

  CliParamHead* = object
    ## The head of a parameter declaration, read leniently: see
    ## ``parseCliParamHead``.
    matched*: bool
    decl*: CliParamDecl
    name*: string
    typed*: bool
      ## The ``<name> is <Type>`` form was used.
    nimType*: string
      ## The type of the ``is`` form; empty otherwise.

  CliParamGroups* = Table[string, seq[NimNode]]
    ## Parameter groups by normalised name: see ``collectCliParamGroup``.

# ---------------------------------------------------------------------------
# AST helpers. Exported with a ``cli`` prefix for extension hooks, which
# read the same shapes.
# ---------------------------------------------------------------------------

proc cliIdentText*(node: NimNode): string =
  ## The spelling of an identifier node. Nim parses the word ``out`` in a
  ## position that could start an ``out T`` type as an ``nnkOutTy`` node; in
  ## a CLI declaration it is a plain name, so it reads back as ``"out"``.
  ## Anything that is not an identifier reads back as its source text.
  case node.kind
  of nnkIdent, nnkSym:
    result = $node
  of nnkAccQuoted:
    result = ""
    for child in node:
      result.add(cliIdentText(child))
  of nnkOutTy:
    result = "out"
  else:
    result = node.repr

proc cliCalleeName*(node: NimNode): string =
  ## The head word of a call or command statement (``flag`` in
  ## ``flag x is string``), or ``""`` for any other node.
  if node.kind in {nnkCall, nnkCommand} and node.len > 0:
    cliIdentText(node[0])
  else:
    ""

proc cliNamedArg*(node: NimNode; name: string): NimNode =
  ## The value of a ``name = value`` argument when ``node`` is one with that
  ## (style-insensitive) name, else ``nil``.
  if node.kind == nnkExprEqExpr and cliIdentText(node[0]).normalize ==
      name.normalize:
    node[1]
  else:
    nil

proc cliStrLit*(node: NimNode; what: string): string =
  ## A value the parser must know at compile time: a string literal, or a
  ## compile error naming ``what``. An expression is refused rather than
  ## read as its source text, which would turn ``alias = ShortFlag`` into the
  ## alias ``"ShortFlag"``.
  if node.isNil or node.kind notin {nnkStrLit..nnkTripleStrLit}:
    error(what & " must be a string literal: it is used at compile time and " &
      "the macro cannot evaluate an expression here", node)
  node.strVal

proc cliNameLit*(node: NimNode): string =
  ## A name written either as a string literal or as an identifier
  ## (``subcmd "build"``): the literal's value, or the node's source text.
  case node.kind
  of nnkStrLit..nnkTripleStrLit:
    node.strVal
  else:
    node.repr

proc cliIntLit*(node: NimNode; fallback: int): int =
  ## An integer literal's value, or ``fallback`` for anything else.
  case node.kind
  of nnkIntLit..nnkUInt64Lit:
    int(node.intVal)
  else:
    fallback

proc cliBoolLit*(node: NimNode; fallback: bool): bool =
  ## ``true`` / ``false`` written as identifiers, or ``fallback``.
  if node.kind == nnkIdent:
    case ($node).normalize
    of "true": true
    of "false": false
    else: fallback
  else:
    fallback

proc cliFormatLit*(node: NimNode; fallback: CliArgFormat): CliArgFormat =
  ## ``separate`` / ``concat`` / ``equals`` (or the enum names), else
  ## ``fallback``.
  case cliIdentText(node).normalize
  of "separate", "cafseparate":
    cafSeparate
  of "concat", "cafconcat":
    cafConcat
  of "equals", "cafequals":
    cafEquals
  else:
    fallback

proc cliPlacementLit*(node: NimNode;
                      fallback: CliArgPlacement): CliArgPlacement =
  ## ``after`` / ``before`` (or ``global``, or the enum names), else
  ## ``fallback``.
  case cliIdentText(node).normalize
  of "after", "aftersubcommand", "capaftersubcommand":
    capAfterSubcommand
  of "before", "beforesubcommand", "global", "capbeforesubcommand":
    capBeforeSubcommand
  else:
    fallback

# ---------------------------------------------------------------------------
# Parameter declarations.
# ---------------------------------------------------------------------------

proc paramDeclOf(head: string): tuple[found: bool; decl: CliParamDecl] =
  case head.normalize
  of "pos": (true, cpdPos)
  of "flag": (true, cpdFlag)
  of "boolflag": (true, cpdBoolFlag)
  else: (false, cpdPos)

proc isTypedHead(node: NimNode): bool =
  node.kind == nnkInfix and node.len == 3 and node[0].eqIdent("is")

proc parseCliTypedHead*(node: NimNode; context: string):
    tuple[matched: bool, name: string, nimType: string] =
  ## The strict reading of a declaration's ``<name> is <Type>`` head:
  ## ``matched`` is false for a bare name, and any other infix is a compile
  ## error naming ``context``, because it is almost certainly a mistyped
  ## declaration.
  if isTypedHead(node):
    result.matched = true
    result.name = cliIdentText(node[1])
    result.nimType = node[2].repr
  elif node.kind == nnkInfix:
    error(context & " uses an unsupported infix form: " & node.repr, node)

proc parseCliParamHead*(stmt: NimNode): CliParamHead =
  ## Classifies ``stmt`` as a parameter declaration WITHOUT validating it:
  ## ``matched`` is false for anything that is not ``pos`` / ``flag`` /
  ## ``boolFlag`` followed by a name or a ``<name> is <Type>`` head, and
  ## nothing here raises. For tools that scan a ``cli:`` body for its
  ## parameters while leaving diagnostics to the full parser.
  if stmt.kind notin {nnkCall, nnkCommand} or stmt.len < 2:
    return
  if stmt[0].kind notin {nnkIdent, nnkSym}:
    return
  let (found, decl) = paramDeclOf(cliIdentText(stmt[0]))
  if not found:
    return
  result.decl = decl
  let nameArg = stmt[1]
  if isTypedHead(nameArg):
    if nameArg[1].kind notin {nnkIdent, nnkSym, nnkAccQuoted}:
      return
    result.name = cliIdentText(nameArg[1])
    result.typed = true
    result.nimType = nameArg[2].repr
    result.matched = true
  elif nameArg.kind in {nnkIdent, nnkSym, nnkAccQuoted}:
    result.name = cliIdentText(nameArg)
    result.matched = true

proc parseCliParamExtension*(ext: var NoCliExtension; kind: CliParamKind;
                             arg: NimNode): bool =
  ## The empty extension claims no argument.
  false

proc parseCliParam*[P](node: NimNode): CliParam[P] =
  ## Parses one ``pos`` / ``flag`` / ``boolFlag`` declaration. Named
  ## arguments the declaration kind does not take go to the extension hook
  ## ``parseCliParamExtension`` (see the module documentation), and are
  ## ignored when it does not claim them.
  mixin parseCliParamExtension
  let kindName = cliCalleeName(node).normalize
  let info = node.lineInfoObj()
  var headMatched = false
  if kindName == "pos":
    if node.len < 2:
      error("pos requires a parameter name", node)
    let head = parseCliTypedHead(node[1], "pos parameter")
    headMatched = head.matched
    result.kind = cpkPositional
    result.name = if head.matched: head.name else: cliIdentText(node[1])
    if head.matched:
      result.nimType = head.nimType
    else:
      if node.len < 3:
        error("pos requires a type", node)
      result.nimType = node[2].repr
    result.required = true
  elif kindName == "flag" or kindName == "boolflag":
    if node.len < 2:
      error(kindName & " requires a parameter name", node)
    let head = parseCliTypedHead(node[1], kindName & " parameter")
    headMatched = head.matched
    result.kind = cpkFlag
    result.name = if head.matched: head.name else: cliIdentText(node[1])
    if kindName == "boolflag":
      result.nimType = if head.matched: head.nimType else: "bool"
      if result.nimType.normalize != "bool":
        error("boolFlag requires bool type", node[1])
    elif head.matched:
      result.nimType = head.nimType
    else:
      if node.len < 3:
        error("flag requires a type", node)
      result.nimType = node[2].repr
    result.required = false
  else:
    error("unsupported CLI parameter DSL form: " & node.repr, node)
  result.position = 0
  # The named arguments start after the head: after ``<name> is <Type>``,
  # or after ``<name>, <Type>`` in the older call spelling. A ``boolFlag``
  # written without ``is`` therefore has its first argument skipped; that is
  # how this grammar has always read it, and changing it would change what
  # existing declarations mean.
  let optionStart = if headMatched: 2 else: 3
  for i in optionStart ..< node.len:
    let arg = node[i]
    if arg.kind != nnkExprEqExpr:
      continue
    let key = cliIdentText(arg[0]).normalize
    let value = arg[1]
    var consumed = true
    case result.kind
    of cpkPositional:
      case key
      of "position":
        result.position = cliIntLit(value, result.position)
      of "repeated":
        result.repeated = cliBoolLit(value, result.repeated)
      else:
        consumed = false
    of cpkFlag:
      case key
      of "alias":
        result.alias = cliStrLit(value, "param alias")
      of "required":
        result.required = cliBoolLit(value, result.required)
      of "format":
        result.format = cliFormatLit(value, result.format)
      of "placement":
        result.placement = cliPlacementLit(value, result.placement)
      of "repeated":
        result.repeated = cliBoolLit(value, result.repeated)
      else:
        consumed = false
    if not consumed:
      discard parseCliParamExtension(result.ext, result.kind, arg)
  result.sourceFile = info.filename
  result.sourceLine = info.line

proc cliDeclaredParamNames*(body: NimNode): seq[string] =
  ## The name of every parameter declared anywhere in ``body``, nested
  ## scopes included, in source order. For diagnostics that must tell a name
  ## declared in another scope from one that does not exist.
  proc walk(node: NimNode; output: var seq[string]) =
    case node.kind
    of nnkCall, nnkCommand:
      let head = cliCalleeName(node).normalize
      if head in ["pos", "flag", "boolflag"] and node.len >= 2:
        let parsed = parseCliTypedHead(node[1], head & " parameter")
        output.add(if parsed.matched: parsed.name
                   else: cliIdentText(node[1]))
      for i in 0 ..< node.len:
        walk(node[i], output)
    of nnkStmtList:
      for child in node:
        walk(child, output)
    else:
      discard
  walk(body, result)

# ---------------------------------------------------------------------------
# Scopes.
# ---------------------------------------------------------------------------

proc parseCliCommandExtension*[P](cmd: var CliCommand[NoCliExtension, P];
                                  stmt: NimNode; scope: CliScope): bool =
  ## The empty command extension claims no statement.
  false

proc parseCliScope*[C, P](body: NimNode; path: seq[string]; isRoot: bool;
                          parent: CliCommand[C, P]; wholeBody: NimNode;
                          commands: var seq[CliCommand[C, P]]):
    CliCommand[C, P] =
  ## Parses one scope — the root ``cli:`` body, or a ``call:`` /
  ## ``subcmd`` body — in source order and returns its command. The scope
  ## starts from ``parent``'s parameters and extension (what the enclosing
  ## scope had declared when this one opened). Every nested scope is
  ## appended to ``commands`` after the scopes nested inside it; the root is
  ## not appended.
  mixin parseCliCommandExtension
  let info = body.lineInfoObj()
  result.sourceFile = info.filename
  result.sourceLine = info.line
  result.path = path
  result.name = if path.len == 0: "" else: path[^1]
  result.params = parent.params
  result.ext = parent.ext
  for stmt in body:
    let head = cliCalleeName(stmt).normalize
    case head
    of "pos":
      result.params.add(parseCliParam[P](stmt))
    of "flag", "boolflag":
      var param = parseCliParam[P](stmt)
      if isRoot:
        param.placement = capBeforeSubcommand
      result.params.add(param)
    of "call", "subcmd":
      let childName = if head == "call": "" else: cliNameLit(stmt[1])
      var childPath = path
      if childName.len > 0:
        childPath.add(childName)
      discard parseCliScope(stmt[stmt.len - 1], childPath, false, result,
        wholeBody, commands)
    else:
      discard parseCliCommandExtension(result, stmt,
        CliScope(isRoot: isRoot, path: path, wholeBody: wholeBody))
  if not isRoot:
    commands.add(result)

proc parseCliModel*[C, P](body: NimNode; rootExt: C): CliModel[C, P] =
  ## Parses a whole ``cli:`` body. ``rootExt`` is the root command's
  ## extension value before any statement is read — the consumer's
  ## defaults, which every scope inherits unless a statement changes them.
  var root: CliCommand[C, P]
  root.ext = rootExt
  result.root = parseCliScope[C, P](body, @[], true, root, body,
    result.commands)

macro plainCliModel*(body: untyped): untyped =
  ## The model of a ``cli:`` body with no extension, as a constant:
  ##
  ## .. code-block:: nim
  ##   const model = plainCliModel:
  ##     subcmd "run":
  ##       pos script is string
  newLit(parseCliModel[NoCliExtension, NoCliExtension](body,
    NoCliExtension()))

# ---------------------------------------------------------------------------
# Parameter groups.
# ---------------------------------------------------------------------------

proc collectCliParamGroup*(node: NimNode):
    tuple[name: string, statements: seq[NimNode]] =
  ## Reads a parameter group: a parameterless template whose body is a list
  ## of declarations, shared between commands by naming it as a statement
  ## (``commonFlags()``).
  ##
  ## .. code-block:: nim
  ##   template commonFlags() =
  ##     boolFlag verbose is bool, alias = "-v"
  if node.kind != nnkTemplateDef:
    error("CLI parameter group must be a template definition", node)
  result.name = cliIdentText(node[0]).normalize
  if node[3].kind != nnkFormalParams or node[3].len != 1:
    error("CLI parameter group templates must not accept parameters", node[3])
  let body = node[^1]
  if body.kind != nnkStmtList:
    error("CLI parameter group template must contain a statement body", body)
  for stmt in body:
    result.statements.add(stmt)

proc expandCliParamGroups*(stmt: NimNode; groups: CliParamGroups;
                           stack: var seq[string]): seq[NimNode] =
  ## ``stmt`` itself, or — when it names a group (``commonFlags()``) — the
  ## group's statements, with nested groups expanded. ``stack`` holds the
  ## groups being expanded, so a group that includes itself is a compile
  ## error instead of an endless expansion.
  let groupName = cliCalleeName(stmt).normalize
  if groupName.len > 0 and groups.hasKey(groupName) and stmt.len == 1:
    if stack.find(groupName) >= 0:
      error("recursive CLI parameter group: " & groupName, stmt)
    stack.add(groupName)
    for groupedStmt in groups[groupName]:
      for expandedStmt in expandCliParamGroups(groupedStmt, groups, stack):
        result.add(expandedStmt)
    discard stack.pop()
  else:
    result.add(stmt)
