## The grammar: the run-time tables a parser, a help renderer and a
## completion engine read.
##
## ``cliGrammarOf`` derives a ``CliGrammar`` from a model at compile time.
## The grammar is the model reshaped for use rather than for description:
##
## * every parameter appears once, in ``CliGrammar.params``, however many
##   commands inherit it, so its index (its *parameter id*) identifies it
##   across the tree;
## * commands form an explicit tree (``parent``, ``children``,
##   ``callChild``), with the root at index 0;
## * the facts only the compiler knows (whether a parameter's type is
##   ``bool``, a ``seq``, which texts its closed value set accepts) are
##   filled in by the code ``clispec/program`` generates, where the types are
##   visible.
##
## It is a plain value with no generic parameters and no extension data, so
## a program keeps it as a constant and the parser, help and completion are
## ordinary, non-generic procedures over it.
##
## Rules the grammar adds to the model
## ===================================
##
## A program's own command line must be unambiguous to parse, which is more
## than a description of an external tool needs. ``cliGrammarOf`` reports,
## as problems for the generator to turn into compile errors:
##
## * a positional declared directly in a command that has subcommands (the
##   word after such a command is read as a subcommand word, so its
##   positionals belong in its ``call:``);
## * a ``subcmd`` inside a ``call:``, and two ``call:`` scopes in one command;
## * more than one list-valued (``repeated``) positional in one command;
## * a ``rest`` positional that is not the last positional of its command,
##   or that follows a ``repeated`` one;
## * an ``afterSeparator`` positional that is not the last positional of
##   its command (so a command has at most one, and none beside a ``rest``
##   one), or one declared under ``parsing loneDashesAreFlags``, where
##   ``--`` ends nothing and so nothing could fill it;
## * under ``commandMatching``, two subcommands of one command whose words
##   match each other in that mode (``clispec/dsl`` reports it for every
##   model; repeated here for a model built by hand).

import std/[algorithm, json, strutils]

import ./model

export cliSameSpelling

