## The argv parser: from words to the values each parameter receives.
##
## Parsing runs in phases, each a separate procedure so that later layers
## (completion, and a library that adds configuration files and the
## environment as sources) reuse the ones they need:
##
## 1. ``cliTokenize`` walks argv against a ``CliGrammar``: it dispatches
##    subcommands, recognises every flag spelling and collects, for each
##    parameter, the *candidates* the command line supplies, each with the
##    argv index and the spelling it came from (``clispec/candidates``).
## 2. ``cliMerge`` decides, for each parameter, which candidates make up its
##    value: every occurrence of a list or a counted flag, the last one of
##    anything else. A library that merges other sources with the command
##    line replaces this phase with its own, which fills the same
##    ``CliResolution``.
## 3. ``cliDecide`` settles what each parameter of the selected commands
##    gets: its merged candidates, a value implied by another parameter, its
##    default, or nothing, and reports a required parameter that got nothing.
##    It runs after the merge, so a default never stands in for a value a
##    source supplied.
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
##   ``--no-<long name>``.
## * A flag's long spelling is ``--`` followed by its name in the command
##   line's naming convention, or its override (``CliGrammarParam.longName``,
##   ``clispec/model``, "Naming conventions"); the declared name is not
##   accepted when the two differ.
## * ``counted = true``: each occurrence (``-v``, ``-vv``) adds one.
## * ``optionalValue``: bare, the flag takes that value; ``--flag=value``
##   gives another. It never takes the next word.
## * A list parameter (a ``seq``) collects every occurrence, and with a
##   ``separator`` each occurrence is split on it.
## * ``--`` ends the flags: every later word is a positional (under
##   ``parsing loneDashesAreFlags`` it is an unknown flag instead, as is a
##   lone ``-``). When the command that runs declares an ``afterSeparator``
##   positional, every word after its first ``--`` is that positional's,
##   exactly as written, and no word before it is. A ``--`` that is a
##   flag's value (``--flag --``, ``--flag=--``) ends nothing.
## * The first bare word after a command that has subcommands names one (or
##   one of its ``aliases``). When the command also has a ``call:``, a word
##   that names no subcommand, or a flag (or a cluster of short flags) only
##   the ``call:`` declares, runs the ``call:`` instead.
## * Positionals fill in ``position`` order; a list positional takes every
##   word the positionals declared after it do not need.
## * ``--help`` and ``-h`` request help (``--help=json`` the machine-readable
##   form) unless the program turns them off or declares those spellings
##   itself. In a program that declares a ``tier = secondary`` subcommand,
##   ``--help-all`` does too (the long page, listing every tier), and so
##   does ``help --all`` under ``parsing helpWord``; elsewhere
##   ``--help-all`` is an ordinary spelling, unknown unless a flag declares
##   it.
## * Under ``parsing helpWord`` / ``versionWord``, the bare word ``help`` /
##   ``version`` where a subcommand word is expected is a request, checked
##   before the subcommands: a subcommand declared ``shadowedByWord = true``
##   that answers to the word is reached by it only where the rule does not
##   apply (``disableHelpFlag``; no ``versionText``), and by its other words
##   always.
## * ``--version`` requests the version (``CliVersionRequest``) when the
##   program gives a version text (``CliOptions.versionText``) and declares
##   no ``--version`` flag of its own; it is compared under ``flagMatching``
##   and takes an attached value only under ``helpWithAnyValue``.
##
## Opt-in rules
## ============
##
## A description can opt into rules that confutils' type-based loader
## followed (``CliFlagMatching``, ``CliParseRule`` in ``clispec/model``):
## ``flagMatching ignoreCase | ignoreStyle`` accepts a spelling that matches
## in that mode when none matches exactly; ``parsing`` names
## ``shortEquals`` (``-o=value``), ``helpWithAnyValue`` (``--help=1``),
## ``helpInCluster`` (``-help``), ``valueErrorsBeforeHelp``,
## ``switchesRefuseFalse``, ``lenientSwitchValues``, ``colonValues``
## (``--name:value``, ``-o:value``), ``equalsTakesNext`` (``--name=
## value``), ``helpWord`` and ``versionWord`` (the bare words ``help`` and
## ``version`` where a subcommand word is expected), ``longHelpOnly``
## (``-h`` is not help), ``loneDashesAreFlags`` (a lone ``-`` or ``--`` is
## an unknown flag with an empty spelling, so ``--`` ends nothing) and
## ``exactOneLetterFlags`` (``-T`` is not ``-t`` under ``flagMatching``);
## ``commandMatching ignoreCase | ignoreStyle``
## compares subcommand words in that mode when none matches exactly. A
## positional declared ``rest = true`` takes, once the positionals before
## it have their words, every remaining word verbatim. On a flag,
## ``acceptsNextWord`` lets an optional value be the next word when it is a
## valid value, ``refuseFalse`` makes a switch's false value the error
## ``cekSwitchFalseValue``, and ``alsoSets`` adds, for each occurrence, a
## candidate for another parameter at the same argv index (``setBy`` names
## the flag), which the merge orders with that parameter's own. The rules
## that need to know whether a text is a valid value use
## ``CliOptions.valueCheck``, which the generated ``load`` supplies.

import std/[options, strutils]

import ./[model, grammar, errors, values, help, candidates]

export errors, values, candidates

