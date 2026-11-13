## The argv parser: from words to the values each parameter receives.
##
## Parsing runs in phases, each a separate procedure so that later layers
## (configuration files and the environment, completion) reuse the ones
## they need:
##
## 1. ``cliTokenize`` walks argv against a ``CliGrammar``: it dispatches
##    subcommands, recognises every flag spelling and collects, for each
##    parameter, the *candidates* the command line supplies, each with the
##    argv index and the spelling it came from.
## 2. ``cliMerge`` decides, for each parameter, which candidates win. Only
##    the command line is a source so far, so a list keeps every occurrence
##    and anything else keeps its last.
## 3. ``cliDecide`` settles what each parameter of the selected commands
##    gets: its merged candidates, a value implied by another parameter, its
##    default, or nothing, and reports a required parameter that got nothing.
## 4. The code ``clispec/program`` generates converts the decisions into the
##    typed configuration object (``cliConvert``, which also checks a
##    ``values`` set).
##
## Command-line conventions
## ========================
##
## * ``--name`` is every flag's canonical spelling; ``alias`` adds one and
##   ``short`` adds ``-x``.
## * A flag that takes a value, written with a ``--`` spelling, always
##   accepts ``--flag=value``. With ``format = separate`` (the default) it
##   also takes the next word as its value, whatever that word looks like;
##   with ``format = equals`` it never does, and with ``format = concat`` the
##   value follows its spelling directly (``-lm``).
## * A ``short`` spelling follows POSIX ``getopt``: ``-j 4`` or ``-j4``, and
##   switches cluster (``-vvq``); in a cluster, a letter that takes a value
##   takes the rest of the word, or the next word when it is last.
## * A ``bool`` parameter is a switch: bare it means ``true``,
##   ``--flag=false`` is accepted too, and ``negatable = true`` adds
##   ``--no-<name>``.
## * ``counted = true``: each occurrence (``-v``, ``-vv``) adds one.
## * ``optionalValue``: bare, the flag takes that value; ``--flag=value``
##   gives another. It never takes the next word.
## * A list parameter (a ``seq``) collects every occurrence, and with a
##   ``separator`` each occurrence is split on it.
## * ``--`` ends the flags: every later word is a positional.
## * The first bare word after a command that has subcommands names one (or
##   one of its ``aliases``). When the command also has a ``call:``, a word
##   that names no subcommand, or a flag (or a cluster of short flags) only
##   the ``call:`` declares, runs the ``call:`` instead.
## * Positionals fill in ``position`` order; a list positional takes every
##   word the positionals declared after it do not need.
## * ``--help`` and ``-h`` request help (``--help=json`` the machine-readable
##   form) unless the program turns them off or declares those spellings
##   itself.

import std/[options, strutils]

import ./[model, grammar, errors, values, help]

export errors, values

type
  CliOptions* = object
    ## How a program wants its command line parsed.
    program*: string
      ## The program's name in help and errors; empty means the name its
      ## description was given.
    usageExitCode*: int
      ## The exit code a usage error carries (``DefaultUsageExitCode``, 2,
      ## when zero).
    disableHelpFlag*: bool
      ## Do not treat ``--help`` / ``-h`` as a request for help.

  CliCandidateForm* = enum
    ## How a candidate was written.
    ccfValue    ## with a value: ``--jobs 4``, ``--jobs=4``, ``-j4``, a word
    ccfBare     ## a switch or an optional-value flag written bare
    ccfNegated  ## ``--no-<name>``
    ccfCount    ## one occurrence of a counted flag

  CliCandidate* = object
    ## One value a source supplies for a parameter.
    source*: CliSource
    form*: CliCandidateForm
    text*: string
      ## The value as written (``ccfValue`` only).
    argvIndex*: int
      ## The index in argv of the flag (or of the positional word).
    valueArgvIndex*: int
      ## The index of the word holding the value when it is not the flag's
      ## own word (``--jobs 4``), else -1.
    spelling*: string
      ## The spelling used: ``--jobs``, ``-j``, ``--no-verbose``. Empty for
      ## a positional.

  CliTokens* = object
    ## What ``cliTokenize`` read from argv.
    selected*: seq[int]
      ## The commands dispatched to, from the root (index 0) to the one that
      ## runs (a ``call:`` included).
    candidates*: seq[seq[CliCandidate]]
      ## Per parameter id, in argv order.

  CliDecisionKind* = enum
    cdkUnset    ## no source, implication or default supplies a value
    cdkSource   ## the merged candidates supply it
    cdkImplied  ## another parameter's ``implies``
    cdkDefault  ## the parameter's ``default``

  CliDecision* = object
    kind*: CliDecisionKind
    impliedBy*: int
      ## The implying parameter's id (``cdkImplied``).
    implication*: int
      ## The index of the entry in that parameter's ``implies``.

  CliResolution* = object
    ## Everything decided before the typed object is built.
    selected*: seq[int]
    merged*: seq[seq[CliCandidate]]
      ## Per parameter id: the winning candidates (``cliMerge``).
    overridden*: seq[seq[CliCandidate]]
      ## Per parameter id: the candidates that lost.
    decisions*: seq[CliDecision]
      ## Per parameter id; ``cdkUnset`` for parameters of commands that were
      ## not selected.
    exitCode*: int
    program*: string