type
  CliGrammarParam* = object
    ## One parameter, as the parser sees it.
    name*: string
    longName*: string
      ## The long flag without ``--``, in the command line's convention with
      ## the parameter's overrides applied (``CliParam.longName``); empty
      ## for a positional.
    nimType*: string
    kind*: CliParamKind
    format*: CliArgFormat
    alias*: string
      ## The declared spelling with any trailing ``=`` removed, or empty.
    short*: char
    required*: bool
    repeated*: bool
    position*: int
    rest*: bool
      ## ``rest = true``: the rest of the command line (``CliParam.rest``).
    afterSeparator*: bool
      ## ``afterSeparator = true``: the words after ``--``
      ## (``CliParam.afterSeparator``).
    negatable*: bool
    counted*: bool
    hasOptionalValue*: bool
    separator*: string
    help*: string
    longHelp*: string
      ## Further paragraphs of description, one per line (``longHelp``).
    placeholder*: string
      ## The declared ``valueName``, or empty (help then shows the closed
      ## value set or the type's name; see ``cliPlaceholder``).
    acceptsNextWord*: bool
      ## ``acceptsNextWord = true``.
    refuseFalse*: bool
      ## ``refuseFalse = true``. Whether a switch refuses a false value is
      ## ``cliRefusesFalse``, which also reads the program's
      ## ``switchesRefuseFalse``.
    alsoSets*: seq[CliGrammarAlsoSet]
      ## ``alsoSets``, resolved to parameter ids, in declaration order.
    group*: string
    visibility*: CliVisibility
    env*: seq[string]
    configKey*: string
      ## The key in the ``file`` source.
    sourceKeys*: seq[CliSourceSpelling]
      ## The key in each named file source (``CliParam.sourceKeys``).
    sources*: set[CliSource]
    merge*: CliMergeRule
    hasDefault*: bool
    defaultText*: string
      ## The ``default`` as written, for help (a string literal unquoted).
    defaultIsText*: bool
      ## The ``default`` is a string literal (help quotes it when it is
      ## empty or holds white space).
    hasCompleter*: bool
    completer*: string
      ## The ``complete`` expression as written (the completer's name or
      ## call), or empty.
    declaredIn*: seq[string]
    declaredBy*: int
      ## The index of the command (in ``CliGrammar.commands``) that declares
      ## the parameter.
    implies*: seq[int]
      ## The parameter ids of this parameter's ``implies`` targets, in
      ## declaration order.
    impliesText*: seq[string]
      ## The values of those implications, as written.
    isSwitch*: bool
      ## The type is ``bool``: the flag takes no value of its own (filled in
      ## by the generated code).
    isList*: bool
      ## The type is a ``seq``: occurrences collect (generated code).
    valueName*: string
      ## The placeholder help shows for the value (``int``, ``a|b|c``).
    choices*: seq[string]
      ## The closed value set as the parser accepts it: the ``values``
      ## entries, or every value of an enum type (generated code). Empty when
      ## the set is open.
    configType*: CliConfigType
      ## The type its configuration-file value (each element, for a list)
      ## must have (generated code; ``cctInteger`` for a counted flag).

  CliGrammarAlsoSet* = object
    ## One ``alsoSets`` entry, resolved: the parameter id that also receives
    ## a value, and the value as command-line text.
    id*: int
    text*: string

  CliGrammarCommand* = object
    ## One command: the root, a ``subcmd`` or a ``call:``.
    name*: string
    path*: seq[string]
    aliases*: seq[string]
    help*: string
    longHelp*: string
      ## ``CliCommand.longHelp``: the long help's further paragraphs.
    examples*: seq[CliExample]
      ## ``CliCommand.examples``, in declaration order.
    visibility*: CliVisibility
    shadowedByWord*: bool
      ## ``CliCommand.shadowedByWord``: a word a ``parsing`` rule reserves
      ## answers to it, and the rule wins.
    isCall*: bool
    parent*: int
      ## The enclosing command, -1 for the root.
    children*: seq[int]
      ## The ``subcmd`` children, in declaration order.
    callChild*: int
      ## The ``call:`` child, or -1.
    params*: seq[int]
      ## Every parameter the command accepts (inherited ones first), in
      ## declaration order.
    ownParams*: seq[int]
      ## The parameters the command itself declares.
    sourceFile*: string
    sourceLine*: int

  CliGrammar* = object
    ## A whole command tree.
    program*: string
      ## The name help and errors use for the program.
    params*: seq[CliGrammarParam]
    commands*: seq[CliGrammarCommand]
      ## Index 0 is the root.
    groups*: seq[CliGroup]
    configSchema*: string
      ## The identifier configuration files must declare in their
      ## ``schema`` string (``CliModel.configSchema``).
    keyStyle*: CliConvention
      ## The ``file`` source's convention (``CliModel.keyStyle``).
    flagConvention*: CliConvention
      ## The long flags' convention (``CliModel.flagConvention``).
    fileSources*: seq[CliSourceConvention]
      ## The named file sources and their conventions.
    flagMatching*: CliFlagMatching
      ## How words are compared with flag spellings
      ## (``CliModel.flagMatching``).
    commandMatching*: CliFlagMatching
      ## How words are compared with subcommand names and aliases
      ## (``CliModel.commandMatching``).
    parseRules*: set[CliParseRule]
      ## The opt-in command-line rules (``CliModel.parseRules``).

  CliGrammarProblem* = object
    ## A description that is a valid model but not a parseable program.
    message*: string
    sourceFile*: string
    sourceLine*: int

func displayDefault(e: CliExpr): string =
  ## A default as help shows it: a string literal without its quotes,
  ## anything else as written.
  let code = e.code
  if code.len >= 2 and code[0] == '"' and code[^1] == '"':
    try:
      result = unescape(code)
    except ValueError:
      result = code
  else:
    result = code

func stripAlias(alias: string): string =
  result = alias
  while result.endsWith("="):
    result.setLen(result.len - 1)

func sameParam[P](a, b: CliParam[P]): bool =
  a.name == b.name and a.sourceFile == b.sourceFile and
    a.sourceLine == b.sourceLine and a.declaredIn == b.declaredIn

func toGrammarParam[P](p: CliParam[P]; declaredBy: int): CliGrammarParam =
  let longName = if p.kind != cpkFlag: ""
                 elif p.longName.len > 0: p.longName
                 else: p.name
  result = CliGrammarParam(name: p.name, longName: longName,
    nimType: p.nimType, kind: p.kind,
    format: p.format, alias: stripAlias(p.alias), short: p.short,
    required: p.required, repeated: p.repeated, position: p.position,
    rest: p.rest, afterSeparator: p.afterSeparator,
    negatable: p.negatable, counted: p.counted,
    hasOptionalValue: p.optionalValue.isSet, separator: p.separator,
    help: p.help, longHelp: p.longHelp, placeholder: p.valueName,
    acceptsNextWord: p.acceptsNextWord, refuseFalse: p.refuseFalse,
    group: p.group, visibility: p.visibility, env: p.env,
    configKey: p.configKey, sourceKeys: p.sourceKeys, sources: p.sources,
    merge: p.merge,
    hasDefault: p.default.isSet, defaultText: displayDefault(p.default),
    defaultIsText: p.default.code.len >= 2 and p.default.code[0] == '"',
    hasCompleter: p.complete.isSet,
    completer: (if p.complete.isSet: p.complete.code else: ""),
    declaredIn: p.declaredIn,
    declaredBy: declaredBy, valueName: p.nimType)