type
  CliValueCheck* = proc (id: int; text: string): string {.raises: [].}
    ## Whether ``text`` is a valid value of parameter ``id`` (it converts to
    ## the parameter's type and is in its ``values``): empty when it is,
    ## else what would have been accepted, worded as the conversion words
    ## it (``an integer``, ``one of: a, b``). The generated ``load``
    ## supplies one (``cliValueCheckName``); the parser uses it for
    ## ``acceptsNextWord`` and ``valueErrorsBeforeHelp``.

  CliOptions* = object
    ## How a program wants its command line parsed.
    program*: string
      ## The program's name in help and errors; empty means the name its
      ## description was given.
    usageExitCode*: int
      ## The exit code a usage error carries (``DefaultUsageExitCode``, 2,
      ## when zero).
    disableHelpFlag*: bool
      ## Do not treat ``--help`` / ``-h`` (nor, under ``helpWord``, the word
      ## ``help``) as a request for help.
    versionText*: string
      ## The program's version, as it wants it printed. When not empty,
      ## ``--version`` (and under ``parsing versionWord`` the word
      ## ``version``) raises ``CliVersionRequest`` carrying it; empty (the
      ## default), neither means anything special.
    completionEntry*: string
      ## The hidden first word through which a shell's completion script
      ## asks the program for candidates (``clispec/completion``);
      ## ``DefaultCompletionEntry`` (``__complete``) when empty.
    disableCompletionEntry*: bool
      ## Do not treat that word as a completion request: the program
      ## answers completion requests itself, or not at all.
    helpLayout*: CliHelpLayout = cliDefaultHelpLayout
      ## The layout of the help text a ``CliHelpRequest`` carries
      ## (``clispec/help``): the standard page unless set
      ## (``cliClassicHelpLayout`` keeps the classic one). ``-h`` gives its
      ## short form, ``--help`` (and the word ``help``) its long one; in the
      ## standard style its options table lists ``--version`` (``Print
      ## version``, unless ``versionFlag`` words it) when ``versionText``
      ## is set.
    valueCheck*: CliValueCheck
      ## The value check of the program's parameters (``CliValueCheck``).
      ## The generated ``load`` fills it in when it is nil.
    color*: CliColorMode
      ## Whether ``cliPrintHelp`` and ``cliPrintError`` style what they
      ## print (``clispec/styles``): ``ccmAuto`` (the default) when the
      ## stream is a terminal, ``NO_COLOR`` is unset or empty and ``TERM``
      ## is not ``dumb``; ``ccmAlways``; ``ccmNever``. The help requests
      ## and usage errors the parser raises carry it.

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
      ## Per parameter id: the candidates the value is made of
      ## (``cliMerge``), in the order they were considered.
    overridden*: seq[seq[CliCandidate]]
      ## Per parameter id: the candidates that are not part of the value.
    decisions*: seq[CliDecision]
      ## Per parameter id; ``cdkUnset`` for parameters of commands that were
      ## not selected.
    exitCode*: int
    program*: string
    color*: CliColorMode
      ## ``CliOptions.color``, for the usage errors raised after
      ## tokenizing.
    disableHelpFlag*: bool
      ## ``CliOptions.disableHelpFlag``, likewise (an error then names no
      ## help command).

func cliWithValueCheck*(options: CliOptions;
                        check: CliValueCheck): CliOptions =
  ## ``options`` with ``check`` as its ``valueCheck`` unless it has one.
  result = options
  if result.valueCheck.isNil:
    result.valueCheck = check

func effectiveProgram(g: CliGrammar; options: CliOptions): string =
  if options.program.len > 0: options.program else: g.program

func effectiveExitCode(options: CliOptions): int =
  if options.usageExitCode == 0: DefaultUsageExitCode
  else: options.usageExitCode

func subcommandWords(g: CliGrammar; command: int): string =
  cliSubcommandWords(g, command).join(", ")

const DefaultCompletionEntry* = "__complete"
  ## The word ``CliOptions.completionEntry`` defaults to.

type
  FlagMatch* = object
    ## A word read as one flag (``cliMatchFlagWord``).
    found*: bool
    id*: int
      ## The parameter id.
    spelling*: string
      ## The spelling the word used (``--jobs``, ``-j``, ``--no-color``).
    negated*: bool
    attached*: Option[string]
      ## A value written in the same word (``--x=v``, ``-ov``).

func findFlag(g: CliGrammar; scope: seq[int];
              pred: proc (p: CliGrammarParam): bool {.noSideEffect, raises: [].}): int =
  ## The last flag of ``scope`` (the most nested declaration) matching.
  for i in countdown(scope.high, 0):
    let p = g.params[scope[i]]
    if p.kind == cpkFlag and csCli in p.sources and pred(p):
      return scope[i]
  -1

func matchModes(g: CliGrammar): seq[CliFlagMatching] =
  ## The matching modes to try, in order: an exact spelling always wins.
  if g.flagMatching == cfmExact: @[cfmExact]
  else: @[cfmExact, g.flagMatching]

func dashlessLen(spelling: string): int =
  ## The length of a spelling's name: what follows its ``-`` or ``--``.
  var k = 0
  while k < spelling.len and k < 2 and spelling[k] == '-':
    inc k
  spelling.len - k

func sameFlagSpelling(g: CliGrammar; mode: CliFlagMatching;
                      word, spelling: string): bool =
  ## ``cliSameSpelling`` for flag spellings: under ``exactOneLetterFlags``,
  ## a word or spelling whose name is one character is compared exactly.
  if mode != cfmExact and cprExactOneLetterFlags in g.parseRules and
      (dashlessLen(word) == 1 or dashlessLen(spelling) == 1):
    word == spelling
  else:
    cliSameSpelling(mode, word, spelling)

func cliIsLoneDash*(g: CliGrammar; word: string): bool =
  ## Under ``parsing loneDashesAreFlags``, whether ``word`` is a lone ``-``
  ## or ``--``, which is then an unknown flag wherever a flag may stand.
  cprLoneDashesAreFlags in g.parseRules and word in ["-", "--"]

func cliValueSeparator*(g: CliGrammar; word: string): int =
  ## Where the spelling of ``word``, a ``--`` word, ends and the value
  ## written in the same word begins: the index of its first ``=`` (under
  ## ``colonValues``, of its first ``:`` or ``=``), or -1.
  result = word.find('=')
  if cprColonValues in g.parseRules:
    let colon = word.find(':')
    if colon >= 0 and (result < 0 or colon < result):
      result = colon

