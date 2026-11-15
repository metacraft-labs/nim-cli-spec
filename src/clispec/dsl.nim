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
##   accepts ``position = <int>``, ``repeated = true|false``,
##   ``required = true|false`` (it is required unless it says otherwise or
##   has a ``default``) and ``rest = true|false`` (the rest of the command
##   line, ``CliParam.rest``).
## * Every parameter also accepts what a program declares about its own
##   command line: ``help = "<text>"``, ``default = <expr>``,
##   ``env = ["NAME", ...]``, ``values = [a, b, c]``,
##   ``complete = <completer>``, ``key = "<dotted.key>"``,
##   ``sources = {cli, env, file}``,
##   ``merge = replace|append|errorOnConflict|<combine proc>``,
##   ``separator = ","``, ``implies = [<param> = <value>, ...]`` and
##   ``visibility = shown|internal|hidden``; a flag also ``short = 'x'``,
##   ``optionalValue = <expr>``, ``negatable = true`` and
##   ``counted = true``. ``clispec/model`` documents what each one means and
##   how expressions and configuration keys are kept.
## * Also for every parameter: ``longHelp = "<text>"`` (further paragraphs)
##   and ``valueName = "<text>"`` (the help placeholder). ``help`` and
##   ``longHelp`` take a constant string expression too: a literal or ``&``
##   of literals is folded here, anything else (a ``const``, a ``when``
##   expression) is kept as ``helpExpr`` / ``longHelpExpr`` and evaluated by
##   the generator (``cliModelValue``). ``sources = {}`` declares a
##   parameter no source supplies directly.
## * And for a flag: ``acceptsNextWord = true`` (with ``optionalValue``),
##   ``refuseFalse = true`` (a switch) and ``alsoSets = [<param> =
##   "<text>", ...]``.
## * Directly under ``cli:``, ``flagMatching exact | ignoreCase |
##   ignoreStyle``, ``commandMatching exact | ignoreCase | ignoreStyle``
##   (the same modes, for subcommand words) and ``parsing <rule>, ...``
##   (``shortEquals``, ``helpWithAnyValue``, ``helpInCluster``,
##   ``valueErrorsBeforeHelp``, ``switchesRefuseFalse``,
##   ``lenientSwitchValues``, ``colonValues``, ``equalsTakesNext``,
##   ``helpWord``, ``versionWord``, ``longHelpOnly``,
##   ``loneDashesAreFlags``, ``exactOneLetterFlags``) opt into the
##   command-line rules ``clispec/model`` documents.
## * ``call:`` opens the anonymous command, ``subcmd "<name>":`` a named one;
##   both nest. A nested scope sees the parameters its enclosing scopes
##   declared before it opened. The head takes ``help``, ``visibility`` and
##   (``subcmd`` only) ``aliases = ["<word>", ...]`` and ``shadowedByWord =
##   true|false`` (``CliCommand.shadowedByWord``):
##   ``subcmd "build", help = "...", aliases = ["b"]:``,
##   ``call(help = "..."):``.
## * ``help "<text>"`` as a statement gives the scope's command its help
##   (the only way to give the root command one).
## * ``group "<title>"[, help = "<text>"]:`` lists the declarations inside it
##   under one help heading; it opens no command and changes no scoping.
## * A flag declared directly under ``cli:`` is placed before the subcommand
##   word (``placement = before``); everywhere else the default is after it.
## * Directly under ``cli:`` only, ``configSchema "<id>"`` names the schema
##   identifier the program's configuration files declare, and
##   ``convention <source> = declared|camelCase|snakeCase|kebabCase`` the
##   naming convention of one source: ``cli`` (the long flags), ``file``
##   (every configuration file) or ``"<name>"`` (the configuration layer or
##   format of that name). ``keyStyle <convention>`` is the older spelling
##   of ``convention file = <convention>``. ``parseCliModel`` reads them
##   before anything else (``clispec/model``, "Naming conventions").
## * A parameter refines its spellings with ``perConvention = [<convention>
##   = "<spelling>", ...]`` (its name in one convention) and ``perSource =
##   [cli = "<flag>", "<source>" = "<dotted.key>", ...]`` (its long flag, or
##   its whole key in one named file source).
##
## Anything else — an unknown statement, or a named argument the parameter
## kind does not take — is offered to the consumer's extension (below) and
## ignored when no extension claims it. The library's own words above never
## reach the extension.
##
## Invalid declarations
## ====================
##
## A declaration that cannot mean anything is a compile error that names the
## parameter (``clispec: parameter '<name>': ...``) or the command: a name
## declared twice in one command (compared as Nim compares identifiers,
## inherited parameters included); a ``short``, ``alias`` or ``--<name>``
## spelling used twice among the flags of one placement; a configuration key
## used twice in one command; ``default`` or ``optionalValue`` together with
## ``required = true``; ``key`` when ``sources`` exclude ``file``; ``env``
## when they exclude ``env``; ``counted`` on a non-integer; ``negatable`` on
## a non-``bool``; a counted flag that is negatable or has an
## ``optionalValue``; ``negatable`` or ``counted`` set to anything but
## ``true`` or ``false``; a flag-only argument on a positional; ``implies``
## naming no parameter of the command, or the parameter itself; ``alsoSets``
## naming no parameter of the command, the parameter itself or one parameter
## twice, or with a value that is not a string literal; ``acceptsNextWord``
## without ``optionalValue``; ``refuseFalse`` on a non-``bool`` or with
## ``negatable``; ``help`` or ``longHelp`` that is not a constant string
## expression; an unknown ``parsing`` rule, ``flagMatching`` or
## ``commandMatching`` mode; ``parsing exactOneLetterFlags`` under
## ``flagMatching exact`` (the default); one of
## the library's arguments given twice; two subcommands of one command answering
## to the same word (compared under ``commandMatching``), or one answering
## to ``help`` under ``parsing helpWord`` or to ``version`` under
## ``versionWord`` without ``shadowedByWord = true``, or ``shadowedByWord``
## on one that answers to neither (or on ``call:``); ``rest`` on a flag, on
## a type that is not a ``seq``, or together with ``repeated``; ``aliases``
## on ``call:``; a ``help`` statement inside a ``group`` section;
## ``keyStyle``, ``convention``, ``configSchema``, ``flagMatching``,
## ``commandMatching`` or ``parsing`` anywhere but directly under ``cli:``;
## an unknown
## convention, or one source's convention given twice; a ``perConvention``
## entry for ``declared`` or one convention given twice; a ``perSource``
## entry naming a file source the description does not declare, ``file``
## (that is ``key``), the same source twice, ``cli`` on a positional or when
## ``sources`` exclude ``cli``, or a file source when they exclude ``file``;
## and two parameters of one command whose long flags or keys in one source
## come out the same once converted and overridden. (``cliProgram`` adds rules of its own for a
## program's own command line, such as reserved configuration keys and a
## ``rest`` positional that is not the last one of its command or follows a
## ``repeated`` one.)
##
## Whether a ``default``, ``optionalValue``, ``values`` entry or ``implies``
## value is a value of the parameter's type is checked here when the type is
## a builtin and the value a literal; otherwise it needs the compiler, and
## ``cliModelTypeChecks`` generates the check as code for the consumer's
## macro to place in its output (``plainCliModel`` does). The same checks
## reject ``merge = append`` on a parameter that is neither a ``seq`` nor
## counted, and a ``complete`` expression that is not a ``CliCompleter``
## (``proc (ctx: CliCompletionContext): seq[CliCompletion]``,
## ``clispec/completers``). A combine proc (``merge = <proc>``) is recorded
## and not checked here: it is called by the library that merges several
## sources (confutils, over a clispec description), which checks its
## signature where it calls it.
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

import std/[macros, options, strutils, tables]

import ./[model, completers]

export model, completers

type
  CliNaming* = object
    ## The conventions of a description's sources, which every key and
    ## long flag is spelt in (``clispec/model``, "Naming conventions").
    fileConvention*: CliConvention
      ## The ``file`` source's (``CliModel.keyStyle``).
    flagConvention*: CliConvention
      ## The command line's long flags'.
    fileSources*: seq[CliSourceConvention]
      ## The named file sources'.
    commandMatching*: CliFlagMatching
      ## How subcommand words are compared (``CliModel.commandMatching``),
      ## for the check that no two subcommands answer to one word.
    parseRules*: set[CliParseRule]
      ## The description's ``parsing`` rules, for the words ``helpWord`` and
      ## ``versionWord`` reserve.

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