func effectiveProgram(g: CliGrammar; options: CliOptions): string =
  if options.program.len > 0: options.program else: g.program

func effectiveExitCode(options: CliOptions): int =
  if options.usageExitCode == 0: DefaultUsageExitCode
  else: options.usageExitCode

func subcommandWords(g: CliGrammar; command: int): string =
  cliSubcommandWords(g, command).join(", ")

type
  FlagMatch = object
    found: bool
    id: int
    spelling: string
    negated: bool
    attached: Option[string]
      ## A value written in the same word (``--x=v``, ``-ov``).

func findFlag(g: CliGrammar; scope: seq[int];
              pred: proc (p: CliGrammarParam): bool {.noSideEffect, raises: [].}): int =
  ## The last flag of ``scope`` (the most nested declaration) matching.
  for i in countdown(scope.high, 0):
    let p = g.params[scope[i]]
    if p.kind == cpkFlag and pred(p):
      return scope[i]
  -1

func matchLong(g: CliGrammar; scope: seq[int]; word: string): FlagMatch =
  ## A word starting with ``--``: an exact spelling, ``<spelling>=value``,
  ## ``--no-<name>`` or a ``concat`` spelling followed by its value.
  let eq = word.find('=')
  let head = if eq >= 0: word[0 ..< eq] else: word
  let id = findFlag(g, scope, proc (p: CliGrammarParam): bool =
    head == "--" & p.name or head == p.alias)
  if id >= 0:
    result = FlagMatch(found: true, id: id, spelling: head)
    if eq >= 0:
      result.attached = some(word[eq + 1 .. ^1])
    return
  if head.startsWith("--no-"):
    let name = head[5 .. ^1]
    let neg = findFlag(g, scope, proc (p: CliGrammarParam): bool =
      p.negatable and p.name == name)
    if neg >= 0:
      result = FlagMatch(found: true, id: neg, spelling: head, negated: true)
      if eq >= 0:
        result.attached = some(word[eq + 1 .. ^1])
      return
  var best = -1
  for i in countdown(scope.high, 0):
    let p = g.params[scope[i]]
    if p.kind == cpkFlag and p.format == cafConcat and p.alias.len > 0 and
        word.startsWith(p.alias) and word.len > p.alias.len:
      if best < 0 or p.alias.len > g.params[best].alias.len:
        best = scope[i]
  if best >= 0:
    let alias = g.params[best].alias
    result = FlagMatch(found: true, id: best, spelling: alias,
      attached: some(word[alias.len .. ^1]))