func matchLong(g: CliGrammar; scope: seq[int]; word: string): FlagMatch =
  ## A word starting with ``--``: an exact spelling, ``<spelling>=value``
  ## (or ``<spelling>:value`` under ``colonValues``), ``--no-<longName>``
  ## or a ``concat`` spelling followed by its value.
  ## Under a ``flagMatching`` other than ``exact``, a spelling that matches
  ## in that mode is accepted when none matches exactly.
  let eq = cliValueSeparator(g, word)
  let head = if eq >= 0: word[0 ..< eq] else: word
  for listed in matchModes(g):
    let mode = listed
    let id = findFlag(g, scope, proc (p: CliGrammarParam): bool =
      sameFlagSpelling(g, mode, head, "--" & cliLongName(p)) or
        (p.alias.len > 0 and sameFlagSpelling(g, mode, head, p.alias)))
    if id >= 0:
      result = FlagMatch(found: true, id: id, spelling: head)
      if eq >= 0:
        result.attached = some(word[eq + 1 .. ^1])
      return
  for listed in matchModes(g):
    let mode = listed
    if head.len > 5 and cliSameSpelling(mode, head[0 .. 4], "--no-"):
      let name = head[5 .. ^1]
      let neg = findFlag(g, scope, proc (p: CliGrammarParam): bool =
        p.negatable and sameFlagSpelling(g, mode, name, cliLongName(p)))
      if neg >= 0:
        result = FlagMatch(found: true, id: neg, spelling: head,
          negated: true)
        if eq >= 0:
          result.attached = some(word[eq + 1 .. ^1])
        return
  var best = -1
  for i in countdown(scope.high, 0):
    let p = g.params[scope[i]]
    if p.kind == cpkFlag and csCli in p.sources and p.format == cafConcat and
        p.alias.len > 0 and word.startsWith(p.alias) and
        word.len > p.alias.len:
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
  for listed in matchModes(g):
    let mode = listed
    let id = findFlag(g, scope, proc (p: CliGrammarParam): bool =
      sameFlagSpelling(g, mode, word, p.alias) or
        (p.short != '\0' and sameFlagSpelling(g, mode, word, "-" & p.short)))
    if id >= 0:
      return FlagMatch(found: true, id: id, spelling: word)
  let eq = word.find('=')
  if eq > 0:
    let head = word[0 ..< eq]
    for listed in matchModes(g):
      let mode = listed
      let eid = findFlag(g, scope, proc (p: CliGrammarParam): bool =
        p.format == cafEquals and sameFlagSpelling(g, mode, head, p.alias))
      if eid >= 0:
        return FlagMatch(found: true, id: eid, spelling: head,
          attached: some(word[eq + 1 .. ^1]))
  var best = -1
  for i in countdown(scope.high, 0):
    let p = g.params[scope[i]]
    if p.kind == cpkFlag and csCli in p.sources and p.format == cafConcat and
        p.alias.len > 1 and word.startsWith(p.alias) and
        word.len > p.alias.len:
      if best < 0 or p.alias.len > g.params[best].alias.len:
        best = scope[i]
  if best >= 0:
    let alias = g.params[best].alias
    return FlagMatch(found: true, id: best, spelling: alias,
      attached: some(word[alias.len .. ^1]))

func cliFindShort*(g: CliGrammar; scope: seq[int]; letter: char): int =
  ## The flag of ``scope`` whose ``short`` is ``letter`` (exactly, else
  ## under the program's ``flagMatching`` unless ``exactOneLetterFlags``
  ## keeps letters exact), or -1.
  for listed in matchModes(g):
    let mode = if cprExactOneLetterFlags in g.parseRules: cfmExact
               else: listed
    let id = findFlag(g, scope, proc (p: CliGrammarParam): bool =
      p.short != '\0' and cliSameLetter(mode, p.short, letter))
    if id >= 0:
      return id
  -1

func cliMatchFlagWord*(g: CliGrammar; scope: seq[int];
                       word: string): FlagMatch =
  ## Reads ``word`` (which starts with ``-``) as one flag of the parameters
  ## ``scope``, as the parser does: an exact spelling, ``--flag=value``,
  ## ``--no-<name>``, or a ``concat`` spelling followed by its value. A
  ## cluster of short flags is not read here.
  if word.startsWith("--"): matchLong(g, scope, word)
  else: matchSingleDash(g, scope, word)

func takesNoValue(p: CliGrammarParam): bool =
  p.isSwitch or p.counted

func cliIsHelpWord*(g: CliGrammar; word: string; options: CliOptions): bool =
  ## Whether ``word``, where a subcommand word is expected, asks for help
  ## under ``parsing helpWord`` (compared under ``commandMatching``; never
  ## with ``disableHelpFlag``). It does even when a subcommand declared
  ## ``shadowedByWord = true`` answers to it.
  cprHelpWord in g.parseRules and not options.disableHelpFlag and
    cliSameSpelling(g.commandMatching, word, "help")

func cliIsVersionWord*(g: CliGrammar; word: string; options: CliOptions):
    bool =
  ## Whether ``word``, where a subcommand word is expected, asks for the
  ## version under ``parsing versionWord``: only when the program gives a
  ## ``versionText``. It does even when a subcommand declared
  ## ``shadowedByWord = true`` answers to it.
  cprVersionWord in g.parseRules and options.versionText.len > 0 and
    cliSameSpelling(g.commandMatching, word, "version")

func isHelpSpelling(g: CliGrammar; scope: seq[int]; word: string;
                    options: CliOptions):
    tuple[help, json, long, all: bool] =
  ## ``--help``, ``--help=json`` or ``-h``, unless turned off or declared
  ## by the program for one of its own flags; in a program with
  ## ``secondary`` subcommands also ``--help-all`` (the long page with every
  ## tier), which takes the same values. ``--help`` is compared under the
  ## program's ``flagMatching``; with ``helpWithAnyValue``,
  ## ``--help=<anything>`` asks for help too.
  if options.disableHelpFlag:
    return
  let eq = if word.startsWith("--"): cliValueSeparator(g, word) else: -1
  let head = if eq >= 0: word[0 ..< eq] else: word
  let canonical = if head == "-h" and cprLongHelpOnly notin g.parseRules: "-h"
                  elif cliSameSpelling(g.flagMatching, head, "--help"):
                    "--help"
                  elif cliHasSecondaryCommands(g) and
                      cliSameSpelling(g.flagMatching, head, "--help-all"):
                    "--help-all"
                  else: ""
  if canonical.len == 0:
    return
  if findFlag(g, scope, proc (p: CliGrammarParam): bool =
      canonical in cliFlagSpellings(p)) >= 0:
    return
  let all = canonical == "--help-all"
  let long = canonical == "--help" or all
  if eq < 0:
    return (true, false, long, all)
  let value = word[eq + 1 .. ^1]
  if value == "json":
    return (true, true, long, all)
  if value == "text" or cprHelpWithAnyValue in g.parseRules:
    return (true, false, long, all)

func cliIsHelpAllWord*(g: CliGrammar; word: string): bool =
  ## Whether ``word``, right after the word ``help`` (``parsing helpWord``),
  ## turns that request into ``--help-all``'s: ``--all`` (compared under
  ## ``flagMatching``) in a program with ``secondary`` subcommands.
  cliHasSecondaryCommands(g) and
    cliSameSpelling(g.flagMatching, word, "--all")

func isVersionSpelling(g: CliGrammar; scope: seq[int]; word: string;
                       options: CliOptions): bool =
  ## ``--version`` (compared under ``flagMatching``) when the program has a
  ## version text and no flag of ``scope`` is spelt ``--version``;
  ## ``--version=<anything>`` too under ``helpWithAnyValue``.
  if options.versionText.len == 0 or not word.startsWith("--"):
    return false
  let eq = cliValueSeparator(g, word)
  let head = if eq >= 0: word[0 ..< eq] else: word
  if not cliSameSpelling(g.flagMatching, head, "--version"):
    return false
  if findFlag(g, scope, proc (p: CliGrammarParam): bool =
      "--version" in cliFlagSpellings(p)) >= 0:
    return false
  eq < 0 or cprHelpWithAnyValue in g.parseRules