func cliNamingOf*[C, P](model: CliModel[C, P]): CliNaming =
  ## The conventions a model's description declares.
  CliNaming(fileConvention: model.keyStyle,
    flagConvention: model.flagConvention, fileSources: model.fileSources,
    commandMatching: model.commandMatching, parseRules: model.parseRules)

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

# ---------------------------------------------------------------------------
# Validation helpers.
# ---------------------------------------------------------------------------

proc cliParamError*(param, message: string; node: NimNode) =
  ## A compile error about the parameter ``param``. Every diagnostic about a
  ## parameter goes through here, so each one names it the same way:
  ## ``clispec: parameter '<name>': <message>``.
  error("clispec: parameter '" & param & "': " & message, node)

proc cliCommandLabel*(path: seq[string]; isRoot = true): string =
  ## A command for diagnostics: ``command 'build target'``, ``the root
  ## command``, or — for a ``call:`` directly under ``cli:``, which has no
  ## path either — ``the anonymous call: command``.
  if path.len > 0: "command '" & path.join(" ") & "'"
  elif isRoot: "the root command"
  else: "the anonymous call: command"

proc cliExprOf*(node: NimNode): CliExpr =
  ## Keeps an expression of the description in the model: its source text
  ## and where it was written (see "Expressions" in ``clispec/model``).
  let info = node.lineInfoObj()
  CliExpr(code: node.repr, sourceFile: info.filename, sourceLine: info.line,
    sourceColumn: info.column)

proc constExprText(n: NimNode): string =
  ## The source text of a constant expression, parenthesised so that
  ## ``parseExpr`` reads it back on one line (``repr`` prints a ``when``
  ## expression over several lines, which does not parse back).
  case n.kind
  of nnkPar:
    if n.len == 1: "(" & constExprText(n[0]) & ")" else: n.repr
  of nnkInfix:
    "(" & constExprText(n[1]) & " " & n[0].repr & " " &
      constExprText(n[2]) & ")"
  of nnkPrefix:
    n[0].repr & "(" & constExprText(n[1]) & ")"
  of nnkStmtList, nnkStmtListExpr:
    if n.len == 1: constExprText(n[0]) else: n.repr
  of nnkWhenStmt, nnkIfExpr, nnkIfStmt:
    var parts: seq[string] = @[]
    for i, b in n:
      if b.kind in {nnkElifBranch, nnkElifExpr}:
        let head = if i > 0: "elif "
                   elif n.kind == nnkWhenStmt: "when "
                   else: "if "
        parts.add(head & constExprText(b[0]) & ": " & constExprText(b[1]))
      else:
        parts.add("else: " & constExprText(b[0]))
    "(" & parts.join(" ") & ")"
  of nnkCall, nnkCommand:
    var args: seq[string] = @[]
    for a in n[1 .. ^1]:
      args.add(constExprText(a))
    constExprText(n[0]) & "(" & args.join(", ") & ")"
  else:
    n.repr

proc foldStrLit(n: NimNode; folded: var string): bool =
  ## Whether ``n`` is a string literal or ``&`` of such (parenthesised or
  ## not); ``folded`` is then its value.
  case n.kind
  of nnkStrLit..nnkTripleStrLit:
    folded = n.strVal
    true
  of nnkPar:
    n.len == 1 and foldStrLit(n[0], folded)
  of nnkInfix:
    var a, b = ""
    if n[0].eqIdent("&") and foldStrLit(n[1], a) and foldStrLit(n[2], b):
      folded = a & b
      true
    else:
      false
  else:
    false

proc cliConstStr*(node: NimNode; text: var string; expr: var CliExpr) =
  ## A text argument that may be a constant string expression (``help``,
  ## ``longHelp``): a string literal or ``&`` of literals is folded into
  ## ``text``; anything else (a ``const``, a ``when`` expression, ``&`` of
  ## those) is kept in ``expr`` for a generator to evaluate at compile time
  ## where the description is (``cliModelValue``), and ``text`` is left
  ## empty.
  var folded = ""
  if foldStrLit(node, folded):
    text = folded
    expr = CliExpr()
  else:
    text = ""
    let info = node.lineInfoObj()
    expr = CliExpr(code: constExprText(node), sourceFile: info.filename,
      sourceLine: info.line, sourceColumn: info.column)

proc cliStrList(node: NimNode; param, what: string): seq[string] =
  ## A string literal, or a bracketed list of string literals, each
  ## non-empty.
  var items: seq[NimNode] = @[]
  if node.kind == nnkBracket:
    for child in node:
      items.add(child)
  else:
    items.add(node)
  if items.len == 0:
    cliParamError(param, what & " must name at least one entry", node)
  for item in items:
    if item.kind notin {nnkStrLit..nnkTripleStrLit} or item.strVal.len == 0:
      cliParamError(param, what & " entries must be non-empty string " &
        "literals, got: " & item.repr, item)
    result.add(item.strVal)

proc cliSourcesLit(node: NimNode; param: string): set[CliSource] =
  ## ``{cli, env, file}``; ``{}`` declares a parameter no source supplies
  ## directly (``CliParam.sources``).
  if node.kind notin {nnkCurly, nnkBracket}:
    cliParamError(param, "sources must be a set such as {cli, env, file}, " &
      "got: " & node.repr, node)
  for item in node:
    case cliIdentText(item).normalize
    of "cli": result.incl(csCli)
    of "env": result.incl(csEnv)
    of "file": result.incl(csFile)
    else:
      cliParamError(param, "unknown source '" & item.repr &
        "' (expected cli, env or file)", item)

proc cliVisibilityLit*(node: NimNode; owner: string): CliVisibility =
  ## ``shown`` / ``internal`` / ``hidden``; anything else is a compile error
  ## naming ``owner``.
  case cliIdentText(node).normalize
  of "shown", "cvshown": cvShown
  of "internal", "cvinternal": cvInternal
  of "hidden", "cvhidden": cvHidden
  else:
    error("clispec: " & owner & ": visibility must be shown, internal or " &
      "hidden, got: " & node.repr, node)

type
  TypeClass = enum
    ## What the parser can tell about a declared type from its spelling.
    ## ``tcUnknown`` (aliases, enums, user types) is checked by the code
    ## ``cliModelTypeChecks`` generates instead.
    tcUnknown, tcBool, tcString, tcChar, tcInt, tcFloat, tcSeq

proc typeClassOf(nimType: string): TypeClass =
  let t = nimType.strip()
  if t.startsWith("seq["):
    return tcSeq
  case t
  of "bool": tcBool
  of "string": tcString
  of "char": tcChar
  of "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16",
     "uint32", "uint64", "Natural", "Positive", "byte":
    tcInt
  of "float", "float32", "float64":
    tcFloat
  else:
    tcUnknown

proc literalFits(tc: TypeClass; value: NimNode): bool =
  ## False only when ``value`` is a literal that certainly is not a value of
  ## a type of class ``tc``. Expressions, and types the parser cannot
  ## classify, are left to the generated checks.
  if tc == tcUnknown:
    return true
  case value.kind
  of nnkStrLit..nnkTripleStrLit:
    tc == tcString
  of nnkCharLit:
    tc == tcChar
  of nnkIntLit..nnkUInt64Lit:
    tc in {tcInt, tcFloat}
  of nnkFloatLit..nnkFloat128Lit:
    tc == tcFloat
  of nnkIdent:
    if ($value).normalize in ["true", "false"]: tc == tcBool
    else: true
  of nnkBracket:
    tc == tcSeq
  of nnkPrefix:
    if value.len == 2 and value[0].eqIdent("@") and value[1].kind == nnkBracket:
      tc == tcSeq
    else:
      true
  else:
    true

proc requireLiteralFits(param, what, nimType: string; value: NimNode) =
  if not literalFits(typeClassOf(nimType), value):
    cliParamError(param, what & " `" & value.repr & "` is not a valid " &
      nimType, value)

proc strictBoolLit(node: NimNode; param, what: string): bool =
  ## ``true`` or ``false`` for an argument the library introduced: anything
  ## else is a compile error rather than a silent fallback, so a typo such as
  ## ``negatable = yes`` cannot leave the flag quietly unnegatable.
  if node.kind == nnkIdent:
    case ($node).normalize
    of "true": return true
    of "false": return false
    else: discard
  cliParamError(param, what & " must be true or false, got: " & node.repr,
    node)

proc elementTypeOf(nimType: string): string =
  ## The element type of a ``seq[T]`` spelling, else the type itself.
  let t = nimType.strip()
  if t.startsWith("seq[") and t.endsWith("]"): t[4 .. ^2].strip() else: t

# ---------------------------------------------------------------------------
# One parameter.
# ---------------------------------------------------------------------------

