## Rendering a parsed command line back to argv words.
##
## A program sometimes has to hand part of its own command line to another
## command line: a ``test`` command that runs a ``build`` passes on the
## build flags it was given; a front end that re-executes itself in a
## daemon or a sandbox passes on what it parsed. Splicing the original
## words is wrong as soon as only some parameters travel (a flag's value
## may be the next word, short flags cluster, a value can look like a
## flag), and writing the words by hand duplicates the grammar.
##
## ``cliArgvOf`` writes them from the grammar and the *candidates* the
## parser recorded (``clispec/candidates``): the occurrences the command
## line supplied for each parameter, each with its argv index. The words it
## returns parse, with the same grammar, to the same values, and every value
## they supply comes from the command line again, so a value another source
## supplied (an environment variable, a configuration file, a default or an
## implication, which the program reads again when it parses the words) is
## never written into them.
##
## The canonical spellings
## =======================
##
## * A flag is written with its long spelling, ``--<longName>``, whatever
##   spelling was used (``-j``, an alias, a cluster such as ``-vqq``, a
##   spelling matched under ``flagMatching``). ``hidden`` and ``internal``
##   flags are written like any other; a ``retired`` spelling is never
##   written, because the parser never accepts one.
## * A value is attached: ``--<longName>=<value>``, so a value that starts
##   with ``-``, is ``--`` or is empty stays that flag's value. Under
##   ``parsing equalsTakesNext`` an empty value of a ``format = separate``
##   flag is written as two words (``--name`` and the empty word), because
##   ``--name=`` would take the next word.
## * A switch is ``--<longName>`` when true, ``--no-<longName>`` when
##   negated (``--<longName>=false`` when it is not negatable or another
##   flag answers to ``--no-<longName>``), and any other value it was given
##   is attached as written.
## * A counted flag is ``--<longName>`` once per occurrence; an optional
##   value flag is bare (its ``optionalValue``) or ``--<longName>=<value>``.
## * A list is one word per occurrence, in order (each occurrence keeps its
##   ``separator``-delimited text).
## * A value another flag's ``alsoSets`` supplied is written as that flag,
##   at its position, when that flag is selected (a switch given twice is
##   then written twice, the later occurrence deciding its own value as
##   before); otherwise as the parameter's own value, and not at all for a
##   parameter the command line cannot spell (``sources`` without ``cli``).
## * The flags come in the order they were given, after the words of the
##   subcommands that select the command. The positionals follow, in
##   position order, and the words of an ``afterSeparator`` positional
##   last, after ``--``, exactly as they were.
## * ``--`` comes before the positionals when one of them would otherwise
##   not be read as a positional: a word that starts with ``-``, or, after
##   a command whose subcommands and ``call:`` share the word, a word that
##   names a subcommand (or ``help`` / ``version`` under ``parsing
##   helpWord`` / ``versionWord``), and after a flag word that would take
##   the next word as its value (a bare ``acceptsNextWord`` flag, an empty
##   ``--name=`` under ``equalsTakesNext``). Where ``--`` would start an
##   ``afterSeparator`` positional instead, a flag that can move without
##   changing a value (it shares no parameter, and no ``alsoSets`` target,
##   with the flags after it) is written after that flag word, or else the
##   flags follow the positionals.
##
## Order matters only within one parameter (the last occurrence of a scalar
## wins, a list keeps its order) and between a flag and the values its
## ``alsoSets`` gives another parameter; both are kept.
##
## What a selection cannot keep
## ============================
##
## Positionals are positional: rendering one positional and leaving out an
## earlier one gives its words to the earlier one when the words are read
## back. Select a command's positionals together. A flag that
## ``alsoSets`` another parameter brings that value with it when the words
## are read back, whether or not the other parameter is selected.

import std/strutils

import ./[model, grammar, candidates, parser]

func cliCommandWord*(g: CliGrammar; command: int;
                     options = CliOptions()): string =
  ## The word that selects ``command`` below its parent: its name, or,
  ## when ``parsing helpWord`` / ``versionWord`` would read the name as a
  ## request (a subcommand declared ``shadowedByWord = true``), the first
  ## of its ``aliases`` that is not. Empty for the root and a ``call:``,
  ## which no word selects.
  let cmd = g.commands[command]
  if command == 0 or cmd.isCall:
    return ""
  for w in @[cmd.name] & cmd.aliases:
    if not cliIsHelpWord(g, w, options) and
        not cliIsVersionWord(g, w, options):
      return w
  cmd.name

func normalName(name: string): string =
  ## A parameter name compared as Nim compares identifiers.
  nimIdentNormalize(name)