func cliHelpCommandLine*(g: CliGrammar; command: int; program: string;
                         options = CliOptions()): string =
  ## The command line that prints the help of ``command``
  ## (``tool build --help``; ``-h`` when the command spells ``--help``
  ## itself), or empty when help is off (``disableHelpFlag``) or both
  ## spellings belong to the command's own flags. A ``call:`` is its
  ## holder's.
  if options.disableHelpFlag:
    return ""
  let holder = if g.commands[command].isCall: g.commands[command].parent
               else: command
  let scope = g.commands[holder].params
  var asked = @["--help"]
  if cprLongHelpOnly notin g.parseRules:
    asked.add("-h")
  for s in asked:
    let spelling = s
    if findFlag(g, scope, proc (p: CliGrammarParam): bool =
        spelling in cliFlagSpellings(p)) < 0:
      return (@[program] & g.commands[holder].path & @[spelling]).join(" ")
  ""

func cliAddErrorContext*(e: ref CliUsageError; g: CliGrammar; command: int;
                         options = CliOptions()) =
  ## Fills in what ``cliErrorText`` prints besides the message: the usage
  ## line of ``command``, the command line that prints its help and the
  ## program's ``color``. The parser calls it for every error it raises; a
  ## library that raises its own usage errors (another source's) calls it
  ## too.
  e.usage = cliUsageLine(g, command, e.program)
  e.helpCommand = cliHelpCommandLine(g, command, e.program, options)
  e.color = options.color

func dashless(spelling: string): string =
  var k = 0
  while k < spelling.len and k < 2 and spelling[k] == '-':
    inc k
  spelling[k .. ^1]

func cliSubcommandSuggestions*(g: CliGrammar; command: int; word: string;
                               options = CliOptions()): seq[string] =
  ## What an unknown subcommand ``word`` of ``command`` may have meant: the
  ## names of the subcommands its help lists (an alias that matches offers
  ## its command's name), and ``help`` / ``version`` where those words are
  ## requests (``cliSuggest``).
  var candidates: seq[CliSuggestionCandidate] = @[]
  for child in g.commands[command].children:
    if not cliListsCommand(g, command, child):
      continue
    let c = g.commands[child]
    for w in @[c.name] & c.aliases:
      candidates.add((w, c.name, c.name))
  for w in ["help", "version"]:
    if (w == "help" and cliIsHelpWord(g, w, options)) or
        (w == "version" and cliIsVersionWord(g, w, options)):
      candidates.add((w, w, w))
  cliSuggest(word, candidates)

func cliFlagSuggestions*(g: CliGrammar; command: int; word: string;
                         options = CliOptions()): seq[string] =
  ## What an unknown flag ``word`` given to ``command`` may have meant: the
  ## spellings, as written, of the flags the command accepts and lists in
  ## its help (``hidden`` and ``internal`` ones never; with a ``call:``
  ## beside subcommands, the ``call:``'s too), their ``--no-`` form, and
  ## ``--help`` and ``--version`` where they request help and the version.
  ## A one-letter ``-x`` is not offered. Spellings are compared without
  ## their leading dashes; one suggestion per flag (``cliSuggest``).
  let typed = dashless(word)
  if typed.len == 0:
    return
  var scope = g.commands[command].params
  if g.commands[command].children.len > 0 and
      g.commands[command].callChild >= 0:
    scope.add(g.commands[g.commands[command].callChild].params)
  var candidates: seq[CliSuggestionCandidate] = @[]
  for id in scope:
    let p = g.params[id]
    if p.kind != cpkFlag or csCli notin p.sources or
        p.visibility != cvShown:
      continue
    var spellings = cliFlagSpellings(p)
    if p.negatable:
      spellings.add("--no-" & cliLongName(p))
    for spelling in spellings:
      if spelling.len == 2 and spelling[0] == '-':
        continue
      candidates.add((dashless(spelling), spelling, $id))
  for spelling in ["--help", "--help-all", "--version"]:
    let asks = if spelling == "--version":
                 isVersionSpelling(g, scope, spelling, options)
               else: isHelpSpelling(g, scope, spelling, options).help
    if asks:
      candidates.add((dashless(spelling), spelling, spelling))
  cliSuggest(typed, candidates)

func retiredFlagMatches(g: CliGrammar; name, spelling: string;
                        byLetter: bool): bool =
  ## Whether the unknown flag ``spelling`` (as an error carries it: the
  ## flag name alone, or the whole word for a single-dash one) is the
  ## retired flag ``name``. With ``byLetter``, a one-letter ``-x`` matches
  ## a longer word that starts with it instead (``-xvalue``, ``-xv``): such
  ## a word is refused at its first letter, which is the retired one.
  if not byLetter:
    for mode in matchModes(g):
      if sameFlagSpelling(g, mode, spelling, name):
        return true
    return false
  if name.len == 2 and name[0] == '-' and name[1] != '-' and
      spelling.len > 2 and spelling[0] == '-' and spelling[1] != '-':
    let mode = if cprExactOneLetterFlags in g.parseRules: cfmExact
               else: g.flagMatching
    return cliSameLetter(mode, spelling[1], name[1])
  false

func cliRetiredMatch*(g: CliGrammar; command: int; kind: CliErrorKind;
                      spelling, value: string):
    tuple[found: bool; retired: CliRetired] =
  ## The ``retired`` declaration (``cliRetiredAt``) that an unknown flag or
  ## subcommand word refused at ``command`` is, if any. ``spelling`` and
  ## ``value`` are the error's (``CliUsageError``). A flag retired with one
  ## of its values (``--mode=legacy``) matches only that value written in
  ## the same word, and is preferred to the flag retired alone; flags are
  ## compared as the parser compares them (``flagMatching``), words under
  ## ``commandMatching``, values exactly.
  if kind notin {cekUnknownFlag, cekUnknownSubcommand} or spelling.len == 0:
    return
  let applying = cliRetiredAt(g, command)
  if kind == cekUnknownSubcommand:
    for a in applying:
      let r = a.retired
      if not cliRetiredIsFlag(r) and (r.spelling == spelling or
          cliSameSpelling(g.commandMatching, spelling, r.spelling)):
        return (true, r)
    return
  # Most specific first: a flag retired with this value, then the flag
  # retired alone, then a retired letter that starts the word.
  for (withValue, byLetter) in [(true, false), (false, false),
                                (false, true)]:
    for a in applying:
      let r = a.retired
      if not cliRetiredIsFlag(r):
        continue
      let parts = cliRetiredFlagParts(r)
      if parts.hasValue != withValue:
        continue
      if withValue and parts.value != value:
        continue
      if retiredFlagMatches(g, parts.name, spelling, byLetter):
        return (true, r)