const
  commonParamKeys = ["help", "default", "env", "values", "complete", "key",
    "sources", "merge", "separator", "implies", "visibility",
    "perconvention", "persource", "longhelp", "valuename"]
    ## The named arguments every parameter takes, normalised.
  flagOnlyParamKeys = ["short", "optionalvalue", "negatable", "counted",
    "acceptsnextword", "refusefalse", "alsosets"]
    ## The named arguments only a flag takes, normalised.
  positionalOnlyParamKeys = ["rest"]
    ## The named arguments only a positional takes and that a flag must not
    ## pass to an extension, normalised.

proc cliConventionLit*(node: NimNode; what: string): CliConvention =
  ## A convention written as an identifier: ``declared``, ``camelCase``,
  ## ``snakeCase`` or ``kebabCase`` (compared as Nim compares identifiers).
  ## Anything else is a compile error naming ``what``.
  let text = if node.kind in {nnkIdent, nnkSym, nnkAccQuoted}:
               cliIdentText(node)
             else: ""
  for c in CliConvention:
    if text.len > 0 and nimIdentNormalize(text) == nimIdentNormalize($c):
      return c
  error("clispec: " & what & " must be declared, camelCase, snakeCase or " &
    "kebabCase, not " & node.repr, node)

proc validFlagName(text: string): bool =
  ## A long flag's name (without ``--``) or a key segment: non-empty, no
  ## leading ``-``, and no ``=``, ``.`` or white space.
  if text.len == 0 or text[0] == '-':
    return false
  for ch in text:
    if ch in {'=', '.'} + Whitespace:
      return false
  true

proc validDottedKey(text: string): bool =
  text.len > 0 and not text.startsWith(".") and not text.endsWith(".") and
    ".." notin text

proc parsePerConvention(value: NimNode; param: string):
    seq[CliConventionSpelling] =
  ## ``perConvention = [<convention> = "<spelling>", ...]``.
  if value.kind != nnkBracket or value.len == 0:
    cliParamError(param, "perConvention must be a non-empty list such as " &
      "[kebabCase = \"http-port\"], got: " & value.repr, value)
  for item in value:
    if item.kind != nnkExprEqExpr:
      cliParamError(param, "perConvention entries are written " &
        "<convention> = \"<spelling>\", got: " & item.repr, item)
    let convention = cliConventionLit(item[0],
      "parameter '" & param & "': a perConvention entry's convention")
    if convention == cnDeclared:
      cliParamError(param, "perConvention cannot override `declared`: " &
        "that is the name as written", item[0])
    let spelling = cliStrLit(item[1], "perConvention spelling")
    if not validFlagName(spelling):
      cliParamError(param, "the " & $convention & " spelling must be one " &
        "name without '.', '=', white space or a leading '-', got: \"" &
        spelling & "\"", item[1])
    for seen in result:
      if seen.convention == convention:
        cliParamError(param, "perConvention gives " & $convention &
          " twice", item)
    result.add(CliConventionSpelling(convention: convention,
      spelling: spelling))

proc parsePerSource(value: NimNode; param: string; kind: CliParamKind):
    seq[CliSourceSpelling] =
  ## ``perSource = [cli = "<flag>", "<source>" = "<key>", ...]``. Whether
  ## a named source exists is checked once the description's conventions
  ## are known (``addScopeParam``).
  if value.kind != nnkBracket or value.len == 0:
    cliParamError(param, "perSource must be a non-empty list such as " &
      "[cli = \"port\", \"project\" = \"web.port\"], got: " & value.repr,
      value)
  for item in value:
    if item.kind != nnkExprEqExpr:
      cliParamError(param, "perSource entries are written " &
        "cli = \"<flag>\" or \"<source>\" = \"<key>\", got: " & item.repr,
        item)
    var source = ""
    if item[0].kind in {nnkStrLit..nnkTripleStrLit}:
      source = item[0].strVal
      if source in [CliSourceCli, CliSourceFile] or source.len == 0:
        cliParamError(param, "perSource names a file source with a " &
          "string that is not empty, `cli` or `file`, got: " & item[0].repr,
          item[0])
    elif item[0].kind in {nnkIdent, nnkSym, nnkAccQuoted}:
      case cliIdentText(item[0]).normalize
      of "cli":
        source = CliSourceCli
      of "file":
        cliParamError(param, "the override for every file source is " &
          "written key = \"<dotted.key>\", not perSource = [file = ...]",
          item[0])
      else:
        cliParamError(param, "perSource names `cli` or a file source as " &
          "a string (\"project\"), not " & item[0].repr, item[0])
    else:
      cliParamError(param, "perSource names `cli` or a file source as " &
        "a string (\"project\"), not " & item[0].repr, item[0])
    let spelling = cliStrLit(item[1], "perSource spelling")
    if source == CliSourceCli:
      if kind == cpkPositional:
        cliParamError(param, "a positional has no long flag, so perSource " &
          "cannot give its cli spelling", item)
      if not validFlagName(spelling):
        cliParamError(param, "the cli spelling is a long flag's name " &
          "without --, with no '.', '=', white space or leading '-', " &
          "got: \"" & spelling & "\"", item[1])
    elif not validDottedKey(spelling):
      cliParamError(param, "the key in source '" & source & "' must be a " &
        "non-empty dotted name such as \"section.name\", got: \"" &
        spelling & "\"", item[1])
    for seen in result:
      if seen.source == source:
        cliParamError(param, "perSource gives source '" & source &
          "' twice", item)
    result.add(CliSourceSpelling(source: source, spelling: spelling))