proc cliRenderParams*(g: CliGrammar; selected: openArray[int];
                      only: openArray[string] = []; group = ""):
    seq[int] {.raises: [ValueError].} =
  ## The parameters of the commands ``selected`` (``cliVisibleParams``)
  ## that ``cliArgvOf`` renders: every one, or those named in ``only``
  ## (declared names, compared as Nim identifiers), and of those the ones in
  ## the parameter group ``group`` when it is not empty. A name in ``only``
  ## that the selected commands do not hold is skipped, so the flags of one
  ## command can select the same flags of another; a name that is no
  ## parameter of the grammar at all, and a group no parameter is in, raise
  ## ``ValueError``.
  var wanted: seq[string] = @[]
  for name in only:
    let n = normalName(name)
    var known = false
    for p in g.params:
      if normalName(p.name) == n:
        known = true
        break
    if not known:
      raise newException(ValueError, "clispec: no parameter is named '" &
        name & "'")
    wanted.add(n)
  if group.len > 0:
    var known = false
    for p in g.params:
      if p.group == group:
        known = true
        break
    if not known:
      raise newException(ValueError, "clispec: no parameter is in the " &
        "group '" & group & "'")
  for id in cliVisibleParams(g, selected):
    let p = g.params[id]
    if only.len > 0 and normalName(p.name) notin wanted:
      continue
    if group.len > 0 and p.group != group:
      continue
    result.add(id)

func flagScope(g: CliGrammar; leaf: int): seq[int] =
  ## The parameters a flag word is matched against where the flags are
  ## written: the command that runs, and, for a ``call:`` beside
  ## subcommands, the command holding it.
  result = g.commands[leaf].params
  if g.commands[leaf].isCall:
    let parent = g.commands[leaf].parent
    if g.commands[parent].children.len > 0:
      for id in g.commands[parent].params:
        if id notin result:
          result.add(id)

func valueWords(g: CliGrammar; id: int; text: string): seq[string] =
  ## A value-taking flag with ``text`` as its value.
  let p = g.params[id]
  let long = "--" & cliLongName(p)
  if text.len == 0 and cprEqualsTakesNext in g.parseRules and
      p.format == cafSeparate:
    @[long, ""]
  else:
    @[long & "=" & text]

func flagWords(g: CliGrammar; scope: seq[int]; id: int;
               c: CliCandidate): seq[string] =
  ## One occurrence of the flag ``id``, in its canonical spelling.
  let p = g.params[id]
  let long = "--" & cliLongName(p)
  proc falseWords(): seq[string] =
    let negated = "--no-" & cliLongName(p)
    let m = cliMatchFlagWord(g, scope, negated)
    if p.negatable and m.found and m.id == id and m.negated:
      @[negated]
    else:
      @[long & "=false"]
  case c.form
  of ccfBare, ccfCount:
    @[long]
  of ccfNegated:
    falseWords()
  of ccfValue:
    if p.isSwitch and not p.hasOptionalValue:
      if c.text == "true":
        @[long]
      elif c.text == "false":
        falseWords()
      else:
        @[long & "=" & c.text]
    else:
      valueWords(g, id, c.text)
  of ccfEmpty:
    @[]

func setterOf(g: CliGrammar; id: int; c: CliCandidate): int =
  ## The flag whose ``alsoSets`` supplied ``c`` to parameter ``id``, or -1.
  for s, p in g.params:
    if p.name == c.setBy:
      for a in p.alsoSets:
        if a.id == id:
          return s
  -1

func related(g: CliGrammar; a, b: int): bool =
  ## Whether the order of a word of flag ``a`` and a word of flag ``b``
  ## can change a value: one parameter, one gives the other a value through
  ## ``alsoSets``, or both give a third one a value.
  if a == b:
    return true
  for x in g.params[a].alsoSets:
    if x.id == b:
      return true
    for y in g.params[b].alsoSets:
      if x.id == y.id:
        return true
  for x in g.params[b].alsoSets:
    if x.id == a:
      return true
  false

func commandLineOnly(given: openArray[seq[CliCandidate]];
                     id: int): seq[CliCandidate] =
  ## The candidates of ``given[id]`` the command line supplied.
  if id < given.len:
    for c in given[id]:
      if c.source == csCli:
        result.add(c)

func isFlagLike(g: CliGrammar; word: string): bool =
  ## Whether the parser reads ``word``, where a positional may stand, as
  ## something else: a flag (``--`` included), or under
  ## ``loneDashesAreFlags`` a lone ``-``.
  (word.len > 1 and word[0] == '-') or cliIsLoneDash(g, word)