func cliNameRetired*(e: ref CliUsageError; g: CliGrammar; command: int) =
  ## When ``e``, an unknown flag or subcommand word refused at ``command``,
  ## is a retired spelling (``cliRetiredMatch``): records the declaration
  ## (``retired``, ``replacement``), words the message with the
  ## replacement and drops the suggestions. The parser calls it for every
  ## such error; a library that raises its own calls it too.
  let m = cliRetiredMatch(g, command, e.kind, e.spelling, e.value)
  if not m.found:
    return
  e.retired = m.retired.spelling
  e.replacement = m.retired.replacement
  e.suggestions = @[]
  e.msg = cliErrorMessage(e.kind, e.program, e.commandPath, e.spelling,
    e.value, e.expected, e.detail, e.source, e.retired, e.replacement)

func cliValueSuggestions*(p: CliGrammarParam; text: string): seq[string] =
  ## What a value ``text`` outside ``p``'s closed value set may have meant:
  ## the values of the set (``cliSuggest``). Empty for an open set or a
  ## value in the set.
  if p.choices.len == 0 or text in p.choices:
    return
  var candidates: seq[CliSuggestionCandidate] = @[]
  for c in p.choices:
    candidates.add((c, c, c))
  cliSuggest(text, candidates)

type SwitchValue = enum
  svTrue, svFalse, svInvalid

func switchValue(g: CliGrammar; text: string): SwitchValue =
  ## How a switch reads an explicit value: as ``parseCliValue`` reads a
  ## ``bool``, or under ``lenientSwitchValues`` as Nim's ``parseBool``
  ## does, with an empty value true.
  if cprLenientSwitchValues in g.parseRules:
    if text.len == 0:
      return svTrue
    case normalize(text)
    of "y", "yes", "true", "1", "on": svTrue
    of "n", "no", "false", "0", "off": svFalse
    else: svInvalid
  else:
    case text.toLowerAscii()
    of "true", "yes", "on", "1": svTrue
    of "false", "no", "off", "0": svFalse
    else: svInvalid

proc cliAcceptsWord*(g: CliGrammar; id: int; text: string;
                     options: CliOptions): bool =
  ## Whether ``text``, the word after a bare ``acceptsNextWord`` flag, is
  ## taken as its value: it does not start with ``-`` and is a valid value
  ## (``options.valueCheck`` says so; without a value check, it is one of
  ## the closed value set's texts).
  if text.len > 0 and text[0] == '-':
    return false
  if not options.valueCheck.isNil:
    return options.valueCheck(id, text).len == 0
  text in g.params[id].choices