func matchSingleDash(g: CliGrammar; scope: seq[int];
                     word: string): FlagMatch =
  ## A word starting with one ``-``: an exact spelling, an ``equals``
  ## spelling with ``=value`` or a ``concat`` spelling with its value. Short
  ## clusters are handled by the caller.
  let id = findFlag(g, scope, proc (p: CliGrammarParam): bool =
    word == p.alias or (p.short != '\0' and word == "-" & p.short))
  if id >= 0:
    return FlagMatch(found: true, id: id, spelling: word)
  let eq = word.find('=')
  if eq > 0:
    let head = word[0 ..< eq]
    let eid = findFlag(g, scope, proc (p: CliGrammarParam): bool =
      p.format == cafEquals and head == p.alias)
    if eid >= 0:
      return FlagMatch(found: true, id: eid, spelling: head,
        attached: some(word[eq + 1 .. ^1]))
  var best = -1
  for i in countdown(scope.high, 0):
    let p = g.params[scope[i]]
    if p.kind == cpkFlag and p.format == cafConcat and p.alias.len > 1 and
        word.startsWith(p.alias) and word.len > p.alias.len:
      if best < 0 or p.alias.len > g.params[best].alias.len:
        best = scope[i]
  if best >= 0:
    let alias = g.params[best].alias
    return FlagMatch(found: true, id: best, spelling: alias,
      attached: some(word[alias.len .. ^1]))

func takesNoValue(p: CliGrammarParam): bool =
  p.isSwitch or p.counted

func isHelpSpelling(g: CliGrammar; scope: seq[int]; word: string;
                    options: CliOptions): tuple[help, json: bool] =
  ## ``--help``, ``--help=json`` or ``-h``, unless turned off or declared
  ## by the program for one of its own flags.
  if options.disableHelpFlag:
    return
  let head = if word.startsWith("--help="): "--help" else: word
  if head notin ["--help", "-h"]:
    return
  if findFlag(g, scope, proc (p: CliGrammarParam): bool =
      head in cliFlagSpellings(p)) >= 0:
    return
  if word == "--help" or word == "-h":
    return (true, false)
  if word == "--help=json":
    return (true, true)
  if word == "--help=text":
    return (true, false)

