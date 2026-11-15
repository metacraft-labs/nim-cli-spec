## Shell completion: the engine that answers "what can come next", and the
## protocol a shell's completion script uses to ask the program.
##
## The engine
## ==========
##
## ``cliComplete`` reads the words of a command line up to the cursor
## against a ``CliGrammar``, the way the parser reads them, and returns the
## candidates for the word under the cursor:
##
## * a word starting with ``-`` (outside a ``--``-terminated tail) is
##   completed as a flag: every spelling of every flag the command accepts
##   (``--<long name>``, ``--no-<long name>`` for a ``negatable`` flag, the
##   ``alias`` and ``-<short>``) that starts with the word, then ``--help``
##   and ``-h`` when they request help (``--help`` alone under ``parsing
##   longHelpOnly``). ``--version`` is not offered. A flag that takes its value only as
##   ``--flag=value`` (``format = equals``) is offered as ``--flag=``, so
##   the user types the value straight after it. A ``concat`` alias, whose
##   value is written straight after it, is not offered on its own.
## * ``--flag=<partial>`` and a ``concat`` alias followed by a partial value
##   complete that flag's value, each candidate written with the flag in
##   front, as the word must be.
## * the word after a flag that takes the next word as its value
##   (``format = separate``, no ``optionalValue``), or after a cluster of
##   short flags whose last letter takes a value, is that flag's value.
## * under ``colonValues``, ``--flag:<partial>`` completes like
##   ``--flag=<partial>``; under ``equalsTakesNext``, a word that does not
##   start with ``-`` after ``--flag=`` (or ``--flag:``) is that flag's
##   value, a switch's included (``true`` and ``false``), and a word that
##   starts with ``-`` there is completed as a flag.
## * any other word is a subcommand word or a positional: the subcommands
##   of the command reached so far (their names, or an alias when the name
##   does not match what was typed), followed by the values of the
##   positional the word fills. Under ``commandMatching ignoreCase |
##   ignoreStyle`` what was typed is compared with a subcommand word in
##   that mode (``LI`` offers ``list``), and the word offered is the
##   declared one; a shell that filters candidates by what was typed may
##   drop it. A subcommand declared ``shadowedByWord = true`` is offered
##   like any other (help lists it too); the words after the reserved word
##   are not walked into it where the rule makes the word a request, as the
##   parser never reaches it there.
## * once a ``rest`` positional has taken a word, or would take the word
##   under the cursor, every word is that positional's: nothing is offered
##   but its own values (its ``values`` or completer; none when it has
##   neither), no flag and no subcommand.
##
## A flag's or a positional's values are its closed value set (``values``,
## or every value of an enum type), else what its ``complete`` completer
## returns (``clispec/completers``), else ``true`` and ``false`` for a
## switch written as ``--flag=``. Only values that start with what was
## typed are offered. For a list with a ``separator``, the element after
## the last separator is completed and the earlier ones are kept.
##
## Visibility decides what is offered, as it decides what help lists:
## ``hidden`` commands and parameters, and ``internal`` parameters, are
## never offered; an ``internal`` subcommand is offered only inside its
## namespace (by the command that holds it, unless that is the root, whose
## completion is the program's primary one). A value of a parameter the user
## typed explicitly is completed whatever its visibility. Candidates come in
## declaration order; descriptions are the declared ``help`` texts.
##
## The engine never raises: a word it cannot place is skipped, and a
## completer that raises contributes nothing.
##
## The protocol
## ============
##
## A shell's completion script (``clispec/completion_scripts``) runs the
## program itself with a hidden first word, ``__complete`` by default
## (``CliOptions.completionEntry``):
##
## .. code-block::
##   <program> __complete <shell> <arguments...>
##
## and prints what it writes to standard output. ``<shell>`` says how the
## arguments are given and how the answer is written:
##
## ============== ========================================= ===================================================
## shell          arguments                                 each line of the answer
## ============== ========================================= ===================================================
## ``bash``       ``$COMP_WORDBREAKS``, then the command    the text that replaces the word bash completes, quoted
##                line up to the cursor (``COMP_LINE``)     for bash (see below)
## ``zsh``        the words after the program name, the     ``<value>`` or ``<value><TAB><description>``
##                last one being completed, unquoted
## ``fish``       the same                                  ``<value>`` or ``<value><TAB><description>``
## ``powershell`` the same, each written as ``:`` and the     ``<completion text><TAB><list text><TAB><tooltip>``,
##                base64 of its UTF-8 bytes                 the completion text quoted for PowerShell
## ============== ========================================= ===================================================
##
## Bash gives a completion function its words split at the characters in
## ``COMP_WORDBREAKS`` (``=`` and ``:`` among them), so ``--out=fi`` arrives
## as three words; the engine therefore reads the command line itself,
## with the shell's quoting rules (single and double quotes, backslash),
## starting at the last unquoted ``;``, ``|``, ``&`` or ``(``, and answers
## with what replaces the part bash completes: the text after the last
## word-break character, or after an opening quote the word is still
## inside. Outside quotes the text is backslash-quoted.
##
## PowerShell's argument passing to native programs drops empty arguments
## and mangles quotes in some versions, which is why its words are encoded.
##
## Values and descriptions never contain a line break or a tab in the
## answer: a value that does is not offered, and a description has them
## replaced by spaces.
##
## The protocol is part of the program's interface: an installed script may
## be older than the program it calls. Within these shell names the
## arguments and the answer only change compatibly.
##
## A generated program answers the request from ``load``
## (``clispec/program``), which raises ``CliCompletionRequest``, a
## ``CliHelpRequest`` whose ``text`` is the answer: a program that prints a
## help request's text and exits 0 answers completion requests too. A
## program that dispatches some words itself before parsing (a thin client
## that hands everything but a few commands to another executable, say)
## forwards ``__complete ...`` unchanged to the executable that holds the
## description.