proc cliTokenize*(g: CliGrammar; argv: openArray[string];
                  options = CliOptions()): CliTokens {.
    raises: [CliUsageError, CliHelpRequest].} =
  ## Phase 1: reads ``argv`` (the arguments, without the program name).
  ## Raises ``CliUsageError`` for a word it cannot place and
  ## ``CliHelpRequest`` when help is asked for (``CliVersionRequest`` when
  ## the version is).
  let program = effectiveProgram(g, options)
  let exitCode = effectiveExitCode(options)
  var selected = @[0]
  var candidates = newSeq[seq[CliCandidate]](g.params.len)
  var node = 0
  var positionals: seq[tuple[word: string, index: int]] = @[]
    ## The bare words of the current command, in argv order.

  proc fail(kind: CliErrorKind; at: int; spelling: string; value = "";
            expected = "") {.raises: [CliUsageError].} =
    let e = newCliUsageError(kind, program, g.commands[node].path, at,
      spelling, value, expected, exitCode = exitCode)
    e.cliAddErrorContext(g, node, options)
    case kind
    of cekUnknownSubcommand:
      e.suggestions = cliSubcommandSuggestions(g, node, spelling, options)
    of cekUnknownFlag:
      e.suggestions = cliFlagSuggestions(g, node, spelling, options)
    else:
      discard
    e.cliNameRetired(g, node)
    raise e

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
    # ``alsoSets``: every occurrence (of a switch, one that sets it to true)
    # also supplies its text to each target, at the flag's own position.
    let p = g.params[id]
    if p.alsoSets.len == 0 or c.form == ccfNegated:
      return
    if p.isSwitch and c.form == ccfValue and switchValue(g, c.text) != svTrue:
      return
    for a in p.alsoSets:
      candidates[a.id].add(CliCandidate(source: csCli, form: ccfValue,
        text: a.text, argvIndex: c.argvIndex, valueArgvIndex: -1,
        spelling: c.spelling, setBy: p.name))

  proc switchCandidate(id, at: int; spelling, text: string): CliCandidate {.
      raises: [CliUsageError].} =
    ## A switch written with an explicit value (``--flag=value``).
    result = CliCandidate(source: csCli, form: ccfValue, text: text,
      argvIndex: at, valueArgvIndex: -1, spelling: spelling)
    let p = g.params[id]
    let lenient = cprLenientSwitchValues in g.parseRules
    if not lenient and not cliRefusesFalse(g, p):
      return
    case switchValue(g, text)
    of svTrue:
      if lenient:
        result.text = "true"
    of svFalse:
      if cliRefusesFalse(g, p):
        fail(cekSwitchFalseValue, at, spelling, text)
      if lenient:
        result.text = "false"
    of svInvalid:
      discard

  proc checkValuesBeforeHelp() {.raises: [CliUsageError].} =
    ## ``valueErrorsBeforeHelp``: the earliest value written so far that
    ## its parameter rejects, or bare word no positional accepts, reported
    ## as the conversion (or the placement of positionals) would report it.
    if cprValueErrorsBeforeHelp notin g.parseRules or
        options.valueCheck.isNil:
      return
    var found = false
    var bestAt, bestId = 0
    var bestCand: CliCandidate
    var bestText, bestExpected = ""
    for id in 0 ..< candidates.len:
      let p = g.params[id]
      if p.counted:
        continue
      for c in candidates[id]:
        if c.form != ccfValue or (found and c.argvIndex >= bestAt):
          continue
        let pieces = if p.separator.len > 0 and not c.verbatim:
                       c.text.split(p.separator)
                     else: @[c.text]
        for piece in pieces:
          let expected = options.valueCheck(id, piece)
          if expected.len > 0:
            found = true
            bestAt = c.argvIndex
            bestId = id
            bestCand = c
            bestText = piece
            bestExpected = expected
            break
    # The bare words read so far, when the command's positionals take them
    # in a fixed order (it has no list positional): a word no positional
    # accepts, or one its positional rejects. With a list positional, which
    # positional a word fills depends on the words not read yet.
    let slots = cliWordPositionals(g, node)
    var fixed = g.commands[node].children.len == 0
    for id in slots:
      if g.params[id].repeated or g.params[id].isList:
        fixed = false
    if fixed:
      for k, w in positionals:
        if found and w.index >= bestAt:
          break
        if k >= slots.len:
          fail(cekUnexpectedPositional, w.index, w.word)
        let p = g.params[slots[k]]
        let pieces = if p.separator.len > 0: w.word.split(p.separator)
                     else: @[w.word]
        for piece in pieces:
          let expected = options.valueCheck(slots[k], piece)
          if expected.len > 0:
            let e = newCliUsageError(cekInvalidValue, program,
              g.commands[p.declaredBy].path, w.index, cliDisplayName(p),
              piece, expected, exitCode = exitCode)
            e.cliAddErrorContext(g, p.declaredBy, options)
            e.suggestions = cliValueSuggestions(p, piece)
            raise e
    if found:
      let p = g.params[bestId]
      let spelling = if bestCand.spelling.len > 0: bestCand.spelling
                     else: cliDisplayName(p)
      let index = if bestCand.valueArgvIndex >= 0: bestCand.valueArgvIndex
                  else: bestCand.argvIndex
      let e = newCliUsageError(cekInvalidValue, program,
        g.commands[p.declaredBy].path, index, spelling, bestText,
        bestExpected, exitCode = exitCode)
      e.cliAddErrorContext(g, p.declaredBy, options)
      e.suggestions = cliValueSuggestions(p, bestText)
      raise e

  proc requestHelp(json: bool; long: bool; all = false) {.
      raises: [CliUsageError, CliHelpRequest].} =
    checkValuesBeforeHelp()
    let path = g.commands[node].path
    var layout = options.helpLayout
    if layout.style == chsStandard and layout.versionFlag.len == 0 and
        options.versionText.len > 0:
      layout.versionFlag = "Print version"
    let text = if json: cliHelpJson(g, node, program)
               else: cliHelpText(g, node, program, layout, long, all = all)
    var render: CliHelpRender = nil
    if not json:
      # The page again, for the stream it is printed to: a standard layout
      # whose width is 0 takes the printer's width; a classic one is styled
      # only when the program asks for colour.
      let grammar = g
      let command = node
      let color = options.color
      render = proc (width: int; styled: bool): string {.closure, gcsafe,
          raises: [].} =
        var l = layout
        if l.style == chsStandard and l.width == 0:
          l.width = width
        let paint = styled and (l.style == chsStandard or
          color == ccmAlways)
        cliHelpText(grammar, command, program, l, long, paint, all)
    raise (ref CliHelpRequest)(msg: "help requested", commandPath: path,
      json: json, long: long, all: all, text: text, render: render,
      color: options.color)

  proc requestVersion() {.raises: [CliUsageError, CliVersionRequest].} =
    checkValuesBeforeHelp()
    raise (ref CliVersionRequest)(msg: "version requested",
      commandPath: g.commands[node].path, text: options.versionText)

  proc restStarts(): int =
    ## The ``rest`` positional that takes the word at hand and every one
    ## after it: the current command runs (it has no subcommands) and every
    ## positional before the rest one has its word. -1 otherwise.
    if g.commands[node].children.len > 0:
      return -1
    let r = cliRestParam(g, node)
    if r.id >= 0 and positionals.len >= r.index: r.id else: -1

  proc afterSeparatorStarts(): int =
    ## The ``afterSeparator`` positional of the command that runs, once its
    ## ``--`` has been read; -1 otherwise. A command with subcommands is not
    ## the one that runs: the word after its ``--`` enters its ``call:``
    ## below, and is read again there.
    if g.commands[node].children.len > 0:
      return -1
    cliAfterSeparatorParam(g, node)

  descend()
  var terminated = false
  var i = 0

  while i < argv.len:
    if terminated:
      let sepId = afterSeparatorStarts()
      if sepId >= 0:
        # The words after ``--``, exactly as written: a later ``--``, a word
        # that looks like a flag and ``--help`` are among them. A flag's
        # value was consumed with its flag below, so a ``--`` that is a
        # value (``--flag --``, ``--flag=--``) never set ``terminated``.
        for k in i ..< argv.len:
          addCandidate(sepId, CliCandidate(source: csCli, form: ccfValue,
            text: argv[k], argvIndex: k, valueArgvIndex: -1, verbatim: true))
        break
    let restId = restStarts()
    if restId >= 0:
      # The rest of the command line, verbatim: nothing after this point is
      # read as a flag, a help request or ``--``.
      for k in i ..< argv.len:
        addCandidate(restId, CliCandidate(source: csCli, form: ccfValue,
          text: argv[k], argvIndex: k, valueArgvIndex: -1, verbatim: true))
      break
    var word = argv[i]
    if cliIsLoneDash(g, word):
      # ``loneDashesAreFlags``: a flag with an empty name, which no flag
      # has. (A flag's value never gets here: it is consumed with its
      # flag; nor does a word a ``rest`` positional takes.)
      fail(cekUnknownFlag, i, "")
    let isFlagWord = not terminated and word.len > 1 and word[0] == '-'
    if not terminated and word == "--":
      terminated = true
      inc i
      continue
    if not isFlagWord:
      let cmd = g.commands[node]
      if cmd.children.len > 0:
        # Before the subcommands: a subcommand declared ``shadowedByWord``
        # that answers to the word is not reached through it.
        if not terminated and cliIsHelpWord(g, word, options):
          # ``help --all``: the word right after it may ask for every tier.
          requestHelp(false, long = true, all = i + 1 < argv.len and
            cliIsHelpAllWord(g, argv[i + 1]))
        if not terminated and cliIsVersionWord(g, word, options):
          requestVersion()
        let next = if terminated: -1 else: cliChildNamed(g, node, word)
        if next >= 0:
          enter(next)
        elif cmd.callChild >= 0 and
            (terminated or cliPositionals(g, cmd.callChild).len > 0):
          # The word is one of the call:'s positionals. A call: that takes
          # no word from the command line (it holds only flags) cannot
          # accept it, so an unterminated word there is a mistyped
          # subcommand and is reported as one, naming the subcommands,
          # rather than as a stray argument of the call:. The word is read
          # again in the call:, where it may start a ``rest`` positional.
          enter(cmd.callChild)
          continue
        elif terminated:
          fail(cekUnexpectedPositional, i, word)
        else:
          fail(cekUnknownSubcommand, i, word,
            expected = subcommandWords(g, node))
      else:
        positionals.add((word, i))
      inc i
      continue

    # ``equalsTakesNext``: ``--name= value`` is ``--name=value`` when the
    # next word does not start with ``-``. (A word that is a flag's value
    # never gets here: it is consumed with its flag.)
    var joinedNext = false
    if cprEqualsTakesNext in g.parseRules and word.startsWith("--") and
        cliValueSeparator(g, word) == word.high and i + 1 < argv.len and
        (argv[i + 1].len == 0 or argv[i + 1][0] != '-'):
      word.add(argv[i + 1])
      joinedNext = true

    # A flag. Help first, then the command's own flags, then (for a command
    # with subcommands and a call:) the call:'s.
    let scope = g.commands[node].params
    let helpAsk = isHelpSpelling(g, scope, word, options)
    if helpAsk.help:
      requestHelp(helpAsk.json, helpAsk.long, helpAsk.all)
    if isVersionSpelling(g, scope, word, options):
      requestVersion()
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
          let id = cliFindShort(g, clusterScope, letter)
          if id < 0:
            if letter == 'h' and attempt == 0 and
                cprHelpInCluster in g.parseRules and
                cprLongHelpOnly notin g.parseRules and
                not options.disableHelpFlag and
                (callNode < 0 or cliFindShort(g, scopes[^1], 'h') < 0):
              # ``-help``, ``-vh``: the letters before it count, the rest
              # of the word is not read.
              for item in pending:
                addCandidate(item.id, item.c)
              requestHelp(false, long = false)
            ok = false
            break
          let p = g.params[id]
          let spelling = "-" & letter
          let equalsValue = k + 1 < word.len and
            ((word[k + 1] == '=' and cprShortEquals in g.parseRules) or
             (word[k + 1] == ':' and cprColonValues in g.parseRules))
          if equalsValue:
            # ``-o=value`` (``-o:value``): the value follows the ``=``.
            let text = word[k + 2 .. ^1]
            if p.counted:
              fail(cekInvalidValue, i, spelling, text, "no value")
            if p.isSwitch:
              pending.add((id, switchCandidate(id, i, spelling, text)))
            else:
              pending.add((id, CliCandidate(source: csCli, form: ccfValue,
                text: text, argvIndex: i, valueArgvIndex: -1,
                spelling: spelling)))
            break
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
            if p.acceptsNextWord and i + 1 < argv.len and
                cliAcceptsWord(g, id, argv[i + 1], options):
              pending.add((id, CliCandidate(source: csCli, form: ccfValue,
                text: argv[i + 1], argvIndex: i, valueArgvIndex: i + 1,
                spelling: spelling)))
              consumedNext = true
            else:
              pending.add((id, CliCandidate(source: csCli, form: ccfBare,
                argvIndex: i, valueArgvIndex: -1, spelling: spelling)))
          elif i + 1 < argv.len:
            pending.add((id, CliCandidate(source: csCli, form: ccfValue,
              text: argv[i + 1], argvIndex: i, valueArgvIndex: i + 1,
              spelling: spelling)))
            consumedNext = true
          else:
            fail(cekMissingValue, i, spelling, expected = p.placeholder)
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
      # The spelling is the flag name alone; a value written in the word
      # (``--name=value``, ``--name:value`` under ``colonValues``) or taken
      # from the next one (``equalsTakesNext``) goes in ``value``.
      let sep = cliValueSeparator(g, word)
      if sep > 0:
        fail(cekUnknownFlag, i, word[0 ..< sep], word[sep + 1 .. ^1])
      else:
        fail(cekUnknownFlag, i, word)
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
      if p.isSwitch:
        c = switchCandidate(m.id, i, m.spelling, m.attached.get)
      else:
        c.form = ccfValue
        c.text = m.attached.get
    elif takesNoValue(p):
      c.form = if p.counted: ccfCount else: ccfBare
    elif p.hasOptionalValue:
      if p.acceptsNextWord and i + 1 < argv.len and
          cliAcceptsWord(g, m.id, argv[i + 1], options):
        c.form = ccfValue
        c.text = argv[i + 1]
        c.valueArgvIndex = i + 1
        inc i
      else:
        c.form = ccfBare
    elif p.format == cafSeparate and i + 1 < argv.len:
      c.form = ccfValue
      c.text = argv[i + 1]
      c.valueArgvIndex = i + 1
      inc i
    else:
      fail(cekMissingValue, i, m.spelling, expected = p.placeholder)
    if joinedNext:
      # The value is the next word.
      if c.form == ccfValue:
        c.valueArgvIndex = i + 1
      inc i
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
  # positionals after it do not need. An ``afterSeparator`` positional took
  # its words above; a word before ``--`` that no other positional takes is
  # unexpected.
  let slots = cliWordPositionals(g, node)
  var next = 0
  for s, id in slots:
    let p = g.params[id]
    if p.rest:
      # Its words were taken as they came.
      continue
    if p.repeated or p.isList:
      var reserve = 0
      for later in slots[s + 1 .. ^1]:
        if g.params[later].required and not g.params[later].rest:
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