proc cliTokenize*(g: CliGrammar; argv: openArray[string];
                  options = CliOptions()): CliTokens {.
    raises: [CliUsageError, CliHelpRequest].} =
  ## Phase 1: reads ``argv`` (the arguments, without the program name).
  ## Raises ``CliUsageError`` for a word it cannot place and
  ## ``CliHelpRequest`` when help is asked for.
  let program = effectiveProgram(g, options)
  let exitCode = effectiveExitCode(options)
  var selected = @[0]
  var candidates = newSeq[seq[CliCandidate]](g.params.len)
  var node = 0

  proc fail(kind: CliErrorKind; at: int; spelling: string; value = "";
            expected = "") {.raises: [CliUsageError].} =
    raise newCliUsageError(kind, program, g.commands[node].path, at,
      spelling, value, expected, exitCode = exitCode)

  proc descend() =
    # A command without subcommands runs its call: directly.
    while g.commands[node].children.len == 0 and
        g.commands[node].callChild >= 0:
      node = g.commands[node].callChild
      selected.add(node)

  proc enter(next: int) =
    node = next
    selected.add(next)
    descend()

  proc addCandidate(id: int; c: CliCandidate) =
    candidates[id].add(c)

  descend()
  var positionals: seq[tuple[word: string, index: int]] = @[]
  var terminated = false
  var i = 0

  while i < argv.len:
    let word = argv[i]
    let isFlagWord = not terminated and word.len > 1 and word[0] == '-'
    if not terminated and word == "--":
      terminated = true
      inc i
      continue
    if not isFlagWord:
      let cmd = g.commands[node]
      if cmd.children.len > 0:
        let next = if terminated: -1 else: cliChildNamed(g, node, word)
        if next >= 0:
          enter(next)
        elif cmd.callChild >= 0:
          enter(cmd.callChild)
          positionals.add((word, i))
        elif terminated:
          fail(cekUnexpectedPositional, i, word)
        else:
          fail(cekUnknownSubcommand, i, word,
            expected = subcommandWords(g, node))
      else:
        positionals.add((word, i))
      inc i
      continue

    # A flag. Help first, then the command's own flags, then (for a command
    # with subcommands and a call:) the call:'s.
    let scope = g.commands[node].params
    let helpAsk = isHelpSpelling(g, scope, word, options)
    if helpAsk.help:
      let path = g.commands[node].path
      let text = if helpAsk.json: cliHelpJson(g, node, program)
                 else: cliHelpText(g, node, program)
      raise (ref CliHelpRequest)(msg: "help requested", commandPath: path,
        json: helpAsk.json, text: text)
    var m = if word.startsWith("--"): matchLong(g, scope, word)
            else: matchSingleDash(g, scope, word)
    if not m.found and g.commands[node].children.len > 0 and
        g.commands[node].callChild >= 0:
      let callScope = g.commands[g.commands[node].callChild].params
      let cm = if word.startsWith("--"): matchLong(g, callScope, word)
               else: matchSingleDash(g, callScope, word)
      if cm.found:
        enter(g.commands[node].callChild)
        m = cm
    if not m.found and not word.startsWith("--"):
      # A cluster of short spellings: ``-vvq``, ``-j4``, ``-vo out``. Read
      # against the command's flags first; for a command with subcommands
      # and a call:, a cluster that needs a letter only the call: declares
      # runs the call:, as a single such flag does above.
      var scopes = @[g.commands[node].params]
      let callNode = if g.commands[node].children.len > 0:
                       g.commands[node].callChild
                     else: -1
      if callNode >= 0:
        scopes.add(g.commands[callNode].params)
      var placed = false
      for attempt, clusterScope in scopes:
        var k = 1
        var ok = true
        var pending: seq[tuple[id: int, c: CliCandidate]] = @[]
        var consumedNext = false
        while k < word.len:
          let letter = word[k]
          let id = findFlag(g, clusterScope, proc (p: CliGrammarParam): bool =
            p.short == letter)
          if id < 0:
            ok = false
            break
          let p = g.params[id]
          let spelling = "-" & letter
          if takesNoValue(p):
            pending.add((id, CliCandidate(source: csCli,
              form: (if p.counted: ccfCount else: ccfBare), argvIndex: i,
              valueArgvIndex: -1, spelling: spelling)))
            inc k
            continue
          let rest = word[k + 1 .. ^1]
          if rest.len > 0:
            pending.add((id, CliCandidate(source: csCli, form: ccfValue,
              text: rest, argvIndex: i, valueArgvIndex: -1,
              spelling: spelling)))
          elif p.hasOptionalValue:
            pending.add((id, CliCandidate(source: csCli, form: ccfBare,
              argvIndex: i, valueArgvIndex: -1, spelling: spelling)))
          elif i + 1 < argv.len:
            pending.add((id, CliCandidate(source: csCli, form: ccfValue,
              text: argv[i + 1], argvIndex: i, valueArgvIndex: i + 1,
              spelling: spelling)))
            consumedNext = true
          else:
            fail(cekMissingValue, i, spelling)
          break
        if ok and pending.len > 0:
          if attempt == 1:
            enter(callNode)
          for item in pending:
            addCandidate(item.id, item.c)
          i += (if consumedNext: 2 else: 1)
          placed = true
          break
      if placed:
        continue
      fail(cekUnknownFlag, i, word)
    if not m.found:
      fail(cekUnknownFlag, i,
        (if word.find('=') > 0: word[0 ..< word.find('=')] else: word))
    let p = g.params[m.id]
    var c = CliCandidate(source: csCli, argvIndex: i, valueArgvIndex: -1,
      spelling: m.spelling)
    if m.negated:
      if m.attached.isSome:
        fail(cekInvalidValue, i, m.spelling, m.attached.get, "no value")
      c.form = ccfNegated
    elif m.attached.isSome:
      if p.counted:
        fail(cekInvalidValue, i, m.spelling, m.attached.get, "no value")
      c.form = ccfValue
      c.text = m.attached.get
    elif takesNoValue(p):
      c.form = if p.counted: ccfCount else: ccfBare
    elif p.hasOptionalValue:
      c.form = ccfBare
    elif p.format == cafSeparate and i + 1 < argv.len:
      c.form = ccfValue
      c.text = argv[i + 1]
      c.valueArgvIndex = i + 1
      inc i
    else:
      fail(cekMissingValue, i, m.spelling)
    addCandidate(m.id, c)
    inc i

  # End of argv: a command with subcommands needs one, unless it has a call:.
  if g.commands[node].children.len > 0:
    if g.commands[node].callChild >= 0:
      enter(g.commands[node].callChild)
    else:
      fail(cekMissingSubcommand, -1, "",
        expected = subcommandWords(g, node))

  # Positionals, in position order. A list positional takes what the
  # positionals after it do not need.
  let slots = cliPositionals(g, node)
  var next = 0
  for s, id in slots:
    let p = g.params[id]
    if p.repeated or p.isList:
      var reserve = 0
      for later in slots[s + 1 .. ^1]:
        if g.params[later].required:
          inc reserve
      let take = max(0, positionals.len - next - reserve)
      for w in positionals[next ..< next + take]:
        addCandidate(id, CliCandidate(source: csCli, form: ccfValue,
          text: w.word, argvIndex: w.index, valueArgvIndex: -1))
      next += take
    elif next < positionals.len:
      let w = positionals[next]
      addCandidate(id, CliCandidate(source: csCli, form: ccfValue,
        text: w.word, argvIndex: w.index, valueArgvIndex: -1))
      inc next
  if next < positionals.len:
    fail(cekUnexpectedPositional, positionals[next].index,
      positionals[next].word)
  result.selected = selected
  result.candidates = candidates