proc parseCliParam*[P](node: NimNode): CliParam[P] =
  ## Parses one ``pos`` / ``flag`` / ``boolFlag`` declaration. Named
  ## arguments the declaration kind does not take go to the extension hook
  ## ``parseCliParamExtension`` (see the module documentation), and are
  ## ignored when it does not claim them. Declarations that cannot mean
  ## anything are compile errors naming the parameter (see "Invalid
  ## declarations" in the module documentation).
  mixin parseCliParamExtension
  let kindName = cliCalleeName(node).normalize
  let info = node.lineInfoObj()
  if kindName == "pos":
    if node.len < 2:
      error("pos requires a parameter name", node)
    let head = parseCliTypedHead(node[1], "pos parameter")
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
  result.sources = {csFile, csEnv, csCli}
  let name = result.name
  # The named arguments start right after the name: the type of the older
  # call spelling (``flag(<name>, <Type>, ...)``) sits at index 2 but is not
  # a ``name = value`` node, so the loop passes over it. (Before this
  # version a ``boolFlag`` written without ``is bool`` lost its first named
  # argument, because the loop started at index 3 for every form without an
  # ``is`` head.)
  var given: seq[string] = @[]
  var requiredNode: NimNode = nil
  var keyNode, envNode, defaultNode, perSourceNode: NimNode = nil
  var acceptsNextWordNode, refuseFalseNode, restNode: NimNode = nil
  for i in 2 ..< node.len:
    let arg = node[i]
    if arg.kind != nnkExprEqExpr:
      continue
    let spelled = cliIdentText(arg[0])
    let key = spelled.normalize
    let value = arg[1]
    if key in commonParamKeys or key in flagOnlyParamKeys or
        key in positionalOnlyParamKeys:
      if key in given:
        cliParamError(name, "`" & spelled & "` is given twice", arg)
      given.add(key)
      if key in flagOnlyParamKeys and result.kind == cpkPositional:
        cliParamError(name, "`" & spelled & "` applies to flags only, " &
          "not to a positional", arg)
      if key in positionalOnlyParamKeys and result.kind == cpkFlag:
        cliParamError(name, "`" & spelled & "` applies to positionals " &
          "only, not to a flag", arg)
    var consumed = true
    case key
    of "help":
      cliConstStr(value, result.help, result.helpExpr)
    of "longhelp":
      cliConstStr(value, result.longHelp, result.longHelpExpr)
    of "valuename":
      result.valueName = cliStrLit(value, "valueName")
      if result.valueName.len == 0:
        cliParamError(name, "valueName must not be empty", value)
    of "acceptsnextword":
      result.acceptsNextWord = strictBoolLit(value, name, spelled)
      acceptsNextWordNode = arg
    of "rest":
      result.rest = strictBoolLit(value, name, spelled)
      restNode = arg
    of "refusefalse":
      result.refuseFalse = strictBoolLit(value, name, spelled)
      refuseFalseNode = arg
    of "alsosets":
      if value.kind != nnkBracket or value.len == 0:
        cliParamError(name, "alsoSets must be a non-empty list such as " &
          "[other = \"value\"], got: " & value.repr, value)
      for item in value:
        if item.kind != nnkExprEqExpr or
            item[0].kind notin {nnkIdent, nnkSym, nnkAccQuoted} or
            item[1].kind notin {nnkStrLit..nnkTripleStrLit}:
          cliParamError(name, "alsoSets entries are written " &
            "<parameter> = \"<value as written on the command line>\", " &
            "got: " & item.repr, item)
        result.alsoSets.add(CliAlsoSet(param: cliIdentText(item[0]),
          text: item[1].strVal))
    of "default":
      result.default = cliExprOf(value)
      defaultNode = value
    of "env":
      result.env = cliStrList(value, name, "env")
      envNode = value
    of "values":
      if value.kind != nnkBracket or value.len == 0:
        cliParamError(name, "values must be a non-empty list such as " &
          "[a, b, c], got: " & value.repr, value)
      for item in value:
        requireLiteralFits(name, "values entry", elementTypeOf(result.nimType),
          item)
        result.values.add(cliExprOf(item))
    of "complete":
      result.complete = cliExprOf(value)
    of "key":
      let text = cliStrLit(value, "key")
      if text.len == 0 or text.startsWith(".") or text.endsWith(".") or
          ".." in text:
        cliParamError(name, "key must be a non-empty dotted name such as " &
          "\"section.name\", got: \"" & text & "\"", value)
      result.configKey = text
      result.keyDeclared = true
      keyNode = value
    of "sources":
      result.sources = cliSourcesLit(value, name)
    of "merge":
      case cliIdentText(value).normalize
      of "replace": result.merge = cmrReplace
      of "append": result.merge = cmrAppend
      of "erroronconflict": result.merge = cmrErrorOnConflict
      else:
        result.merge = cmrCombine
        result.combine = cliExprOf(value)
    of "separator":
      result.separator = cliStrLit(value, "separator")
      if result.separator.len == 0:
        cliParamError(name, "separator must not be empty", value)
    of "implies":
      if value.kind != nnkBracket or value.len == 0:
        cliParamError(name, "implies must be a non-empty list such as " &
          "[other = value], got: " & value.repr, value)
      for item in value:
        if item.kind != nnkExprEqExpr or
            item[0].kind notin {nnkIdent, nnkSym, nnkAccQuoted}:
          cliParamError(name, "implies entries are written " &
            "<parameter> = <value>, got: " & item.repr, item)
        result.implies.add(CliImplication(param: cliIdentText(item[0]),
          value: cliExprOf(item[1])))
    of "visibility":
      result.visibility = cliVisibilityLit(value, "parameter '" & name & "'")
    of "perconvention":
      result.perConvention = parsePerConvention(value, name)
    of "persource":
      result.perSource = parsePerSource(value, name, result.kind)
      perSourceNode = value
    of "short":
      if value.kind != nnkCharLit or
          char(value.intVal) notin {'a'..'z', 'A'..'Z', '0'..'9'}:
        cliParamError(name, "short must be a letter or digit character " &
          "literal such as 'v', got: " & value.repr, value)
      result.short = char(value.intVal)
    of "optionalvalue":
      requireLiteralFits(name, "optionalValue", result.nimType, value)
      result.optionalValue = cliExprOf(value)
    of "negatable":
      result.negatable = strictBoolLit(value, name, spelled)
    of "counted":
      result.counted = strictBoolLit(value, name, spelled)
    of "required":
      # Both kinds take ``required``: a flag is optional and a positional
      # required unless it says otherwise. The value is read leniently, as
      # it always has been for flags, so no existing declaration changes
      # meaning.
      result.required = cliBoolLit(value, result.required)
      requiredNode = arg
    else:
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

  # Combinations that cannot mean anything.
  if result.default.isSet:
    requireLiteralFits(name, "default", result.nimType, defaultNode)
    if result.required and not requiredNode.isNil:
      cliParamError(name, "`default` and `required = true` are mutually " &
        "exclusive: a required parameter never takes its default",
        requiredNode)
    # A positional with a default is optional (a flag already is).
    result.required = false
  if result.optionalValue.isSet and result.required:
    cliParamError(name, "`optionalValue` and `required = true` are " &
      "mutually exclusive: a required flag always has a value",
      if requiredNode.isNil: node else: requiredNode)
  if result.keyDeclared and csFile notin result.sources:
    cliParamError(name, "`key` names a configuration-file key, but " &
      "`sources` exclude file", keyNode)
  for o in result.perSource:
    if o.source == CliSourceCli and csCli notin result.sources:
      cliParamError(name, "perSource gives a cli spelling, but `sources` " &
        "exclude cli", perSourceNode)
    if o.source != CliSourceCli and csFile notin result.sources:
      cliParamError(name, "perSource gives a key in file source '" &
        o.source & "', but `sources` exclude file", perSourceNode)
  if result.env.len > 0 and csEnv notin result.sources:
    cliParamError(name, "`env` names environment variables, but `sources` " &
      "exclude env", envNode)
  let tc = typeClassOf(result.nimType)
  if result.counted and tc notin {tcUnknown, tcInt}:
    cliParamError(name, "counted requires an integer type, not " &
      result.nimType, node)
  if result.negatable and tc notin {tcUnknown, tcBool}:
    cliParamError(name, "negatable requires bool, not " & result.nimType, node)
  if result.counted and result.negatable:
    cliParamError(name, "a counted flag cannot also be negatable", node)
  if result.counted and result.optionalValue.isSet:
    cliParamError(name, "a counted flag takes no value, so it cannot have " &
      "an optionalValue", node)
  if result.acceptsNextWord and not result.optionalValue.isSet:
    cliParamError(name, "acceptsNextWord applies to a flag with an " &
      "optionalValue (one whose value may be left out)", acceptsNextWordNode)
  if result.rest:
    if tc notin {tcUnknown, tcSeq}:
      cliParamError(name, "rest takes the rest of the command line, so " &
        "its type is a list (a seq), not " & result.nimType, restNode)
    if result.repeated:
      cliParamError(name, "rest and repeated contradict each other: a " &
        "rest positional takes the remaining words itself", restNode)
  if result.refuseFalse:
    if tc notin {tcUnknown, tcBool}:
      cliParamError(name, "refuseFalse applies to a switch (a bool), not " &
        result.nimType, refuseFalseNode)
    if result.negatable:
      cliParamError(name, "refuseFalse and negatable contradict each " &
        "other: a negatable switch takes a false value as --no-" &
        result.name, refuseFalseNode)
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

type
  CliCommandHeader = object
    ## What a ``subcmd`` / ``call`` head says about the command it opens.
    help: string
    aliases: seq[string]
    visibility: CliVisibility
    anonymous: bool
    shadowedByWord: bool
    shadowedNode: NimNode
      ## The ``shadowedByWord`` argument, for its diagnostics; nil when not
      ## given.

proc flagSpellings(param: CliParam): seq[string] =
  ## The spellings a flag answers to, for collision checks: its canonical
  ## ``--<name>``, its ``alias`` (without a trailing ``=``) and ``-<short>``.
  if param.kind != cpkFlag:
    return
  result.add("--" & (if param.longName.len > 0: param.longName
                     else: param.name))
  var alias = param.alias
  while alias.endsWith("="):
    alias.setLen(alias.len - 1)
  if alias.len > 0 and alias notin result:
    result.add(alias)
  if param.short != '\0' and ("-" & param.short) notin result:
    result.add("-" & param.short)

proc checkNewParam[P](params: seq[CliParam[P]]; param: CliParam[P];
                      label: string; node: NimNode) =
  ## ``param`` is about to join ``params`` (what its command already sees):
  ## its name, spellings and configuration key must be its own.
  let normName = nimIdentNormalize(param.name)
  let mine = flagSpellings(param)
  for other in params:
    let where = " (" & other.sourceFile & ":" & $other.sourceLine & ")"
    if nimIdentNormalize(other.name) == normName:
      cliParamError(param.name, "declared twice in " &
        label & "; the other declaration is '" & other.name &
        "'" & where, node)
    if param.kind == cpkFlag and other.kind == cpkFlag and
        param.placement == other.placement:
      if param.short != '\0' and param.short == other.short:
        cliParamError(param.name, "short '-" & param.short &
          "' is already used by '" & other.name & "' in " &
          label & where, node)
      for spelling in flagSpellings(other):
        if spelling in mine:
          cliParamError(param.name, "spelling '" & spelling &
            "' is already used by '" & other.name & "' in " &
            label & where, node)
    if param.configKey.len > 0 and param.configKey == other.configKey:
      cliParamError(param.name, "configuration key '" & param.configKey &
        "' is already used by '" & other.name & "' in " &
        label & where, node)
    for mineKey in param.sourceKeys:
      for theirs in other.sourceKeys:
        if mineKey.source == theirs.source and
            mineKey.spelling == theirs.spelling:
          cliParamError(param.name, "configuration key '" &
            mineKey.spelling & "' in file source '" & mineKey.source &
            "' is already used by '" & other.name & "' in " & label & where,
            node)