func cliPositionals*(g: CliGrammar; command: int): seq[int] =
  ## The positional parameters of a command, in the order they are filled:
  ## by ``position``, then by declaration. A positional whose ``sources``
  ## exclude the command line takes no word and is left out.
  var items: seq[tuple[position, order, id: int]] = @[]
  for order, id in g.commands[command].params:
    if g.params[id].kind == cpkPositional and csCli in g.params[id].sources:
      items.add((g.params[id].position, order, id))
  items.sort(proc (a, b: tuple[position, order, id: int]): int =
    result = cmp(a.position, b.position)
    if result == 0:
      result = cmp(a.order, b.order))
  for item in items:
    result.add(item.id)

func cliAfterSeparatorParam*(g: CliGrammar; command: int): int =
  ## The ``afterSeparator`` positional of ``command``: the one the words
  ## after its ``--`` fill. -1 when it has none.
  for id in cliPositionals(g, command):
    if g.params[id].afterSeparator:
      return id
  -1

func cliWordPositionals*(g: CliGrammar; command: int): seq[int] =
  ## The positionals of ``command`` that the words before its ``--`` (and,
  ## without an ``afterSeparator`` positional, after it too) fill, in
  ## ``cliPositionals`` order: every one but the ``afterSeparator`` one.
  for id in cliPositionals(g, command):
    if not g.params[id].afterSeparator:
      result.add(id)

func cliRestParam*(g: CliGrammar; command: int): tuple[id, index: int] =
  ## The ``rest`` positional of ``command`` and its index among the
  ## command's positionals (``cliPositionals``), or ``(-1, -1)``.
  for index, id in cliPositionals(g, command):
    if g.params[id].rest:
      return (id, index)
  (-1, -1)