import std/[base64, options, strutils]

import ./[model, grammar, errors, help, parser, completers]

export completers

type
  CliShell* = enum
    ## The shells clispec writes completion scripts for.
    cshBash = "bash"
    cshZsh = "zsh"
    cshFish = "fish"
    cshPowerShell = "powershell"

  CliCompletionRequest* = object of CliHelpRequest
    ## The program was run as ``<program> __complete <shell> ...`` by a
    ## completion script. ``text`` (inherited) is the answer to print to
    ## standard output; the program then exits 0.
    shell*: string
      ## The shell named in the request.

func cliCompletionEntry*(options: CliOptions): string =
  ## The word that asks for completion under ``options``.
  if options.completionEntry.len > 0: options.completionEntry
  else: DefaultCompletionEntry

func cliIsCompletionRequest*(argv: openArray[string];
                             options = CliOptions()): bool =
  ## Whether ``argv`` (without the program name) is a completion request.
  not options.disableCompletionEntry and argv.len > 0 and
    argv[0] == cliCompletionEntry(options)

func cliParseShell*(name: string; shell: var CliShell): bool =
  ## Reads a shell name (``bash``, ``zsh``, ``fish``, ``powershell``; ``pwsh``
  ## is accepted for PowerShell). False for any other name.
  case name.toLowerAscii
  of "bash": shell = cshBash
  of "zsh": shell = cshZsh
  of "fish": shell = cshFish
  of "powershell", "pwsh": shell = cshPowerShell
  else: return false
  true

# ---------------------------------------------------------------------------
# The engine.
# ---------------------------------------------------------------------------

type
  Walk = object
    ## Where the words before the cursor left the parse.
    node: int
    terminated: bool
    pendingValue: int
      ## A flag whose value the next word is, or -1.
    optionalNext: int
      ## A bare ``acceptsNextWord`` flag whose value the next word may be,
      ## or -1.
    attachedNext: int
      ## Under ``equalsTakesNext``, after ``--flag=``: the flag whose value
      ## the next word is when it does not start with ``-``; -2 when that
      ## word is consumed but completes as nothing (an unknown flag, a
      ## negation or a counted flag); -1 otherwise.
    positionals: int
      ## Bare words placed as positionals of the current command.
    rest: int
      ## The ``rest`` positional that has taken the words from some point
      ## on (every word after it is its), or -1.

proc descend(g: CliGrammar; w: var Walk) =
  while g.commands[w.node].children.len == 0 and
      g.commands[w.node].callChild >= 0:
    w.node = g.commands[w.node].callChild

proc enter(g: CliGrammar; w: var Walk; next: int) =
  w.node = next
  w.positionals = 0
  descend(g, w)