proc noteGroup(groups: var seq[CliGroup]; name, help: string; node: NimNode) =
  ## Records a ``group`` section. A group may be opened in several scopes;
  ## its help, given once or given identically, is the group's.
  for group in groups.mitems:
    if group.name == name:
      if help.len > 0:
        if group.help.len > 0 and group.help != help:
          error("clispec: group '" & name & "' is given two different " &
            "help texts (the other at " & group.sourceFile & ":" &
            $group.sourceLine & ")", node)
        group.help = help
      return
  let info = node.lineInfoObj()
  groups.add(CliGroup(name: name, help: help, sourceFile: info.filename,
    sourceLine: info.line))

proc parseCommandHeader(stmt: NimNode; isCall: bool;
                        path: seq[string]): CliCommandHeader =
  ## The named arguments of ``subcmd "<name>", ...:`` or ``call(...):``.
  ## Arguments the library does not know are ignored, as always.
  let label = cliCommandLabel(path, isRoot = false)
  result.anonymous = isCall
  let first = if isCall: 1 else: 2
  var given: seq[string] = @[]
  for i in first ..< stmt.len - 1:
    let arg = stmt[i]
    if arg.kind != nnkExprEqExpr:
      continue
    let key = cliIdentText(arg[0]).normalize
    if key in ["help", "aliases", "visibility", "shadowedbyword"]:
      if key in given:
        error("clispec: " & label & ": `" & cliIdentText(arg[0]) &
          "` is given twice", arg)
      given.add(key)
    case key
    of "help":
      result.help = cliStrLit(arg[1], "help")
    of "aliases":
      if isCall:
        error("clispec: " & label & ": the anonymous `call:` command has " &
          "no command word, so it cannot have aliases", arg)
      var items: seq[NimNode] = @[]
      if arg[1].kind == nnkBracket:
        for child in arg[1]:
          items.add(child)
      else:
        items.add(arg[1])
      if items.len == 0:
        error("clispec: " & label & ": aliases must name at least one " &
          "spelling", arg)
      for item in items:
        if item.kind notin {nnkStrLit..nnkTripleStrLit} or
            item.strVal.len == 0:
          error("clispec: " & label & ": aliases entries must be " &
            "non-empty string literals, got: " & item.repr, item)
        result.aliases.add(item.strVal)
    of "visibility":
      result.visibility = cliVisibilityLit(arg[1], label)
    of "shadowedbyword":
      if isCall:
        error("clispec: " & label & ": the anonymous `call:` command has " &
          "no command word, so no word can shadow it", arg)
      let v = arg[1]
      if v.kind != nnkIdent or ($v).normalize notin ["true", "false"]:
        error("clispec: " & label & ": shadowedByWord must be true or " &
          "false, got: " & v.repr, v)
      result.shadowedByWord = ($v).normalize == "true"
      result.shadowedNode = arg
    else:
      discard

proc nodeAt(file: string; line: int): NimNode =
  ## A node that carries only a source position, for a diagnostic about a
  ## declaration whose AST is no longer at hand.
  result = newEmptyNode()
  result.setLineInfo(file, line, 0)

type
  ScopeContext = object
    ## What every statement of one scope shares.
    isRoot: bool
    path: seq[string]
    wholeBody: NimNode
    naming: CliNaming

proc parseScopeImpl[C, P](body: NimNode; path: seq[string]; isRoot: bool;
                          parent: CliCommand[C, P]; wholeBody: NimNode;
                          header: CliCommandHeader;
                          commands: var seq[CliCommand[C, P]];
                          groups: var seq[CliGroup];
                          naming: CliNaming): CliCommand[C, P]

proc addScopeParam[C, P](cmd: var CliCommand[C, P]; stmt: NimNode;
                         group: string; ctx: ScopeContext) =
  ## Parses a parameter declaration of the scope and adds it to ``cmd``,
  ## with what only the scope knows: its placement under ``cli:``, its group,
  ## the declaring path, and its spellings in every source: the
  ## configuration keys derived from the path and the long flag, each in its
  ## source's convention with the parameter's overrides applied.
  var param = parseCliParam[P](stmt)
  if ctx.isRoot and param.kind == cpkFlag:
    param.placement = capBeforeSubcommand
  param.group = group
  param.declaredIn = ctx.path
  for o in param.perSource:
    if o.source == CliSourceCli:
      continue
    var known = false
    for s in ctx.naming.fileSources:
      if s.source == o.source:
        known = true
    if not known:
      cliParamError(param.name, "perSource names the file source '" &
        o.source & "', which the description does not declare (declare " &
        "it with convention \"" & o.source & "\" = <convention> under cli:)",
        stmt)
  let declaredKey = if param.keyDeclared: param.configKey else: ""
  if csFile notin param.sources:
    param.configKey = ""
  else:
    param.configKey = cliSourceKey(ctx.path, param.name, CliSourceFile,
      ctx.naming.fileConvention, declaredKey, param.perSource,
      param.perConvention)
    for s in ctx.naming.fileSources:
      param.sourceKeys.add(CliSourceSpelling(source: s.source,
        spelling: cliSourceKey(ctx.path, param.name, s.source, s.convention,
          declaredKey, param.perSource, param.perConvention)))
  if param.kind == cpkFlag:
    param.longName = cliSpelling(param.name, CliSourceCli,
      ctx.naming.flagConvention, param.perSource, param.perConvention)
  checkNewParam(cmd.params, param, cliCommandLabel(ctx.path, ctx.isRoot),
    stmt)
  cmd.params.add(param)

proc walkScope[C, P](cmd: var CliCommand[C, P]; stmts: NimNode;
                     group: string; ctx: ScopeContext;
                     commands: var seq[CliCommand[C, P]];
                     groups: var seq[CliGroup]; helpGiven: var bool;
                     childWords: var seq[tuple[word, owner: string]]) =
  ## Reads the statements of a scope (or of a ``group`` inside it) in
  ## source order.
  mixin parseCliCommandExtension
  for stmt in stmts:
    let head = cliCalleeName(stmt).normalize
    case head
    of "pos", "flag", "boolflag":
      addScopeParam(cmd, stmt, group, ctx)
    of "call", "subcmd":
      let isCall = head == "call"
      if stmt.len < 2 or stmt[^1].kind != nnkStmtList or
          (not isCall and stmt.len < 3):
        error("clispec: " & head & " requires " &
          (if isCall: "a body" else: "a name and a body"), stmt)
      let childName = if isCall: "" else: cliNameLit(stmt[1])
      var childPath = ctx.path
      if childName.len > 0:
        childPath.add(childName)
      let childHeader = parseCommandHeader(stmt, isCall, childPath)
      if not isCall:
        let mode = ctx.naming.commandMatching
        var shadowed = false
        for word in @[childName] & childHeader.aliases:
          for seen in childWords:
            if seen.word == word:
              error("clispec: " & cliCommandLabel(childPath) &
                ": the word '" & word & "' is already used by " &
                cliCommandLabel(ctx.path & @[seen.owner]), stmt)
            if cliSameSpelling(mode, word, seen.word):
              error("clispec: " & cliCommandLabel(childPath) &
                ": the word '" & word & "' matches '" & seen.word &
                "' of " & cliCommandLabel(ctx.path & @[seen.owner]) &
                " under commandMatching " & $mode, stmt)
          for (rule, reserved) in [(cprHelpWord, "help"),
                                   (cprVersionWord, "version")]:
            if rule in ctx.naming.parseRules and
                cliSameSpelling(mode, word, reserved):
              if not childHeader.shadowedByWord:
                error("clispec: " & cliCommandLabel(childPath) &
                  ": the word '" & word & "' asks for the " & reserved &
                  " under parsing " & $rule & ", so no subcommand can " &
                  "answer to it (unless it is declared shadowedByWord = " &
                  "true)", stmt)
              shadowed = true
          childWords.add((word, childName))
        if childHeader.shadowedByWord and not shadowed:
          error("clispec: " & cliCommandLabel(childPath) &
            ": shadowedByWord applies to a subcommand that answers to " &
            "the word help under parsing helpWord or version under " &
            "parsing versionWord, and this one answers to neither",
            childHeader.shadowedNode)
      discard parseScopeImpl[C, P](stmt[^1], childPath, false, cmd,
        ctx.wholeBody, childHeader, commands, groups, ctx.naming)
    of "group":
      if group.len > 0:
        error("clispec: group '" & group & "' cannot contain another " &
          "group", stmt)
      if stmt.len < 3 or stmt[^1].kind != nnkStmtList or
          stmt[1].kind notin {nnkStrLit..nnkTripleStrLit} or
          stmt[1].strVal.len == 0:
        error("clispec: group is written group \"<title>\"[, help = " &
          "\"<text>\"]: <declarations>", stmt)
      let title = stmt[1].strVal
      var groupHelp = ""
      for i in 2 ..< stmt.len - 1:
        let helpValue = cliNamedArg(stmt[i], "help")
        if not helpValue.isNil:
          groupHelp = cliStrLit(helpValue, "group help")
      noteGroup(groups, title, groupHelp, stmt)
      walkScope[C, P](cmd, stmt[^1], title, ctx, commands, groups, helpGiven,
        childWords)
    of "keystyle", "configschema", "convention", "flagmatching",
        "commandmatching", "parsing":
      # Read by ``parseCliModel`` before the scope is walked; valid only
      # directly under ``cli:``.
      if not ctx.isRoot or group.len > 0:
        error("clispec: " & cliCalleeName(stmt) & " describes the whole " &
          "program; write it directly under cli:", stmt)
    of "help":
      if stmt.kind notin {nnkCommand, nnkCall} or stmt.len != 2:
        error("clispec: help is written help \"<text>\"", stmt)
      if group.len > 0:
        # Inside a section the statement would read as the section's help
        # but give the command its help; the section's own help goes in its
        # head.
        error("clispec: help inside group '" & group & "' would describe " &
          cliCommandLabel(ctx.path, ctx.isRoot) & "; give the group its " &
          "help as group \"" & group & "\", help = \"<text>\":", stmt)
      if cmd.help.len > 0 or helpGiven:
        error("clispec: " & cliCommandLabel(ctx.path, ctx.isRoot) &
          " is given help " &
          "twice", stmt)
      cmd.help = cliStrLit(stmt[1], "help")
      helpGiven = true
    else:
      discard parseCliCommandExtension(cmd, stmt,
        CliScope(isRoot: ctx.isRoot, path: ctx.path,
          wholeBody: ctx.wholeBody))