proc cliGrammarOf*[C, P](model: CliModel[C, P]; program: string;
                         problems: var seq[CliGrammarProblem];
                         declarations: var seq[CliParam[P]]): CliGrammar =
  ## The grammar of ``model``. What makes the model unparseable as a
  ## program's own command line is appended to ``problems`` (see the module
  ## documentation); the grammar returned then is incomplete.
  ## ``declarations[id]`` is set to the model's declaration of parameter
  ## ``id``, for a generator that needs its expressions.
  result.program = program
  result.groups = model.groups
  result.configSchema = model.configSchema
  result.keyStyle = model.keyStyle
  result.flagConvention = model.flagConvention
  result.fileSources = model.fileSources
  result.flagMatching = model.flagMatching
  result.commandMatching = model.commandMatching
  result.parseRules = model.parseRules
  # The model lists the scopes in post-order: each one after the scopes
  # nested inside it. Rebuild the tree with a stack: when a scope arrives,
  # the scopes directly inside it are the run of entries on top of the stack
  # one level deeper that have the shape of its children (a named scope one
  # word deeper, or a call: at the same path).
  let rootSlot = model.commands.len
  var kids = newSeq[seq[int]](model.commands.len + 1)
  var stack: seq[int] = @[]
  proc isChildOf(child, parent: CliCommand[C, P]): bool =
    if child.depth != parent.depth + 1:
      false
    elif child.anonymous:
      child.path == parent.path
    else:
      child.path.len == parent.path.len + 1 and
        child.path[0 ..< ^1] == parent.path
  for i, cmd in model.commands:
    var mine: seq[int] = @[]
    while stack.len > 0 and isChildOf(model.commands[stack[^1]], cmd):
      mine.add(stack.pop())
    mine.reverse()
    kids[i] = mine
    stack.add(i)
  kids[rootSlot] = stack
  # Lay the tree out in pre-order, so the root is at 0 and every parent
  # precedes its children. ``scopes[k]`` is the model scope at index ``k``.
  var scopes: seq[CliCommand[C, P]] = @[]
  proc place(g: var CliGrammar; slot, parent: int;
             scopes: var seq[CliCommand[C, P]];
             problems: var seq[CliGrammarProblem]) =
    let cmd = if slot == rootSlot: model.root else: model.commands[slot]
    let index = g.commands.len
    if parent >= 0:
      if g.commands[parent].isCall:
        problems.add(CliGrammarProblem(message: "clispec: command '" &
          cmd.path.join(" ") & "' is declared inside a call: scope; a " &
          "call: is what runs when no subcommand word is given, so it " &
          "cannot have subcommands of its own",
          sourceFile: cmd.sourceFile, sourceLine: cmd.sourceLine))
        return
      if cmd.anonymous:
        if g.commands[parent].callChild >= 0:
          problems.add(CliGrammarProblem(message: "clispec: " &
            (if cmd.path.len == 0: "the root command"
             else: "command '" & cmd.path.join(" ") & "'") &
            " has two call: scopes", sourceFile: cmd.sourceFile,
            sourceLine: cmd.sourceLine))
          return
        g.commands[parent].callChild = index
      else:
        g.commands[parent].children.add(index)
    g.commands.add(CliGrammarCommand(name: cmd.name, path: cmd.path,
      aliases: cmd.aliases, help: cmd.help, longHelp: cmd.longHelp,
      examples: cmd.examples, visibility: cmd.visibility,
      shadowedByWord: cmd.shadowedByWord, isCall: cmd.anonymous,
      parent: parent, callChild: -1,
      sourceFile: cmd.sourceFile, sourceLine: cmd.sourceLine))
    scopes.add(cmd)
    for kid in kids[slot]:
      place(g, kid, index, scopes, problems)
  place(result, rootSlot, -1, scopes, problems)
  # Parameters: a scope's list starts with what it inherited (a prefix of
  # its parent's final list) and continues with its own.
  for k in 0 ..< result.commands.len:
    let scope = scopes[k]
    let parent = result.commands[k].parent
    var inherited = 0
    if parent >= 0:
      let parentScope = scopes[parent]
      while inherited < scope.params.len and
          inherited < parentScope.params.len and
          sameParam(scope.params[inherited], parentScope.params[inherited]):
        inc inherited
    for j in 0 ..< scope.params.len:
      if j < inherited:
        result.commands[k].params.add(result.commands[parent].params[j])
      else:
        let id = result.params.len
        result.params.add(toGrammarParam(scope.params[j], k))
        declarations.add(scope.params[j])
        result.commands[k].params.add(id)
        result.commands[k].ownParams.add(id)
  # Implications name a parameter of the declaring scope.
  for k in 0 ..< result.commands.len:
    let scope = scopes[k]
    for j, p in scope.params:
      let id = result.commands[k].params[j]
      if result.params[id].declaredBy != k:
        continue
      for implication in p.implies:
        for jj, other in scope.params:
          if nimIdentNormalize(other.name) ==
              nimIdentNormalize(implication.param):
            result.params[id].implies.add(result.commands[k].params[jj])
            result.params[id].impliesText.add(implication.value.code)
            break
      for a in p.alsoSets:
        for jj, other in scope.params:
          if nimIdentNormalize(other.name) == nimIdentNormalize(a.param):
            result.params[id].alsoSets.add(CliGrammarAlsoSet(
              id: result.commands[k].params[jj], text: a.text))
            break
  # Rules for parsing a program's own command line.
  for k, cmd in result.commands:
    let label = if cmd.path.len == 0 and not cmd.isCall: "the root command"
                elif cmd.isCall: "the call: of " &
                  (if cmd.path.len == 0: "the root command"
                   else: "command '" & cmd.path.join(" ") & "'")
                else: "command '" & cmd.path.join(" ") & "'"
    var lists = 0
    var repeatedSeen, restSeen = false
    var afterSeparatorSeen = ""
    for id in cliPositionals(result, k):
      let p = result.params[id]
      if restSeen:
        problems.add(CliGrammarProblem(message: "clispec: parameter '" &
          p.name & "': " & label & " takes the rest of the command line " &
          "in an earlier positional, so no positional can follow it",
          sourceFile: cmd.sourceFile, sourceLine: cmd.sourceLine))
      if afterSeparatorSeen.len > 0 and p.afterSeparator:
        problems.add(CliGrammarProblem(message: "clispec: parameter '" &
          p.name & "': " & label & " has two afterSeparator positionals ('" &
          afterSeparatorSeen & "' and '" & p.name & "'); the words after " &
          "-- fill one", sourceFile: cmd.sourceFile,
          sourceLine: cmd.sourceLine))
      elif afterSeparatorSeen.len > 0:
        # The words after ``--`` are the afterSeparator positional's alone,
        # so a positional after it could only take words from before
        # ``--``, which help (``[<a>] [-- <b>...] [<c>]``) would misstate.
        problems.add(CliGrammarProblem(message: "clispec: parameter '" &
          p.name & "': " & label & " gives the words after -- to '" &
          afterSeparatorSeen & "' (afterSeparator), which must be its " &
          "last positional", sourceFile: cmd.sourceFile,
          sourceLine: cmd.sourceLine))
      if p.afterSeparator:
        if afterSeparatorSeen.len == 0:
          afterSeparatorSeen = p.name
        if cprLoneDashesAreFlags in result.parseRules:
          problems.add(CliGrammarProblem(message: "clispec: parameter '" &
            p.name & "': afterSeparator takes the words after --, but " &
            "under parsing loneDashesAreFlags -- is an unknown flag, so " &
            "nothing could fill it", sourceFile: cmd.sourceFile,
            sourceLine: cmd.sourceLine))
      if p.rest:
        if repeatedSeen:
          problems.add(CliGrammarProblem(message: "clispec: parameter '" &
            p.name & "': a rest positional cannot follow a repeated one " &
            "in " & label & ", which would never stop taking words",
            sourceFile: cmd.sourceFile, sourceLine: cmd.sourceLine))
        restSeen = true
      if p.repeated:
        repeatedSeen = true
    for child in cmd.children:
      if result.commandMatching == cfmExact:
        break
      for other in cmd.children:
        if other >= child:
          break
        let a = result.commands[child]
        let b = result.commands[other]
        for wa in @[a.name] & a.aliases:
          for wb in @[b.name] & b.aliases:
            if cliSameSpelling(result.commandMatching, wa, wb):
              problems.add(CliGrammarProblem(message: "clispec: command '" &
                a.path.join(" ") & "': the word '" & wa & "' matches '" &
                wb & "' of command '" & b.path.join(" ") & "' under " &
                "commandMatching " & $result.commandMatching,
                sourceFile: a.sourceFile, sourceLine: a.sourceLine))
    for id in cmd.params:
      let p = result.params[id]
      if p.kind != cpkPositional:
        continue
      if cmd.children.len > 0 and p.declaredBy == k:
        problems.add(CliGrammarProblem(message: "clispec: parameter '" &
          p.name & "': " & label & " has subcommands, so the word after it " &
          "is read as a subcommand word; declare its positionals in its " &
          "call: scope", sourceFile: cmd.sourceFile,
          sourceLine: cmd.sourceLine))
      if p.repeated:
        inc lists
    if lists > 1:
      problems.add(CliGrammarProblem(message: "clispec: " & label &
        " has more than one repeated positional, so the words cannot be " &
        "divided between them", sourceFile: cmd.sourceFile,
        sourceLine: cmd.sourceLine))