func cliVisibleParams*(g: CliGrammar; selected: openArray[int]): seq[int] =
  ## The parameters of the selected commands (each declared once).
  for command in selected:
    for id in g.commands[command].ownParams:
      result.add(id)

func cliEffective*(p: CliGrammarParam; grp: openArray[CliCandidate]):
    seq[bool] =
  ## Which of one source's candidates for ``p`` are part of that source's
  ## value: every one of a list or a counted flag, else the last.
  result = newSeq[bool](grp.len)
  if grp.len == 0:
    return
  if p.isList or p.counted:
    for k in 0 ..< grp.len:
      result[k] = true
  else:
    result[^1] = true

func cliNewResolution*(g: CliGrammar; tokens: CliTokens;
                       options = CliOptions()): CliResolution =
  ## An empty resolution for the commands ``tokens`` selected: what a merge
  ## phase fills in.
  result.selected = tokens.selected
  result.program = effectiveProgram(g, options)
  result.exitCode = effectiveExitCode(options)
  result.color = options.color
  result.disableHelpFlag = options.disableHelpFlag
  result.merged = newSeq[seq[CliCandidate]](g.params.len)
  result.overridden = newSeq[seq[CliCandidate]](g.params.len)
  result.decisions = newSeq[CliDecision](g.params.len)