func takesNextWord(p: CliGrammarParam): bool =
  ## A flag written alone takes the next word as its value.
  not (p.isSwitch or p.counted or p.hasOptionalValue) and
    p.format == cafSeparate

func takesValue(p: CliGrammarParam): bool =
  not (p.isSwitch or p.counted)

func callScope(g: CliGrammar; node: int): int =
  ## The call: whose flags a command with subcommands also accepts, or -1.
  if g.commands[node].children.len > 0: g.commands[node].callChild else: -1

proc walkFlag(g: CliGrammar; w: var Walk; word: string) =
  ## A flag word before the cursor.
  var m = cliMatchFlagWord(g, g.commands[w.node].params, word)
  if not m.found:
    let call = callScope(g, w.node)
    if call >= 0:
      m = cliMatchFlagWord(g, g.commands[call].params, word)
      if m.found:
        enter(g, w, call)
  if cprEqualsTakesNext in g.parseRules and word.startsWith("--") and
      cliValueSeparator(g, word) == word.high:
    w.attachedNext = if m.found and not m.negated and
                         not g.params[m.id].counted: m.id
                     else: -2
    return
  if m.found:
    let p = g.params[m.id]
    if not m.negated and m.attached.isNone and takesNextWord(p):
      w.pendingValue = m.id
    elif not m.negated and m.attached.isNone and p.hasOptionalValue and
        p.acceptsNextWord:
      w.optionalNext = m.id
    return
  if word.startsWith("--"):
    return
  # A cluster of short flags: the letter that takes a value takes the rest
  # of the word, or the next word when it is last.
  var scopes = @[w.node]
  let call = callScope(g, w.node)
  if call >= 0:
    scopes.add(call)
  for scope in scopes:
    var ok = true
    var pending = -1
    var optional = -1
    for k in 1 ..< word.len:
      let id = cliFindShort(g, g.commands[scope].params, word[k])
      if id < 0:
        ok = false
        break
      let p = g.params[id]
      if takesValue(p):
        if k == word.high and not p.hasOptionalValue:
          pending = id
        elif k == word.high and p.acceptsNextWord:
          optional = id
        break
    if ok:
      if scope != w.node:
        enter(g, w, scope)
      w.pendingValue = pending
      w.optionalNext = optional
      return

func restStarts(g: CliGrammar; w: Walk): int =
  ## The ``rest`` positional that takes the next word and every one after
  ## it, as the parser decides it, or -1.
  if g.commands[w.node].children.len > 0:
    return -1
  let r = cliRestParam(g, w.node)
  if r.id >= 0 and w.positionals >= r.index: r.id else: -1

proc walk(g: CliGrammar; words: openArray[string];
          options: CliOptions): Walk =
  result = Walk(pendingValue: -1, optionalNext: -1, attachedNext: -1,
    rest: -1)
  descend(g, result)
  for word in words:
    if result.rest >= 0:
      continue
    if result.pendingValue >= 0:
      result.pendingValue = -1
      continue
    if result.attachedNext != -1:
      result.attachedNext = -1
      if word.len == 0 or word[0] != '-':
        continue
    if result.optionalNext >= 0:
      let id = result.optionalNext
      result.optionalNext = -1
      if cliAcceptsWord(g, id, word, options):
        continue
    result.rest = restStarts(g, result)
    if result.rest >= 0:
      continue
    if not result.terminated and word == "--":
      result.terminated = true
      continue
    if result.terminated or word.len < 2 or word[0] != '-':
      let cmd = g.commands[result.node]
      if cmd.children.len > 0:
        # A word that asks for help or the version (``helpWord``,
        # ``versionWord``) never reaches a ``shadowedByWord`` subcommand:
        # the words after it are walked as if no subcommand answered to it.
        if not result.terminated and not cliIsHelpWord(g, word, options) and
            not cliIsVersionWord(g, word, options):
          let child = cliChildNamed(g, result.node, word)
          if child >= 0:
            enter(g, result, child)
            continue
        if cmd.callChild >= 0:
          enter(g, result, cmd.callChild)
          result.rest = restStarts(g, result)
          if result.rest >= 0:
            continue
      inc result.positionals
      continue
    walkFlag(g, result, word)

proc addCandidate(result: var seq[CliCompletion]; value, description: string) =
  for c in result:
    if c.value == value:
      return
  result.add(CliCompletion(value: value, description: description))