proc parseScopeImpl[C, P](body: NimNode; path: seq[string]; isRoot: bool;
                          parent: CliCommand[C, P]; wholeBody: NimNode;
                          header: CliCommandHeader;
                          commands: var seq[CliCommand[C, P]];
                          groups: var seq[CliGroup];
                          naming: CliNaming): CliCommand[C, P] =
  let info = body.lineInfoObj()
  result.sourceFile = info.filename
  result.sourceLine = info.line
  result.path = path
  result.name = if path.len == 0: "" else: path[^1]
  result.params = parent.params
  result.ext = parent.ext
  result.help = header.help
  result.aliases = header.aliases
  result.visibility = header.visibility
  result.anonymous = header.anonymous
  result.shadowedByWord = header.shadowedByWord
  result.depth = if isRoot: 0 else: parent.depth + 1
  let inherited = parent.params.len
  var helpGiven = false
  # The subcommand words opened in this scope (names and aliases), each with
  # the subcommand that owns it, for the collision check.
  var childWords: seq[tuple[word, owner: string]] = @[]
  walkScope[C, P](result, body, "",
    ScopeContext(isRoot: isRoot, path: path, wholeBody: wholeBody,
      naming: naming),
    commands, groups, helpGiven, childWords)

  # ``implies`` may name any parameter the implying one's command sees once
  # its scope is complete, but not itself.
  for i in inherited ..< result.params.len:
    let param = result.params[i]
    for implication in param.implies:
      if nimIdentNormalize(implication.param) == nimIdentNormalize(param.name):
        error("clispec: parameter '" & param.name & "': implies itself",
          nodeAt(param.sourceFile, param.sourceLine))
      var found = false
      for other in result.params:
        if nimIdentNormalize(other.name) ==
            nimIdentNormalize(implication.param):
          found = true
          break
      if not found:
        error("clispec: parameter '" & param.name & "': implies '" &
          implication.param & "', which is not a parameter of " &
          cliCommandLabel(path, isRoot),
          nodeAt(param.sourceFile, param.sourceLine))
  # ``alsoSets`` names a parameter of the same command, not itself.
  for i in inherited ..< result.params.len:
    let param = result.params[i]
    var targets: seq[string] = @[]
    for a in param.alsoSets:
      if nimIdentNormalize(a.param) == nimIdentNormalize(param.name):
        error("clispec: parameter '" & param.name & "': alsoSets names " &
          "the parameter itself", nodeAt(param.sourceFile, param.sourceLine))
      if nimIdentNormalize(a.param) in targets:
        error("clispec: parameter '" & param.name & "': alsoSets names '" &
          a.param & "' twice", nodeAt(param.sourceFile, param.sourceLine))
      targets.add(nimIdentNormalize(a.param))
      var found = false
      for other in result.params:
        if nimIdentNormalize(other.name) == nimIdentNormalize(a.param):
          found = true
          break
      if not found:
        error("clispec: parameter '" & param.name & "': alsoSets names '" &
          a.param & "', which is not a parameter of " &
          cliCommandLabel(path, isRoot),
          nodeAt(param.sourceFile, param.sourceLine))
  if not isRoot:
    commands.add(result)

proc parseCliScope*[C, P](body: NimNode; path: seq[string]; isRoot: bool;
                          parent: CliCommand[C, P]; wholeBody: NimNode;
                          commands: var seq[CliCommand[C, P]];
                          groups: var seq[CliGroup];
                          naming = CliNaming()): CliCommand[C, P] =
  ## Parses one scope — the root ``cli:`` body, or a ``call:`` /
  ## ``subcmd`` body — in source order and returns its command. The scope
  ## starts from ``parent``'s parameters and extension (what the enclosing
  ## scope had declared when this one opened). Every nested scope is
  ## appended to ``commands`` after the scopes nested inside it; the root is
  ## not appended. ``group`` sections are recorded in ``groups``. Keys and
  ## long flags are spelt in the conventions of ``naming``.
  parseScopeImpl[C, P](body, path, isRoot, parent, wholeBody,
    CliCommandHeader(), commands, groups, naming)

proc parseCliScope*[C, P](body: NimNode; path: seq[string]; isRoot: bool;
                          parent: CliCommand[C, P]; wholeBody: NimNode;
                          commands: var seq[CliCommand[C, P]]):
    CliCommand[C, P] =
  ## ``parseCliScope`` for a caller that does not keep ``group`` sections.
  var groups: seq[CliGroup] = @[]
  parseCliScope[C, P](body, path, isRoot, parent, wholeBody, commands, groups)