proc cliMerge*(g: CliGrammar; tokens: CliTokens; options = CliOptions()):
    CliResolution =
  ## Phase 2: the winning candidates of each parameter. With the command
  ## line as the only source, a list (or counted) parameter keeps every
  ## occurrence and any other keeps its last; the earlier ones are recorded
  ## as overridden.
  result.selected = tokens.selected
  result.program = effectiveProgram(g, options)
  result.exitCode = effectiveExitCode(options)
  result.merged = newSeq[seq[CliCandidate]](g.params.len)
  result.overridden = newSeq[seq[CliCandidate]](g.params.len)
  result.decisions = newSeq[CliDecision](g.params.len)
  for id, cands in tokens.candidates:
    if cands.len == 0:
      continue
    let p = g.params[id]
    if p.isList or p.counted:
      result.merged[id] = cands
    else:
      result.merged[id] = @[cands[^1]]
      result.overridden[id] = cands[0 ..< ^1]

proc cliDecide*(g: CliGrammar; r: var CliResolution) {.
    raises: [CliUsageError].} =
  ## Phase 3: what each parameter of the selected commands gets — its merged
  ## candidates, else a value implied by a parameter that has candidates
  ## (the first such in declaration order; implications do not chain), else
  ## its default. A required parameter that gets nothing is a usage error
  ## naming the command that declares it.
  var visible: seq[int] = @[]
  for command in r.selected:
    for id in g.commands[command].ownParams:
      visible.add(id)
  for id in visible:
    if r.merged[id].len > 0:
      r.decisions[id] = CliDecision(kind: cdkSource)
  for id in visible:
    if r.decisions[id].kind != cdkUnset:
      continue
    block implied:
      for src in visible:
        if r.decisions[src].kind != cdkSource:
          continue
        for k, target in g.params[src].implies:
          if target == id:
            r.decisions[id] = CliDecision(kind: cdkImplied, impliedBy: src,
              implication: k)
            break implied
    if r.decisions[id].kind == cdkUnset and g.params[id].hasDefault:
      r.decisions[id] = CliDecision(kind: cdkDefault)
  # The innermost missing parameter is reported first.
  for i in countdown(visible.high, 0):
    let id = visible[i]
    let p = g.params[id]
    if p.required and r.decisions[id].kind == cdkUnset:
      raise newCliUsageError(cekMissingRequired, r.program,
        g.commands[p.declaredBy].path, -1, cliDisplayName(p),
        exitCode = r.exitCode)

proc cliResolve*(g: CliGrammar; argv: openArray[string];
                 options = CliOptions()): CliResolution {.
    raises: [CliUsageError, CliHelpRequest].} =
  ## Phases 1 to 3.
  let tokens = cliTokenize(g, argv, options)
  result = cliMerge(g, tokens, options)
  cliDecide(g, result)