proc valueCandidates(g: CliGrammar; completers: openArray[CliCompleter];
                     id: int; typed: string; w: Walk;
                     words: openArray[string]; switchValues: bool):
    seq[CliCompletion] =
  ## The values of parameter ``id`` that start with ``typed``.
  let p = g.params[id]
  var head = ""
  var prefix = typed
  if p.separator.len > 0:
    let cut = typed.rfind(p.separator)
    if cut >= 0:
      head = typed[0 ..< cut + p.separator.len]
      prefix = typed[cut + p.separator.len .. ^1]
  var offered: seq[CliCompletion] = @[]
  if p.choices.len > 0:
    offered = cliCompletions(p.choices)
  elif id < completers.len and completers[id] != nil:
    var path: seq[string] = @[]
    var cmd = p.declaredBy
    if g.commands[cmd].isCall:
      cmd = g.commands[cmd].parent
    path = g.commands[cmd].path
    let ctx = CliCompletionContext(program: g.program, commandPath: path,
      param: p.name, words: @words, prefix: prefix)
    try:
      offered = completers[id](ctx)
    except CatchableError:
      offered = @[]
  elif p.isSwitch and switchValues:
    offered = cliCompletions(["true", "false"])
  for c in offered:
    if c.value.startsWith(prefix):
      result.addCandidate(head & c.value, c.description)

proc flagCandidates(g: CliGrammar; w: Walk; typed: string;
                    options: CliOptions): seq[CliCompletion] =
  var scope = g.commands[w.node].params
  let call = callScope(g, w.node)
  if call >= 0:
    for id in g.commands[call].params:
      if id notin scope:
        scope.add(id)
  var spelled: seq[string] = @[]
  for id in scope:
    let p = g.params[id]
    if p.kind != cpkFlag or csCli notin p.sources or
        p.visibility != cvShown:
      continue
    let equalsOnly = takesValue(p) and not p.hasOptionalValue and
      p.format == cafEquals
    var spellings = @["--" & cliLongName(p) & (if equalsOnly: "=" else: "")]
    if p.negatable:
      spellings.add("--no-" & cliLongName(p))
    if p.alias.len > 0 and p.alias.startsWith("-") and
        p.alias != "--" & cliLongName(p) and
        not (p.format == cafConcat and takesValue(p)):
      spellings.add(p.alias & (if equalsOnly: "=" else: ""))
    if p.short != '\0':
      spellings.add("-" & p.short)
    for s in spellings:
      spelled.add(s)
      if s.startsWith(typed):
        result.addCandidate(s, p.help)
  if not options.disableHelpFlag:
    let spellings = if cprLongHelpOnly in g.parseRules: @["--help"]
                    else: @["--help", "-h"]
    for s in spellings:
      if s notin spelled and s.startsWith(typed):
        result.addCandidate(s, "Show help")

proc attachedValueCandidates(g: CliGrammar;
                             completers: openArray[CliCompleter]; w: Walk;
                             typed: string; words: openArray[string];
                             found: var bool): seq[CliCompletion] =
  ## ``--flag=<partial>``, ``-o=<partial>`` (an ``equals`` alias) or a
  ## ``concat`` alias followed by a partial value.
  var scopes = @[g.commands[w.node].params]
  let call = callScope(g, w.node)
  if call >= 0:
    scopes.add(g.commands[call].params)
  for scope in scopes:
    let m = cliMatchFlagWord(g, scope, typed)
    if m.found and m.attached.isSome and not m.negated:
      found = true
      let p = g.params[m.id]
      if p.counted:
        return
      let glue = typed[0 ..< typed.len - m.attached.get.len]
      for c in valueCandidates(g, completers, m.id, m.attached.get, w, words,
          switchValues = true):
        result.addCandidate(glue & c.value, c.description)
      return

func positionalSlot(g: CliGrammar; w: Walk): int =
  ## The positional the next bare word fills, or -1.
  var target = w.node
  if g.commands[target].children.len > 0:
    target = g.commands[target].callChild
    if target < 0:
      return -1
  let slots = cliPositionals(g, target)
  var placed = if target == w.node: w.positionals else: 0
  for id in slots:
    if g.params[id].repeated or g.params[id].isList:
      return id
    if placed == 0:
      return id
    dec placed
  -1