proc parseCliModel*[C, P](body: NimNode; rootExt: C): CliModel[C, P] =
  ## Parses a whole ``cli:`` body. ``rootExt`` is the root command's
  ## extension value before any statement is read — the consumer's
  ## defaults, which every scope inherits unless a statement changes them.
  var root: CliCommand[C, P]
  root.ext = rootExt
  # The program-wide statements come first: the conventions decide every
  # key and long flag, so they must be known before any parameter is read.
  var fileSeen, cliSeen, matchingSeen, commandMatchingSeen = false
  var exactLettersNode: NimNode = nil
  for stmt in body:
    case cliCalleeName(stmt).normalize
    of "keystyle":
      # The older spelling of ``convention file = <c>``.
      if stmt.kind notin {nnkCommand, nnkCall} or stmt.len != 2:
        error("clispec: keyStyle is written keyStyle declared | " &
          "camelCase | snakeCase | kebabCase", stmt)
      if fileSeen:
        error("clispec: the convention of source 'file' is given twice " &
          "(keyStyle is convention file = ...)", stmt)
      fileSeen = true
      result.keyStyle = cliConventionLit(stmt[1], "keyStyle")
    of "convention":
      if stmt.kind notin {nnkCommand, nnkCall} or stmt.len != 2 or
          stmt[1].kind != nnkExprEqExpr:
        error("clispec: convention is written convention <source> = " &
          "<convention>, where <source> is cli, file or a file source's " &
          "name as a string", stmt)
      let target = stmt[1][0]
      let convention = cliConventionLit(stmt[1][1], "a convention")
      if target.kind in {nnkStrLit..nnkTripleStrLit}:
        let name = target.strVal
        if name.len == 0 or name in [CliSourceCli, CliSourceFile]:
          error("clispec: a named file source is a non-empty string other " &
            "than \"cli\" and \"file\", got: " & target.repr, target)
        for seen in result.fileSources:
          if seen.source == name:
            error("clispec: the convention of source '" & name &
              "' is given twice", stmt)
        result.fileSources.add(CliSourceConvention(source: name,
          convention: convention))
      elif target.kind in {nnkIdent, nnkSym, nnkAccQuoted} and
          cliIdentText(target).normalize == "cli":
        if cliSeen:
          error("clispec: the convention of source 'cli' is given twice",
            stmt)
        cliSeen = true
        result.flagConvention = convention
      elif target.kind in {nnkIdent, nnkSym, nnkAccQuoted} and
          cliIdentText(target).normalize == "file":
        if fileSeen:
          error("clispec: the convention of source 'file' is given twice " &
            "(keyStyle is convention file = ...)", stmt)
        fileSeen = true
        result.keyStyle = convention
      else:
        error("clispec: convention names the source cli, file or a file " &
          "source's name as a string (\"project\"), not " & target.repr,
          target)
    of "configschema":
      if stmt.kind notin {nnkCommand, nnkCall} or stmt.len != 2:
        error("clispec: configSchema is written configSchema \"<id>\"",
          stmt)
      if result.configSchema.len > 0:
        error("clispec: configSchema is given twice", stmt)
      result.configSchema = cliStrLit(stmt[1], "configSchema")
      if result.configSchema.len == 0:
        error("clispec: configSchema must not be empty", stmt[1])
    of "flagmatching":
      if stmt.kind notin {nnkCommand, nnkCall} or stmt.len != 2:
        error("clispec: flagMatching is written flagMatching exact | " &
          "ignoreCase | ignoreStyle", stmt)
      if matchingSeen:
        error("clispec: flagMatching is given twice", stmt)
      matchingSeen = true
      var found = false
      for m in CliFlagMatching:
        if nimIdentNormalize(cliIdentText(stmt[1])) ==
            nimIdentNormalize($m):
          result.flagMatching = m
          found = true
      if not found:
        error("clispec: flagMatching must be exact, ignoreCase or " &
          "ignoreStyle, not " & stmt[1].repr, stmt[1])
    of "commandmatching":
      if stmt.kind notin {nnkCommand, nnkCall} or stmt.len != 2:
        error("clispec: commandMatching is written commandMatching exact | " &
          "ignoreCase | ignoreStyle", stmt)
      if commandMatchingSeen:
        error("clispec: commandMatching is given twice", stmt)
      commandMatchingSeen = true
      var found = false
      for m in CliFlagMatching:
        if nimIdentNormalize(cliIdentText(stmt[1])) ==
            nimIdentNormalize($m):
          result.commandMatching = m
          found = true
      if not found:
        error("clispec: commandMatching must be exact, ignoreCase or " &
          "ignoreStyle, not " & stmt[1].repr, stmt[1])
    of "parsing":
      if stmt.kind notin {nnkCommand, nnkCall} or stmt.len < 2:
        error("clispec: parsing is written parsing <rule>, ... (" &
          "shortEquals, helpWithAnyValue, helpInCluster, " &
          "valueErrorsBeforeHelp, switchesRefuseFalse, " &
          "lenientSwitchValues, colonValues, equalsTakesNext, helpWord, " &
          "versionWord, longHelpOnly, loneDashesAreFlags, " &
          "exactOneLetterFlags)", stmt)
      for k in 1 ..< stmt.len:
        var found = false
        for r in CliParseRule:
          if stmt[k].kind in {nnkIdent, nnkSym, nnkAccQuoted} and
              nimIdentNormalize(cliIdentText(stmt[k])) ==
                nimIdentNormalize($r):
            if r in result.parseRules:
              error("clispec: parsing names " & $r & " twice", stmt[k])
            result.parseRules.incl(r)
            if r == cprExactOneLetterFlags:
              exactLettersNode = stmt[k]
            found = true
        if not found:
          error("clispec: unknown parsing rule " & stmt[k].repr &
            " (expected shortEquals, helpWithAnyValue, helpInCluster, " &
            "valueErrorsBeforeHelp, switchesRefuseFalse, " &
            "lenientSwitchValues, colonValues, equalsTakesNext, helpWord, " &
            "versionWord, longHelpOnly, loneDashesAreFlags or " &
            "exactOneLetterFlags)", stmt[k])
    else:
      discard
  if exactLettersNode != nil and result.flagMatching == cfmExact:
    error("clispec: parsing exactOneLetterFlags keeps one-letter flag " &
      "spellings exact under flagMatching ignoreCase or ignoreStyle, and " &
      "changes nothing under flagMatching exact; declare one of those " &
      "modes or drop the rule", exactLettersNode)
  result.root = parseCliScope[C, P](body, @[], true, root, body,
    result.commands, result.groups, cliNamingOf(result))

# ---------------------------------------------------------------------------
# Type checks of the expressions a model holds.
# ---------------------------------------------------------------------------

template cliAccepts*(T: typedesc; value: untyped): bool =
  ## Whether ``value`` is a valid value of ``T``. Used by the checks
  ## ``cliModelTypeChecks`` generates.
  compiles((block:
    let clispecProbe {.used.}: T = value
    clispecProbe))

template cliElementAccepts*(T: typedesc; value: untyped): bool =
  ## Whether ``value`` is a valid element of ``T`` when ``T`` is a
  ## collection (other than ``string``), else a valid ``T``. ``values``
  ## entries of a list parameter are elements, and those of an ``Option``
  ## parameter are values of the type it holds (``values = [1, 2]`` for an
  ## ``Option[int]``), which is how the generated parser checks them.
  when T is string:
    cliAccepts(T, value)
  elif T is Option:
    cliAccepts(typeof(default(T).get()), value)
  elif compiles((for clispecItem in default(T): discard)):
    cliAccepts(typeof(items(default(T)), typeOfIter), value)
  else:
    cliAccepts(T, value)

template cliIsConstString*(value: untyped): bool =
  ## Whether ``value`` is a string the compiler can evaluate at compile
  ## time. Used by the checks ``cliModelTypeChecks`` generates for ``help``
  ## and ``longHelp`` expressions.
  compiles((block:
    const clispecProbe {.used.}: string = value
    clispecProbe))

proc cliFailWhenNot*(cond: NimNode; message: string; file: string; line,
                     column: int): NimNode =
  ## ``when not cond: {.error: message.}``, reported at ``file:line``: a
  ## check a macro places in its output, for what only the compiler can
  ## decide (as ``cliModelTypeChecks`` does).
  let pragma = nnkPragma.newTree(nnkExprColonExpr.newTree(ident("error"),
    newLit(message)))
  pragma.setLineInfo(file, line, column)
  result = nnkWhenStmt.newTree(nnkElifBranch.newTree(
    nnkPrefix.newTree(ident("not"), nnkPar.newTree(cond)),
    newStmtList(pragma)))
  # ``setLineInfo`` is shallow, and the nodes built above take the line of
  # the macro invocation (or of whatever the compiler last read), which is
  # where a diagnostic about the pragma's argument would land; put the
  # whole check where the offending argument was written.
  proc setDeepLineInfo(n: NimNode) =
    n.setLineInfo(file, line, column)
    for child in n:
      setDeepLineInfo(child)
  setDeepLineInfo(result)