proc cliMerge*(g: CliGrammar; tokens: CliTokens; options = CliOptions()):
    CliResolution {.raises: [].} =
  ## Phase 2 with the command line as the only source: for each parameter of
  ## the selected commands, the candidates its value is made of. A list or a
  ## counted flag keeps every occurrence, anything else its last; the
  ## earlier occurrences of a scalar are ``overridden``. A parameter's
  ## ``merge`` rule says how several sources combine, so with one source it
  ## has nothing to do.
  result = cliNewResolution(g, tokens, options)
  for id in cliVisibleParams(g, tokens.selected):
    let cands = tokens.candidates[id]
    let eff = cliEffective(g.params[id], cands)
    for j, c in cands:
      if eff[j]:
        result.merged[id].add(c)
      else:
        result.overridden[id].add(c)

proc cliDecide*(g: CliGrammar; r: var CliResolution) {.
    raises: [CliUsageError].} =
  ## Phase 3, after every source is merged: what each parameter of the
  ## selected commands gets — its merged candidates, else a value implied
  ## by a parameter that some source supplied (the first such in
  ## declaration order; implications do not chain), else its default. A
  ## default therefore never stands in for a value a source supplied. A
  ## required parameter that gets nothing is a usage error naming the
  ## command that declares it.
  let visible = cliVisibleParams(g, r.selected)
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
      let e = newCliUsageError(cekMissingRequired, r.program,
        g.commands[p.declaredBy].path, -1, cliDisplayName(p),
        exitCode = r.exitCode)
      e.cliAddErrorContext(g, p.declaredBy, CliOptions(color: r.color,
        disableHelpFlag: r.disableHelpFlag))
      raise e

proc cliResolve*(g: CliGrammar; argv: openArray[string];
                 options = CliOptions()): CliResolution {.
    raises: [CliUsageError, CliHelpRequest].} =
  ## Phases 1 to 3, with the command line as the only source.
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
  let index = if c.source != csCli: -1
              elif c.valueArgvIndex >= 0: c.valueArgvIndex
              else: c.argvIndex
  let e = newCliUsageError(cekInvalidValue, r.program,
    g.commands[p.declaredBy].path, index, spelling, text, expected,
    exitCode = r.exitCode, source = c.described)
  e.cliAddErrorContext(g, p.declaredBy, CliOptions(color: r.color,
    disableHelpFlag: r.disableHelpFlag))
  e.suggestions = cliValueSuggestions(p, text)
  raise e

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

proc cliCheckValue*[T, E](text: string; allowed: openArray[E]): string {.
    raises: [].} =
  ## Whether ``text`` is a valid value of a parameter of type ``T`` whose
  ## closed value set is ``allowed`` (empty when open), as the conversion
  ## (``cliConvertCandidates``) would decide it for one candidate (one
  ## element of a list): empty when it is, else what would have been
  ## accepted. The generated ``CliValueCheck`` calls it.
  mixin parseCliValue
  when T is seq:
    var item: E
    try:
      parseCliValue(text, item)
    except CliValueError as e:
      return e.expected
    except ValueError:
      return cliTypeDescription(E)
    if allowed.len > 0 and item notin allowed:
      var texts: seq[string] = @[]
      for a in allowed:
        texts.add(cliValueText(a))
      return "one of: " & texts.join(", ")
  else:
    var value: T
    try:
      parseCliValue(text, value)
    except CliValueError as e:
      return e.expected
    except ValueError:
      return cliTypeDescription(T)
    var v: E
    when T is Option:
      if value.isNone:
        return ""
      v = value.get
    else:
      v = value
    if allowed.len > 0 and v notin allowed:
      var texts: seq[string] = @[]
      for a in allowed:
        texts.add(cliValueText(a))
      return "one of: " & texts.join(", ")
  ""

template cliElementType*(T: typedesc): typedesc =
  ## The type of one value of a parameter of type ``T``: the element of a
  ## ``seq``, the content of an ``Option``, else ``T`` itself. A
  ## ``values`` set is a set of these.
  when T is seq: typeof(default(T)[0])
  elif T is Option: typeof(default(T).get())
  else: T

proc cliConvertCandidates*[T, E](g: CliGrammar; r: CliResolution; id: int;
                                 cands: openArray[CliCandidate];
                                 value: var T;
                                 bare: proc (): T {.raises: [].};
                                 allowed: openArray[E]) {.
    raises: [CliUsageError].} =
  ## Converts the candidates ``cands`` of parameter ``id`` into ``value``.
  ## ``bare`` gives the value of a bare optional-value flag (its
  ## ``optionalValue``); it is not called otherwise. When ``allowed`` is not
  ## empty (the parameter's ``values``), every converted value must be one
  ## of its entries. A list collects every candidate (each split on the
  ## ``separator`` unless it is ``verbatim``); a counted flag adds up its
  ## occurrences and the counts other sources give; anything else takes the
  ## last candidate.
  mixin parseCliValue
  let p = g.params[id]
  if cands.len == 0:
    return

  template restrict(c: CliCandidate; text: string; v: E) =
    restrictTo(g, r, id, c, text, v, allowed)

  when T is seq:
    value.setLen(0)
    for c in cands:
      case c.form
      of ccfValue:
        let pieces = if p.separator.len > 0 and not c.verbatim:
                       c.text.split(p.separator)
                     else: @[c.text]
        for piece in pieces:
          var item: E
          convertText(g, r, id, c, piece, item)
          restrict(c, piece, item)
          value.add(item)
      of ccfBare:
        for item in bare():
          value.add(item)
      of ccfNegated, ccfCount, ccfEmpty:
        discard
  else:
    if p.counted:
      when T is SomeInteger:
        var total: T = 0
        for c in cands:
          case c.form
          of ccfCount:
            total += 1
          of ccfValue:
            var n: T
            convertText(g, r, id, c, c.text, n)
            total += n
          else:
            discard
        value = total
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
    of ccfCount, ccfEmpty:
      discard

proc cliConvert*[T, E](g: CliGrammar; r: CliResolution; id: int;
                       value: var T; bare: proc (): T {.raises: [].};
                       allowed: openArray[E]) {.raises: [CliUsageError].} =
  ## Converts the merged candidates of parameter ``id`` into ``value``
  ## (``cliConvertCandidates``).
  cliConvertCandidates(g, r, id, r.merged[id], value, bare, allowed)