proc cliComplete*(g: CliGrammar; completers: openArray[CliCompleter];
                  words: openArray[string]; cursor: int;
                  options = CliOptions()): seq[CliCompletion] {.raises: [].} =
  ## The candidates for ``words[cursor]`` (an empty word when ``cursor ==
  ## words.len``), given the words before it. ``words`` excludes the
  ## program name. ``completers[id]`` is parameter ``id``'s completer (nil,
  ## or past the end, when it has none). See the module documentation.
  let at = max(0, min(cursor, words.len))
  let before = words[0 ..< at]
  let typed = if at < words.len: words[at] else: ""
  let w = walk(g, before, options)
  let rest = if w.rest >= 0: w.rest else: restStarts(g, w)
  if rest >= 0 and w.pendingValue < 0 and w.attachedNext == -1 and
      w.optionalNext < 0:
    # Inside the rest of the command line, nothing is a flag or a
    # subcommand: only the rest positional's own values are offered.
    return valueCandidates(g, completers, rest, typed, w, before,
      switchValues = false)
  if w.pendingValue >= 0:
    return valueCandidates(g, completers, w.pendingValue, typed, w, before,
      switchValues = false)
  if w.attachedNext != -1 and not typed.startsWith("-"):
    if w.attachedNext >= 0:
      return valueCandidates(g, completers, w.attachedNext, typed, w, before,
        switchValues = true)
    return @[]
  if w.optionalNext >= 0 and not typed.startsWith("-"):
    # The word after a bare ``acceptsNextWord`` flag may be its value, or
    # whatever would come next without it.
    for c in valueCandidates(g, completers, w.optionalNext, typed, w, before,
        switchValues = false):
      result.addCandidate(c.value, c.description)
  if not w.terminated and typed.startsWith("-"):
    var found = false
    if typed.len > 1:
      let attached = attachedValueCandidates(g, completers, w, typed, before,
        found)
      if found:
        return attached
    return flagCandidates(g, w, typed, options)
  if not w.terminated and g.commands[w.node].children.len > 0:
    for child in g.commands[w.node].children:
      if not cliListsCommand(g, w.node, child):
        continue
      let c = g.commands[child]
      let mode = g.commandMatching
      if cliStartsWithSpelling(mode, c.name, typed):
        result.addCandidate(c.name, c.help)
      else:
        for alias in c.aliases:
          if cliStartsWithSpelling(mode, alias, typed):
            result.addCandidate(alias, c.help)
            break
  let slot = positionalSlot(g, w)
  if slot >= 0:
    for c in valueCandidates(g, completers, slot, typed, w, before,
        switchValues = false):
      result.addCandidate(c.value, c.description)

# ---------------------------------------------------------------------------
# Reading a bash command line.
# ---------------------------------------------------------------------------

type
  ShellLine* = object
    ## A command line read with POSIX shell quoting, up to the cursor.
    words*: seq[string]
      ## The words of the last command, unquoted, the program name first.
      ## The last one is the word under the cursor (possibly empty).
    raw*: string
      ## The word under the cursor as typed.
    rawUnquoted*: seq[int]
      ## For each byte of ``raw``, the length of its unquoted value up to
      ## and including that byte.
    openQuote*: int
      ## The index in ``raw`` of the quote the word is still inside, or -1.