proc cliArgvOf*(g: CliGrammar; selected: openArray[int];
                given: openArray[seq[CliCandidate]];
                params: openArray[int]; commandWords = true;
                options = CliOptions()): seq[string] =
  ## The command line, as argv words (without the program name), that gives
  ## the parameters ``params`` the command-line values ``given`` holds.
  ##
  ## ``selected`` lists the commands from the one the words start at (the
  ## root for a whole command line) to the one that runs, a ``call:``
  ## included, as ``CliTokens.selected`` does. ``given[id]`` holds the
  ## candidates the command line supplied for parameter ``id`` that are
  ## part of its value (``CliResolution.merged`` for a command line parsed
  ## alone; confutils' origin object records them under every source); a
  ## candidate from another source is ignored. ``params`` are the parameter
  ## ids to render (``cliRenderParams``). With ``commandWords`` the words
  ## start with those that select the commands after the first; without,
  ## only the parameters' words are returned, for a caller that places them
  ## after a command of its own. ``options`` is what the words will be
  ## parsed with (its ``valueCheck`` and ``versionText`` matter).
  ##
  ## The spellings and the order are in the module documentation.
  if selected.len == 0:
    return
  let leaf = selected[^1]
  var render = newSeq[bool](g.params.len)
  for id in params:
    if id >= 0 and id < g.params.len:
      render[id] = true
  template cliOnly(id: int): seq[CliCandidate] =
    commandLineOnly(given, id)

  # The flags, as (argv index, order, words, dangerous) items: a flag's
  # own occurrences, and an ``alsoSets`` value its flag does not bring.
  type Item = object
    at, order, id: int
    words: seq[string]
    dangerous: bool
      ## The word takes the next one as its value unless that starts with
      ## ``-``: a bare ``acceptsNextWord`` flag, an empty ``--name=`` under
      ## ``equalsTakesNext``.
  let scope = flagScope(g, leaf)
  var items: seq[Item] = @[]
  var setByWords: seq[tuple[id: int, c: CliCandidate]] = @[]
  var setterWritten: seq[tuple[id, at: int]] = @[]
    ## The extra occurrences of a switch written for the values its
    ## ``alsoSets`` gave (below).
  for id in params:
    let p = g.params[id]
    for c in cliOnly(id):
      if c.setBy.len > 0:
        let s = setterOf(g, id, c)
        let spellable = s >= 0 and render[s] and csCli in g.params[s].sources
        var brought = false
        if spellable:
          for own in cliOnly(s):
            if own.setBy.len == 0 and own.argvIndex == c.argvIndex:
              brought = true
              break
        if brought or (s, c.argvIndex) in setterWritten:
          continue
        if spellable and (g.params[s].isSwitch or g.params[s].counted):
          # The switch occurred here and a later occurrence decided its own
          # value: written here too, it gives the value again, and the
          # later one still decides the switch.
          setterWritten.add((s, c.argvIndex))
          items.add(Item(at: c.argvIndex, order: items.len, id: s,
            words: @["--" & cliLongName(g.params[s])]))
          continue
        if csCli notin p.sources:
          # A parameter the command line cannot spell (``sources`` without
          # ``cli``): only its flag gives it a value.
          continue
        if p.kind == cpkFlag:
          let words = valueWords(g, id, c.text)
          items.add(Item(at: c.argvIndex, order: items.len, id: id,
            words: words, dangerous: words.len == 1 and
              words[0].endsWith("=") and cprEqualsTakesNext in g.parseRules))
        else:
          setByWords.add((id, c))
      elif p.kind == cpkFlag:
        let words = flagWords(g, scope, id, c)
        let dangerous = (c.form == ccfBare and p.hasOptionalValue and
            p.acceptsNextWord) or (words.len == 1 and
            words[0].endsWith("=") and cprEqualsTakesNext in g.parseRules)
        items.add(Item(at: c.argvIndex, order: items.len, id: id,
          words: words, dangerous: dangerous))
  # In argv order; occurrences at one index (a cluster, an ``alsoSets``)
  # in the order collected.
  for i in 1 ..< items.len:
    var j = i
    while j > 0 and (items[j - 1].at > items[j].at or
        (items[j - 1].at == items[j].at and
         items[j - 1].order > items[j].order)):
      swap(items[j - 1], items[j])
      dec j

  # The positionals of the command that runs.
  var words, rest, tail: seq[string] = @[]
  for id in cliWordPositionals(g, leaf):
    if not render[id]:
      continue
    var texts: seq[string] = @[]
    for c in cliOnly(id):
      if c.setBy.len == 0 and c.form == ccfValue:
        texts.add(c.text)
    for item in setByWords:
      if item.id == id:
        texts.add(item.c.text)
    if g.params[id].rest:
      rest.add(texts)
    else:
      words.add(texts)
  let sepId = cliAfterSeparatorParam(g, leaf)
  if sepId >= 0 and render[sepId]:
    for c in cliOnly(sepId):
      if c.form == ccfValue:
        tail.add(c.text)

  # Where the words are read. A ``call:`` beside subcommands is entered by
  # its first word (or a flag only it declares); before that, its parent
  # reads the words.
  let leafCmd = g.commands[leaf]
  let callBesideSubcommands = leafCmd.isCall and
    g.commands[leafCmd.parent].children.len > 0
  var callEntered = not callBesideSubcommands
  if callBesideSubcommands:
    for item in items:
      if item.id in leafCmd.ownParams:
        callEntered = true
  let restParam = cliRestParam(g, leaf)
  let restAtStart = restParam.id >= 0 and restParam.index == 0
  # ``--`` ends the flags where it can be written: not in a command whose
  # ``afterSeparator`` positional it would start, not where a ``rest``
  # positional would take it, and not where it is itself a flag.
  let canEndFlags = sepId < 0 and cprLoneDashesAreFlags notin g.parseRules and
    not (restAtStart and callEntered)
  let positionals = words & rest
  var endFlags = false
  if words.len > 0:
    # A word positional that looks like a flag is a positional only after
    # ``--``. (A ``rest`` positional's words are taken as they come once
    # the positionals before it have theirs.)
    for w in words:
      if isFlagLike(g, w):
        endFlags = true
  if positionals.len > 0 and not callEntered:
    # The parent of a ``call:`` beside subcommands reads the first word: a
    # flag, a subcommand word or a request there is not the call:'s.
    let w = positionals[0]
    if isFlagLike(g, w) or cliChildNamed(g, leafCmd.parent, w) >= 0 or
        cliIsHelpWord(g, w, options) or cliIsVersionWord(g, w, options):
      endFlags = true
  if not canEndFlags:
    endFlags = false
  # A dangerous flag word followed by a word that does not start with
  # ``-`` would take that word. ``--`` ends the flags where it can be
  # written. Elsewhere (a command with an ``afterSeparator`` positional,
  # whose ``--`` starts it) a flag word that may move without changing a
  # value goes last, and failing that the flags follow the positionals.
  var flagsAfterPositionals = false
  if items.len > 0 and items[^1].dangerous and positionals.len > 0 and
      not endFlags and
      not (positionals[0].len > 0 and positionals[0][0] == '-'):
    if canEndFlags:
      endFlags = true
    else:
      var moved = false
      for k in countdown(items.high - 1, 0):
        if items[k].dangerous:
          continue
        var free = true
        for j in k + 1 .. items.high:
          if related(g, items[k].id, items[j].id):
            free = false
            break
        if free:
          let item = items[k]
          items.delete(k)
          items.add(item)
          moved = true
          break
      if not moved and restParam.id < 0 and not callBesideSubcommands:
        flagsAfterPositionals = true

  var flagWordsList: seq[string] = @[]
  for item in items:
    flagWordsList.add(item.words)
  # The subcommand words, with the flags after them; where the command
  # that runs (or the ``call:`` its word enters) takes every word into a
  # ``rest`` positional from its first, the flags (inherited ones) go
  # before its word.
  var path: seq[string] = @[]
  if commandWords:
    for k in 1 ..< selected.len:
      let w = cliCommandWord(g, selected[k], options)
      if w.len > 0:
        path.add(w)
  if restAtStart and not callBesideSubcommands and path.len > 0 and
      flagWordsList.len > 0:
    result = path[0 ..< path.high] & flagWordsList & path[^1]
  elif flagsAfterPositionals:
    result = path
  else:
    result = path & flagWordsList
  if endFlags:
    result.add("--")
  result.add(positionals)
  if flagsAfterPositionals:
    result.add(flagWordsList)
  if tail.len > 0:
    result.add("--")
    result.add(tail)

proc cliArgvOf*(g: CliGrammar; r: CliResolution;
                only: openArray[string] = []; group = "";
                commandWords = true; options = CliOptions()): seq[string] {.
    raises: [ValueError].} =
  ## The command line that gives the parameters ``only`` names (every
  ## parameter when empty; ``cliRenderParams``) the values the command line
  ## gave them in ``r``, a resolution of a command line parsed alone
  ## (``cliResolve``): the canonical form of that command line.
  var given = newSeq[seq[CliCandidate]](g.params.len)
  for id in 0 ..< min(g.params.len, r.merged.len):
    if r.decisions.len > id and r.decisions[id].kind == cdkSource:
      given[id] = r.merged[id]
  cliArgvOf(g, r.selected, given, cliRenderParams(g, r.selected, only,
    group), commandWords, options)