func cliSelected*(r: CliResolution; command: int): bool =
  ## Whether ``command`` is on the selected path.
  command in r.selected

# ---------------------------------------------------------------------------
# Phase 4 helpers, called by the generated code.
# ---------------------------------------------------------------------------

proc invalid(g: CliGrammar; r: CliResolution; id: int; c: CliCandidate;
             text, expected: string) {.noreturn, raises: [CliUsageError].} =
  let p = g.params[id]
  let spelling = if c.spelling.len > 0: c.spelling else: cliDisplayName(p)
  let index = if c.valueArgvIndex >= 0: c.valueArgvIndex else: c.argvIndex
  raise newCliUsageError(cekInvalidValue, r.program,
    g.commands[p.declaredBy].path, index, spelling, text, expected,
    exitCode = r.exitCode)

proc convertText[T](g: CliGrammar; r: CliResolution; id: int;
                    c: CliCandidate; text: string; value: var T) {.
    raises: [CliUsageError].} =
  mixin parseCliValue
  try:
    parseCliValue(text, value)
  except CliValueError as e:
    invalid(g, r, id, c, text, e.expected)
  except ValueError:
    invalid(g, r, id, c, text, cliTypeDescription(T))

proc restrictTo[E](g: CliGrammar; r: CliResolution; id: int;
                   c: CliCandidate; text: string; v: E;
                   allowed: openArray[E]) {.raises: [CliUsageError].} =
  ## ``v`` must be one of ``allowed``, when that is not empty.
  if allowed.len > 0 and v notin allowed:
    var texts: seq[string] = @[]
    for a in allowed:
      texts.add(cliValueText(a))
    invalid(g, r, id, c, text, "one of: " & texts.join(", "))

template cliElementType*(T: typedesc): typedesc =
  ## The type of one value of a parameter of type ``T``: the element of a
  ## ``seq``, the content of an ``Option``, else ``T`` itself. A
  ## ``values`` set is a set of these.
  when T is seq: typeof(default(T)[0])
  elif T is Option: typeof(default(T).get())
  else: T

proc cliConvert*[T, E](g: CliGrammar; r: CliResolution; id: int;
                       value: var T; bare: proc (): T {.raises: [].};
                       allowed: openArray[E]) {.raises: [CliUsageError].} =
  ## Converts the merged candidates of parameter ``id`` into ``value``.
  ## ``bare`` gives the value of a bare optional-value flag (its
  ## ``optionalValue``); it is not called otherwise. When ``allowed`` is not
  ## empty (the parameter's ``values``), every converted value must be one
  ## of its entries.
  mixin parseCliValue
  let p = g.params[id]
  let cands = r.merged[id]

  template restrict(c: CliCandidate; text: string; v: E) =
    restrictTo(g, r, id, c, text, v, allowed)

  when T is seq:
    value.setLen(0)
    for c in cands:
      case c.form
      of ccfValue:
        let pieces = if p.separator.len > 0: c.text.split(p.separator)
                     else: @[c.text]
        for piece in pieces:
          var item: E
          convertText(g, r, id, c, piece, item)
          restrict(c, piece, item)
          value.add(item)
      of ccfBare:
        for item in bare():
          value.add(item)
      of ccfNegated, ccfCount:
        discard
  else:
    if p.counted:
      when T is SomeInteger:
        value = T(cands.len)
      return
    let c = cands[^1]
    case c.form
    of ccfValue:
      convertText(g, r, id, c, c.text, value)
      when T is Option:
        if value.isSome:
          restrict(c, c.text, value.get)
      else:
        restrict(c, c.text, value)
    of ccfBare:
      when T is bool:
        value = if p.hasOptionalValue: bare() else: true
      elif T is Option[bool]:
        value = if p.hasOptionalValue: bare() else: some(true)
      else:
        value = bare()
    of ccfNegated:
      when T is bool:
        value = false
      elif T is Option[bool]:
        value = some(false)
    of ccfCount:
      discard