func cliReadShellLine*(line: string): ShellLine =
  ## Splits ``line`` into words with POSIX shell quoting (single quotes,
  ## double quotes with backslash escapes of ``$`` ``\``` ``"`` ``\``, and
  ## backslash outside quotes). Unquoted ``;``, ``|``, ``&``, ``(`` and
  ## ``)`` end a command, so only the words of the last one are kept;
  ## unquoted ``<`` and ``>`` end a word. A backslash before a line break
  ## (outside single quotes) continues the line and is removed. Expansions
  ## are not performed, and ``$'...'`` is read as ``$`` followed by a
  ## single-quoted string.
  var words: seq[string] = @[]
  var cur = ""
  var raw = ""
  var rawLens: seq[int] = @[]
  var inWord = false
  var quote = '\0'
  var openAt = -1
  var i = 0
  proc finish() =
    if inWord:
      words.add(cur)
    cur = ""
    raw = ""
    rawLens = @[]
    inWord = false
    openAt = -1
  while i < line.len:
    let ch = line[i]
    if quote == '\'':
      if ch == '\'':
        quote = '\0'
        openAt = -1
      else:
        cur.add(ch)
      raw.add(ch)
      rawLens.add(cur.len)
      inc i
      continue
    if quote == '"':
      if ch == '"':
        quote = '\0'
        openAt = -1
        raw.add(ch)
        rawLens.add(cur.len)
      elif ch == '\\' and i + 1 < line.len and line[i + 1] == '\n':
        # A line continuation: both characters are removed.
        raw.add(ch)
        rawLens.add(cur.len)
        raw.add('\n')
        rawLens.add(cur.len)
        inc i
      elif ch == '\\' and i + 1 < line.len and line[i + 1] in {'$', '`', '"',
          '\\'}:
        cur.add(line[i + 1])
        raw.add(ch)
        rawLens.add(cur.len - 1)
        raw.add(line[i + 1])
        rawLens.add(cur.len)
        inc i
      else:
        cur.add(ch)
        raw.add(ch)
        rawLens.add(cur.len)
      inc i
      continue
    case ch
    of ' ', '\t', '\n':
      finish()
    of ';', '|', '&', '(', ')':
      finish()
      words = @[]
    of '<', '>':
      finish()
    of '\'', '"':
      quote = ch
      openAt = raw.len
      inWord = true
      raw.add(ch)
      rawLens.add(cur.len)
    of '\\':
      if i + 1 < line.len and line[i + 1] == '\n':
        # A line continuation, outside a word or inside one: removed.
        if inWord:
          raw.add(ch)
          rawLens.add(cur.len)
          raw.add('\n')
          rawLens.add(cur.len)
        i += 2
        continue
      inWord = true
      raw.add(ch)
      rawLens.add(cur.len)
      if i + 1 < line.len:
        cur.add(line[i + 1])
        raw.add(line[i + 1])
        rawLens.add(cur.len)
        inc i
    else:
      inWord = true
      cur.add(ch)
      raw.add(ch)
      rawLens.add(cur.len)
    inc i
  words.add(cur)
  ShellLine(words: words, raw: raw, rawUnquoted: rawLens, openQuote: openAt)

const bashSpecial = {' ', '\t', '\n', '\'', '"', '\\', '$', '`', '|', '&',
  ';', '<', '>', '(', ')', '*', '?', '[', ']', '!', '{', '}'}

func bashQuote(s: string; atWordStart: bool; quote: char): string =
  ## ``s`` written for bash: inside an open single quote as is, inside an
  ## open double quote with ``$`` ``\``` ``"`` ``\`` escaped, otherwise with
  ## every special character backslash-escaped (``#`` and ``~`` only at the
  ## start of a word).
  for i, ch in s:
    case quote
    of '\'':
      result.add(ch)
    of '"':
      if ch in {'$', '`', '"', '\\'}:
        result.add('\\')
      result.add(ch)
    else:
      if ch in bashSpecial or (i == 0 and atWordStart and ch in {'#', '~'}):
        result.add('\\')
      result.add(ch)

func bashReplacements(line: ShellLine; wordbreaks: string;
                      values: openArray[CliCompletion]): seq[string] =
  ## What replaces the part of the word bash completes, for each value.
  ## That part starts after the opening quote the word is still inside, or
  ## else after the last unquoted word-break character.
  var start = 0
  var quote = '\0'
  if line.openQuote >= 0:
    start = line.openQuote + 1
    quote = line.raw[line.openQuote]
  else:
    var q = '\0'
    var i = 0
    while i < line.raw.len:
      let ch = line.raw[i]
      if q != '\0':
        if ch == q: q = '\0'
        elif q == '"' and ch == '\\': inc i
      elif ch in {'\'', '"'}:
        q = ch
      elif ch == '\\':
        inc i
      elif ch in wordbreaks and ch notin {' ', '\t', '\n'}:
        start = i + 1
      inc i
  let kept = if start == 0: 0 else: line.rawUnquoted[start - 1]
  let full = line.words[^1]
  for c in values:
    if c.value.len < kept or c.value[0 ..< kept] != full[0 ..< kept]:
      continue
    let rest = c.value[kept .. ^1]
    if quote == '\'' and '\'' in rest:
      continue
    result.add(bashQuote(rest, start == 0, quote))