proc cliGrammarOf*[C, P](model: CliModel[C, P]; program: string;
                         problems: var seq[CliGrammarProblem]): CliGrammar =
  ## ``cliGrammarOf`` for a caller that does not need the declarations.
  var declarations: seq[CliParam[P]] = @[]
  cliGrammarOf(model, program, problems, declarations)

func cliChildNamed*(g: CliGrammar; command: int; word: string): int =
  ## The subcommand of ``command`` that answers to ``word`` (its name or one
  ## of its aliases), or -1. A word that matches exactly wins; under a
  ## ``commandMatching`` other than ``exact``, one that matches in that mode
  ## is accepted when none does. A subcommand declared ``shadowedByWord``
  ## is found by every word it answers to: the help path lookup
  ## (``cliCommandAt``) reaches it by its name; only the parser and
  ## completion put the reserved word's request first.
  for child in g.commands[command].children:
    let c = g.commands[child]
    if c.name == word or word in c.aliases:
      return child
  if g.commandMatching != cfmExact:
    for child in g.commands[command].children:
      let c = g.commands[child]
      for w in @[c.name] & c.aliases:
        if cliSameSpelling(g.commandMatching, word, w):
          return child
  -1

func cliSubcommandWords*(g: CliGrammar; command: int): seq[string] =
  ## The names of the subcommands of ``command`` that are advertised in
  ## messages: ``shown`` ones only (hidden and internal subcommands are
  ## accepted but not offered).
  for child in g.commands[command].children:
    if g.commands[child].visibility == cvShown:
      result.add(g.commands[child].name)