proc cliModelTypeChecks*[C, P](model: CliModel[C, P]): NimNode =
  ## Code that checks, where it is placed, what the parser cannot check from
  ## spellings alone: that ``default``, ``optionalValue``, ``values`` entries
  ## and ``implies`` values are values of their parameter's type, that a
  ## ``counted`` parameter is an integer, that a ``negatable`` one is a
  ## ``bool``, that a ``complete`` completer has the signature it needs.
  ## Each failing check is a compile error naming the parameter, reported
  ## where the offending argument was written. A macro that builds
  ## a model places these checks in its output, in the scope where the
  ## description's types are visible (``plainCliModel`` does). The checks
  ## call ``cliAccepts`` and ``cliElementAccepts``, so that scope must see
  ## ``clispec/dsl``.
  result = newStmtList()
  var seen: seq[string] = @[]
  var scopes = @[model.root]
  scopes.add(model.commands)
  for cmd in scopes:
    for param in cmd.params:
      let id = param.sourceFile & ":" & $param.sourceLine & ":" & param.name
      if id in seen:
        continue
      seen.add(id)
      let name = param.name
      let prefix = "clispec: parameter '" & name & "': "
      let typeNode = parseExpr(param.nimType)
      if param.default.isSet:
        let d = param.default
        result.add(cliFailWhenNot(newCall(bindSym("cliAccepts"), typeNode,
          parseExpr(d.code)), prefix & "default `" & d.code &
          "` is not a valid " & param.nimType, d.sourceFile, d.sourceLine,
          d.sourceColumn))
      if param.optionalValue.isSet:
        let o = param.optionalValue
        result.add(cliFailWhenNot(newCall(bindSym("cliAccepts"), typeNode,
          parseExpr(o.code)), prefix & "optionalValue `" & o.code &
          "` is not a valid " & param.nimType, o.sourceFile, o.sourceLine,
          o.sourceColumn))
      for v in param.values:
        result.add(cliFailWhenNot(newCall(bindSym("cliElementAccepts"),
          typeNode, parseExpr(v.code)), prefix & "values entry `" & v.code &
          "` is not a valid value of " & param.nimType, v.sourceFile,
          v.sourceLine, v.sourceColumn))
      for implication in param.implies:
        var targetType = ""
        for other in cmd.params:
          if nimIdentNormalize(other.name) ==
              nimIdentNormalize(implication.param):
            targetType = other.nimType
        if targetType.len == 0:
          continue
        let v = implication.value
        result.add(cliFailWhenNot(newCall(bindSym("cliAccepts"),
          parseExpr(targetType), parseExpr(v.code)), prefix & "implies " &
          implication.param & " = `" & v.code & "`, which is not a valid " &
          targetType & " (the type of '" & implication.param & "')",
          v.sourceFile, v.sourceLine, v.sourceColumn))
      for (what, e) in [("help", param.helpExpr),
                        ("longHelp", param.longHelpExpr)]:
        if e.isSet:
          result.add(cliFailWhenNot(newCall(bindSym("cliIsConstString"),
            parseExpr(e.code)), prefix & what & " = `" & e.code & "` is " &
            "not a constant string expression", e.sourceFile, e.sourceLine,
            e.sourceColumn))
      if param.refuseFalse:
        result.add(cliFailWhenNot(infix(typeNode, "is", ident("bool")),
          prefix & "refuseFalse applies to a switch (a bool), not " &
          param.nimType, param.sourceFile, param.sourceLine, 0))
      if param.counted:
        result.add(cliFailWhenNot(infix(typeNode, "is", ident("SomeInteger")),
          prefix & "counted requires an integer type, not " & param.nimType,
          param.sourceFile, param.sourceLine, 0))
      if param.rest:
        result.add(cliFailWhenNot(infix(typeNode, "is", ident("seq")),
          prefix & "rest takes the rest of the command line, so its type " &
          "is a list (a seq), not " & param.nimType, param.sourceFile,
          param.sourceLine, 0))
      if param.negatable:
        result.add(cliFailWhenNot(infix(typeNode, "is", ident("bool")),
          prefix & "negatable requires bool, not " & param.nimType,
          param.sourceFile, param.sourceLine, 0))
      if param.merge == cmrAppend and not param.counted:
        result.add(cliFailWhenNot(infix(typeNode, "is", ident("seq")),
          prefix & "merge = append concatenates lists; " & param.nimType &
          " is not a seq", param.sourceFile, param.sourceLine, 0))
      if param.complete.isSet:
        let c = param.complete
        result.add(cliFailWhenNot(newCall(bindSym("cliCompleterFits"),
          parseExpr(c.code)), prefix & "complete = `" & c.code & "` is " &
          "not a completer; it must be a CliCompleter: proc (ctx: " &
          "CliCompletionContext): seq[CliCompletion]", c.sourceFile,
          c.sourceLine, c.sourceColumn))

proc cliModelValue*[C, P](model: CliModel[C, P]): NimNode =
  ## An expression whose value is ``model`` with every ``help`` and
  ## ``longHelp`` written as a constant expression evaluated: ``newLit``
  ## of the model, then an assignment of each ``helpExpr`` /
  ## ``longHelpExpr`` to its text. Place it where the description's
  ## constants are visible (a ``const`` at the description's scope). With no
  ## such expression it is just ``newLit(model)``.
  var assigns: seq[NimNode] = @[]
  let m = genSym(nskVar, "model")
  proc fill(scope: NimNode; params: seq[CliParam[P]]) =
    for j, p in params:
      let slot = nnkBracketExpr.newTree(newDotExpr(scope, ident("params")),
        newLit(j))
      for (field, e) in [("help", p.helpExpr), ("longHelp", p.longHelpExpr)]:
        if e.isSet:
          let value = parseExpr(e.code)
          value.setLineInfo(e.sourceFile, e.sourceLine, e.sourceColumn)
          assigns.add(newAssignment(newDotExpr(slot.copyNimTree,
            ident(field)), value))
  fill(newDotExpr(m, ident("root")), model.root.params)
  for k, cmd in model.commands:
    fill(nnkBracketExpr.newTree(newDotExpr(m, ident("commands")), newLit(k)),
      cmd.params)
  if assigns.len == 0:
    return newLit(model)
  var body = newStmtList(newVarStmt(m, newLit(model)))
  for a in assigns:
    body.add(a)
  body.add(m)
  nnkBlockStmt.newTree(newEmptyNode(), body)

macro plainCliModel*(body: untyped): untyped =
  ## The model of a ``cli:`` body with no extension, as a constant, after
  ## the type checks of ``cliModelTypeChecks``:
  ##
  ## .. code-block:: nim
  ##   const model = plainCliModel:
  ##     subcmd "run":
  ##       pos script is string
  let model = parseCliModel[NoCliExtension, NoCliExtension](body,
    NoCliExtension())
  let checks = cliModelTypeChecks(model)
  if checks.len == 0:
    result = cliModelValue(model)
  else:
    result = nnkStmtListExpr.newTree()
    for check in checks:
      result.add(check)
    result.add(cliModelValue(model))

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
  ##     help "Options every command takes"
  ##     boolFlag verbose is bool, alias = "-v"
  ##
  ## When the body starts with a ``help "<text>"`` statement, the group is
  ## also a help section: its declarations come back wrapped in one
  ## ``group "<template name>", help = "<text>":`` statement, so the
  ## parameters it declares carry the group in the model. A group without
  ## ``help`` expands to its bare declarations.
  if node.kind != nnkTemplateDef:
    error("CLI parameter group must be a template definition", node)
  result.name = cliIdentText(node[0]).normalize
  if node[3].kind != nnkFormalParams or node[3].len != 1:
    error("CLI parameter group templates must not accept parameters", node[3])
  let body = node[^1]
  if body.kind != nnkStmtList:
    error("CLI parameter group template must contain a statement body", body)
  var first = 0
  var help = ""
  if body.len > 0 and cliCalleeName(body[0]).normalize == "help":
    if body[0].len != 2:
      error("clispec: help is written help \"<text>\"", body[0])
    help = cliStrLit(body[0][1], "group help")
    first = 1
  if help.len == 0:
    for stmt in body:
      result.statements.add(stmt)
  else:
    var inner = newStmtList()
    for i in first ..< body.len:
      inner.add(body[i])
    let wrapper = nnkCommand.newTree(ident("group"),
      newLit(cliIdentText(node[0])),
      nnkExprEqExpr.newTree(ident("help"), newLit(help)), inner)
    wrapper.copyLineInfo(body[0])
    result.statements.add(wrapper)

proc expandCliParamGroups*(stmt: NimNode; groups: CliParamGroups;
                           stack: var seq[string]): seq[NimNode] =
  ## ``stmt`` itself, or — when it names a group (``commonFlags()``) — the
  ## group's statements, with nested groups expanded (inside a ``group``
  ## section too). ``stack`` holds the groups being expanded, so a group
  ## that includes itself is a compile error instead of an endless
  ## expansion.
  let groupName = cliCalleeName(stmt).normalize
  if groupName.len > 0 and groups.hasKey(groupName) and stmt.len == 1:
    if stack.find(groupName) >= 0:
      error("recursive CLI parameter group: " & groupName, stmt)
    stack.add(groupName)
    for groupedStmt in groups[groupName]:
      for expandedStmt in expandCliParamGroups(groupedStmt, groups, stack):
        result.add(expandedStmt)
    discard stack.pop()
  elif groupName == "group" and stmt.len >= 3 and
      stmt[^1].kind == nnkStmtList:
    var copy = stmt.copyNimNode()
    for i in 0 ..< stmt.len - 1:
      copy.add(stmt[i])
    var body = newStmtList()
    for inner in stmt[^1]:
      for expandedStmt in expandCliParamGroups(inner, groups, stack):
        body.add(expandedStmt)
    copy.add(body)
    result.add(copy)
  else:
    result.add(stmt)