const powerShellQuoteMarks = ["\u2018", "\u2019", "\u201A", "\u201B"]
  ## The typographic quotes PowerShell reads as a single quote.

func cliPowerShellSingleQuote*(s: string): string =
  ## ``s`` as a PowerShell single-quoted string: every single quote doubled,
  ## the typographic ones included, which PowerShell treats the same
  ## (https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_quoting_rules).
  result = "'"
  var i = 0
  while i < s.len:
    var mark = if s[i] == '\'': "'" else: ""
    for m in powerShellQuoteMarks:
      if s.continuesWith(m, i):
        mark = m
    if mark.len > 0:
      result.add(mark & mark)
      i += mark.len
    else:
      result.add(s[i])
      inc i
  result.add('\'')

func powerShellQuote(s: string): string =
  ## ``s`` as one PowerShell argument: as is when nothing in it is special,
  ## else single-quoted. PowerShell reads the typographic quotes and dashes
  ## as their ASCII counterparts, so they count as special too.
  const special = {' ', '\t', '\'', '"', '`', '$', '{', '}', '(', ')', '@',
    '#', ';', ',', '|', '&', '<', '>'}
  const specialText = ["\u2013", "\u2014", "\u2015", "\u2018", "\u2019",
    "\u201A", "\u201B", "\u201C", "\u201D", "\u201E"]
  var plain = s.len > 0
  for i, ch in s:
    if ch in special:
      plain = false
    elif ord(ch) >= 0x80:
      for t in specialText:
        if s.continuesWith(t, i):
          plain = false
  if plain: s else: cliPowerShellSingleQuote(s)

func oneLine(s: string): string =
  result = s
  for ch in ['\n', '\r', '\t']:
    result = result.replace($ch, " ")

func lineSafe(s: string): bool =
  '\n' notin s and '\r' notin s and '\t' notin s

proc cliCompletionReply*(g: CliGrammar; completers: openArray[CliCompleter];
                         args: openArray[string];
                         options = CliOptions()): string {.raises: [].} =
  ## The answer to ``<program> __complete <args...>`` (``args`` starts with
  ## the shell's name), as the module documentation describes it. An unknown
  ## shell or a malformed request gets an empty answer.
  if args.len < 1:
    return ""
  var shell: CliShell
  if not cliParseShell(args[0], shell):
    return ""
  var lines: seq[string] = @[]
  case shell
  of cshBash:
    if args.len < 3:
      return ""
    let line = cliReadShellLine(args[2])
    let words = line.words[1 .. ^1]
    var values: seq[CliCompletion] = @[]
    for c in cliComplete(g, completers, words, words.high, options):
      if lineSafe(c.value):
        values.add(c)
    lines = bashReplacements(line, args[1], values)
  of cshZsh, cshFish:
    let words = args[1 .. ^1]
    for c in cliComplete(g, completers, words, max(0, words.high), options):
      if lineSafe(c.value):
        lines.add(if c.description.len > 0: c.value & "\t" &
          oneLine(c.description) else: c.value)
  of cshPowerShell:
    var words: seq[string] = @[]
    for a in args[1 .. ^1]:
      if not a.startsWith(":"):
        return ""
      try:
        words.add(decode(a[1 .. ^1]))
      except ValueError:
        return ""
    for c in cliComplete(g, completers, words, max(0, words.high), options):
      if lineSafe(c.value):
        let tip = if c.description.len > 0: oneLine(c.description)
                  else: c.value
        lines.add(powerShellQuote(c.value) & "\t" & c.value & "\t" & tip)
  if lines.len == 0: "" else: lines.join("\n") & "\n"

proc cliCompletionCheck*(g: CliGrammar; completers: openArray[CliCompleter];
                         argv: openArray[string]; options = CliOptions()) {.
    raises: [CliCompletionRequest].} =
  ## Raises ``CliCompletionRequest`` with the answer when ``argv`` is a
  ## completion request (``cliIsCompletionRequest``); does nothing
  ## otherwise. Generated ``load`` procedures call it first.
  if not cliIsCompletionRequest(argv, options):
    return
  var text = ""
  text = cliCompletionReply(g, completers, argv[1 .. ^1], options)
  raise (ref CliCompletionRequest)(msg: "completion requested",
    shell: (if argv.len > 1: argv[1] else: ""), text: text)