func cliCommandAt*(g: CliGrammar; words: openArray[string]): int =
  ## The command reached by following subcommand words (names or aliases)
  ## from the root, or -1 when a word names no subcommand.
  result = 0
  for word in words:
    result = cliChildNamed(g, result, word)
    if result < 0:
      return -1

func cliLongName*(p: CliGrammarParam): string =
  ## The long flag without ``--``: ``longName``, or ``name`` for a grammar
  ## built by hand without one.
  if p.longName.len > 0: p.longName else: p.name

func cliFlagSpellings*(p: CliGrammarParam): seq[string] =
  ## The spellings a flag answers to, the canonical one first:
  ## ``--<longName>``, then its ``alias`` and ``-<short>`` when they differ.
  if p.kind != cpkFlag:
    return
  result.add("--" & cliLongName(p))
  if p.alias.len > 0 and p.alias notin result:
    result.add(p.alias)
  if p.short != '\0' and ("-" & p.short) notin result:
    result.add("-" & p.short)

func cliDisplayName*(p: CliGrammarParam): string =
  ## How messages name a parameter: ``--<longName>`` for a flag, ``<name>``
  ## for a positional.
  if p.kind == cpkFlag: "--" & cliLongName(p) else: "<" & p.name & ">"

func cliSourceKeyOf*(p: CliGrammarParam; source: string): string =
  ## The parameter's configuration key in the file source ``source``: a
  ## named source's key when the description declares that source, else
  ## the ``file`` source's (``configKey``). Empty when files cannot supply
  ## it.
  for k in p.sourceKeys:
    if k.source == source:
      return k.spelling
  p.configKey

func cliHasFileSource*(g: CliGrammar; source: string): bool =
  ## Whether the description declares the named file source ``source``.
  for s in g.fileSources:
    if s.source == source:
      return true
  false

func cliFileSourceConvention*(g: CliGrammar; source: string): CliConvention =
  ## The convention of the file source ``source``: a named one's, else the
  ## ``file`` source's.
  for s in g.fileSources:
    if s.source == source:
      return s.convention
  g.keyStyle

func cliConfigKeysJson*(p: CliGrammarParam): JsonNode =
  ## ``{"file": "<key>", "<named source>": "<key>", ...}``: the parameter's
  ## configuration key in every file source, ``file`` first, then the named
  ## ones in declaration order; ``{}`` when files cannot supply it.
  result = newJObject()
  if p.configKey.len == 0 or csFile notin p.sources:
    return
  result[CliSourceFile] = %p.configKey
  for k in p.sourceKeys:
    result[k.source] = %k.spelling

func cliConventionsJson*(g: CliGrammar): JsonNode =
  ## ``{"cli": "<convention>", "file": "<convention>", "<named source>":
  ## "<convention>", ...}``: the convention of every source the description
  ## knows.
  result = newJObject()
  result[CliSourceCli] = %($g.flagConvention)
  result[CliSourceFile] = %($g.keyStyle)
  for s in g.fileSources:
    result[s.source] = %($s.convention)

func cliRefusesFalse*(g: CliGrammar; p: CliGrammarParam): bool =
  ## Whether the switch ``p`` refuses an explicit false value on the command
  ## line: its own ``refuseFalse``, or every switch's under the program's
  ## ``switchesRefuseFalse``.
  p.isSwitch and (p.refuseFalse or cprSwitchesRefuseFalse in g.parseRules)

func cliStartsWithSpelling*(mode: CliFlagMatching; word, prefix: string):
    bool =
  ## Whether ``word`` starts with ``prefix`` under the matching mode
  ## ``mode``: the prefix of a word being completed, compared as a whole
  ## word would be (``LI`` and ``l_i`` start ``list`` under
  ## ``ignoreStyle``).
  case mode
  of cfmExact:
    word.startsWith(prefix)
  of cfmIgnoreCase:
    word.toLowerAscii.startsWith(prefix.toLowerAscii)
  of cfmIgnoreStyle:
    normalize(word).startsWith(normalize(prefix))

func cliSameLetter*(mode: CliFlagMatching; a, b: char): bool =
  ## Whether two short-flag letters are the same under ``mode``.
  if mode == cfmExact: a == b
  else: toLowerAscii(a) == toLowerAscii(b)
