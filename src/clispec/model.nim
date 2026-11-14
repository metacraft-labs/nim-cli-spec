## The typed CLI model.
##
## A command line is described as a tree of commands, each with an ordered
## list of parameters. ``clispec/dsl`` builds this model at compile time from
## a ``cli:`` block; everything else a program derives from its command line
## is meant to be generated from the model, so it is the single source of
## truth.
##
## Extensions
## ==========
##
## Both object types carry an ``ext`` field whose type is a generic
## parameter: ``CliParam[P]`` holds a ``P`` and ``CliCommand[C, P]`` holds a
## ``C`` (and parameters of type ``CliParam[P]``). A consumer that needs to
## attach its own declarations to commands or parameters defines two plain
## object types, instantiates the model with them and teaches the DSL parser
## to fill them (see the hooks documented in ``clispec/dsl``). The library
## never looks inside ``ext``; it only copies it, so it stays a typed value
## all the way through — no casts, no string-keyed side tables.
##
## A consumer with nothing to attach uses ``NoCliExtension`` for both, which
## the ``PlainCliParam`` and ``PlainCliCommand`` aliases spell out.
##
## Expressions
## ===========
##
## Some named arguments take a Nim expression rather than a literal:
## ``default``, ``optionalValue``, the entries of ``values``, the values of
## ``implies``, the ``complete`` completer and a ``merge`` combine proc. The
## model is a plain value (it is built inside a macro and turned into a
## constant with ``newLit``), and a ``NimNode`` cannot live in a constant, so
## each expression is kept as a ``CliExpr``: its source text exactly as the
## compiler's ``repr`` prints the untyped AST, plus where it was written. A
## macro that generates code from the model turns it back into an AST with
## ``parseExpr(e.code)`` and, for diagnostics, ``setLineInfo``. The parsed AST
## is untyped, so its identifiers bind where the generated code is placed;
## generators place it in the scope that holds the description, which is
## where the author wrote the expression.
##
## Names and configuration keys
## ============================
##
## A parameter's ``name`` is its canonical long flag (``output`` is
## ``--output``), spelt in the command line's convention (``longName``). Its
## configuration-file key, ``configKey``, is derived from the path of the
## command that DECLARES it followed by its name, joined with ``.``, each
## segment spelt in the file source's convention (``subcmd "build": flag
## jobs`` gives ``build.jobs``; a parameter declared directly under ``cli:``
## or in the root ``call:`` gives just its name). ``key = "<dotted.key>"``
## replaces the derived key. A parameter whose ``sources`` exclude files has
## no key. A description that names file sources of its own gets a key per
## named source too (``sourceKeys``).
## Environment variables are never derived: a parameter reads exactly the
## variables its ``env`` lists, and none when it lists none.
##
## Naming conventions
## ==================
##
## A name can be spelt in a *convention* (``CliConvention``): ``declared``
## (exactly as written), ``camelCase``, ``snakeCase`` or ``kebabCase``.
## ``cliConvert`` is the one function that respells a name, so a name is
## spelt the same way wherever it appears. It splits the name into words
## (``cliWords``) by these rules:
##
## 1. Letters (``A``-``Z``, ``a``-``z``), digits and every byte above 127
##    (the parts of a non-ASCII character) are word characters; every other
##    character (``-``, ``_``, ``.``, a space) ends the current word and is
##    dropped.
## 2. A new word starts at an upper-case letter that follows a lower-case
##    letter, a digit or a non-ASCII byte (``writeReport`` is ``write`` +
##    ``Report``; ``sha256Sum`` is ``sha256`` + ``Sum``), and at an upper-case
##    letter that follows an upper-case letter and is followed by a
##    lower-case one: an acronym's last capital starts the next word
##    (``HTTPPort`` is ``HTTP`` + ``Port``).
## 3. Nothing else starts a word: digits stay with the word before them
##    (``ipv6Address`` is ``ipv6`` + ``Address``, ``HTTP2Server`` is
##    ``HTTP2`` + ``Server``), and a run of capitals with no lower-case letter
##    after it is one word (``userID`` is ``user`` + ``ID``).
##
## ``snakeCase`` and ``kebabCase`` lower-case every word and join them with
## ``_`` and ``-``. ``camelCase`` lower-cases the first word and spells every
## other one with an upper-case first letter and the rest lower-case
## (``HTTPPort`` is ``httpPort``, ``user_id`` is ``userId``). Only ASCII
## letters change case. A name with no word character is kept as written.
## Converting loses what the words do not record (``HTTPPort`` and
## ``httpPort`` both become ``http_port``), which is why ``declared`` exists
## and why a name can override its spelling (below).
##
## Conventions per source
## ======================
##
## Each source of a parameter's value spells its names in one convention,
## set once in the description (``convention <source> = <convention>``
## directly under ``cli:``):
##
## * ``cli``: the command line's long flags (``flag writeReport`` is
##   ``--write-report`` under ``kebabCase``). Subcommand words, ``alias``
##   and ``short`` spellings are used as written.
## * ``file``: every configuration file, unless a named source below says
##   otherwise. ``keyStyle <convention>`` is the older spelling of
##   ``convention file = <convention>``.
## * ``"<name>"``: one named file source: the configuration layer with that
##   name or, failing that, the configuration format with that name
##   (``clispec/sources``).
##
## Every source defaults to ``declared``, which is also what confutils does
## (its configuration keys are the field names, unconverted). Environment
## variables are never derived, so no convention applies to them.
##
## Overrides refine the conversion for one name, as opt-ins on the parameter:
##
## * ``perConvention = [kebabCase = "url-base", ...]``: the spelling of the
##   parameter's name in one convention, used by every source with that
##   convention (an acronym, or a word the splitter divides wrongly). In a
##   file source it replaces the last segment of the derived key.
## * ``perSource = [cli = "port", "project" = "web.port", ...]``: the long
##   flag (without ``--``) in ``cli``, or the whole key, used as written, in
##   a named file source. ``key = "<dotted.key>"`` is the per-source override
##   for every file source.
##
## The most specific one wins: the override for the source (a named file
## source's own, then ``key``), then the override for the source's
## convention, then the conversion (``cliSpelling``, ``cliSourceKey``).

type
  CliParamKind* = enum
    ## How a parameter appears on the command line.
    cpkPositional ## a bare word, ordered by ``position``
    cpkFlag       ## a named flag (``--name`` or its ``alias``)

  CliArgFormat* = enum
    ## How a flag and its value are joined.
    cafSeparate ## ``-o value``: the flag and the value are two words
    cafConcat   ## ``-ovalue``: the value is appended to the flag
    cafEquals   ## ``--flag=value``

  CliArgPlacement* = enum
    ## Where a flag goes relative to the subcommand word.
    capAfterSubcommand  ## ``tool sub --flag`` (the default)
    capBeforeSubcommand ## ``tool --flag sub``; flags declared directly
                        ## under ``cli:`` get this placement

  CliSource* = enum
    ## A kind of source that can supply a parameter's value, from the
    ## lowest precedence to the highest.
    csFile = "file" ## a configuration file (in the layers a consumer declares)
    csEnv = "env"   ## an environment variable named by ``env``
    csCli = "cli"   ## the command line

  CliMergeRule* = enum
    ## How the values that several sources supply combine.
    cmrReplace = "replace"
      ## The highest source wins (the default). A list given several times
      ## within one source collects every occurrence.
    cmrAppend = "append"
      ## Values from every source are concatenated, lowest source first.
    cmrCombine = "combine"
      ## A consumer-supplied proc (``CliParam.combine``) receives every
      ## candidate value.
    cmrErrorOnConflict = "errorOnConflict"
      ## Two sources supplying different values is an error naming both.

  CliConfigType* = enum
    ## The type a configuration-file value must have, as a format sees it
    ## (a list parameter's elements each have this type).
    cctString = "string"
      ## Strings, and every type whose value is written as text: enums,
      ## ``char``, paths, and types with a ``parseCliValue`` of their own.
    cctInteger = "integer"
    cctFloat = "float"
      ## A float; an integer is accepted too.
    cctBool = "bool"

  CliConvention* = enum
    ## A naming convention (see "Naming conventions" above).
    cnDeclared = "declared"
      ## Exactly as declared (the default for every source).
    cnCamelCase = "camelCase"
      ## ``write_report`` → ``writeReport``, ``HTTPPort`` → ``httpPort``.
    cnSnakeCase = "snakeCase"
      ## ``writeReport`` → ``write_report``, ``debug-dump`` → ``debug_dump``.
    cnKebabCase = "kebabCase"
      ## ``writeReport`` → ``write-report``, ``debug_dump`` → ``debug-dump``.

  CliKeyStyle* = CliConvention
    ## The older name of ``CliConvention`` (``keyStyle`` under ``cli:``).

  CliSourceConvention* = object
    ## ``convention "<name>" = <convention>``: the convention of one named
    ## configuration-file source.
    source*: string
      ## The layer's or format's name.
    convention*: CliConvention

  CliConventionSpelling* = object
    ## One ``perConvention`` entry: the spelling of a parameter's name in
    ## one convention.
    convention*: CliConvention
    spelling*: string

  CliSourceSpelling* = object
    ## One ``perSource`` entry, or one resolved key: a spelling in one
    ## source (``cli``, or a named file source).
    source*: string
    spelling*: string

  CliVisibility* = enum
    ## Where a command or parameter is listed.
    cvShown = "shown"
      ## In help and completion (the default).
    cvInternal = "internal"
      ## Left out of the primary help and completion, but listed by the help
      ## of the command that holds it.
    cvHidden = "hidden"
      ## Accepted, and listed nowhere.

  CliExpr* = object
    ## A Nim expression written in a description (see "Expressions" above).
    code*: string
      ## The expression's source text, as ``repr`` prints the untyped AST.
      ## Empty when the argument was not given.
    sourceFile*: string
    sourceLine*: int
    sourceColumn*: int

  CliImplication* = object
    ## One ``<param> = <value>`` entry of ``implies``.
    param*: string
      ## The implied parameter's name.
    value*: CliExpr
      ## The value it takes unless a source supplies one explicitly.

  CliGroup* = object
    ## A ``group "<title>":`` section: parameters listed together in help.
    name*: string
    help*: string
    sourceFile*: string
    sourceLine*: int

  NoCliExtension* = object
    ## The empty extension: a model that carries nothing beyond what the
    ## library itself knows.

  CliParam*[P] = object
    ## One ``pos`` / ``flag`` / ``boolFlag`` declaration.
    name*: string
      ## The parameter's name as declared (``flag output is string`` →
      ## ``output``).
    nimType*: string
      ## The declared Nim type, as written in the source (``string``,
      ## ``seq[string]``, ``bool``, ``int``, …).
    kind*: CliParamKind
    format*: CliArgFormat
    placement*: CliArgPlacement
    repeated*: bool
      ## A list value is rendered as one flag occurrence per element.
    position*: int
      ## The ordering key among positionals.
    alias*: string
      ## The exact spelling of the flag (``-o``, ``--output=``). Empty means
      ## the canonical ``--<name>``.
    required*: bool
      ## Positionals are required unless declared otherwise; flags are
      ## optional unless ``required = true``.
    help*: string
      ## ``help = "<text>"``: the description help output and completion
      ## show.
    default*: CliExpr
      ## ``default = <expr>``: the value when no source supplies one. Never
      ## given together with ``required = true``. A positional with a
      ## default is optional.
    short*: char
      ## ``short = 'x'``: a one-letter spelling, ``-x``. ``'\0'`` when none.
    env*: seq[string]
      ## ``env = ["NAME", ...]``: the environment variables that supply the
      ## value, first match wins. Only ever declared, never derived.
    values*: seq[CliExpr]
      ## ``values = [a, b, c]``: the closed set of accepted values (of the
      ## element type, for a list). Empty when the set is open, or when it
      ## is the parameter's enum type, which a generator reads from the type.
    complete*: CliExpr
      ## ``complete = <completer>``: dynamic value completion.
    configKey*: string
      ## The configuration-file key in the ``file`` source:
      ## ``key = "<dotted.key>"`` when given, else derived (see "Names and
      ## configuration keys" and "Naming conventions" above). Empty when
      ## ``sources`` exclude files.
    sourceKeys*: seq[CliSourceSpelling]
      ## The configuration-file key in each named file source the
      ## description declares (``convention "<name>" = ...``), in the order
      ## they are declared. Empty when ``sources`` exclude files.
    longName*: string
      ## The long flag without ``--`` in the ``cli`` convention: ``name``
      ## respelt, or its override. Empty for a positional. A model built by
      ## hand may leave it empty, and the flag is then ``--<name>``.
    perConvention*: seq[CliConventionSpelling]
      ## ``perConvention = [<convention> = "<spelling>", ...]``.
    perSource*: seq[CliSourceSpelling]
      ## ``perSource = [cli = "<flag>", "<source>" = "<key>", ...]``.
    keyDeclared*: bool
      ## ``configKey`` was given with ``key``, not derived.
    sources*: set[CliSource]
      ## ``sources = {cli, env, file}``: which sources may supply the value.
      ## The parser sets all three when the argument is not given (a model
      ## built by hand must set it too: Nim's zero value is the empty set).
    merge*: CliMergeRule
      ## ``merge = replace | append | errorOnConflict | <combine proc>``.
    combine*: CliExpr
      ## The combine proc when ``merge`` is ``cmrCombine``.
    separator*: string
      ## ``separator = ","``: a list may be given as one delimited value.
    optionalValue*: CliExpr
      ## ``optionalValue = <expr>``: the flag may appear bare, taking this
      ## value, or with ``=value``; it never takes the next word.
    negatable*: bool
      ## ``negatable = true``: ``--no-<name>`` sets the bool to false.
    counted*: bool
      ## ``counted = true``: the value is the number of occurrences.
    implies*: seq[CliImplication]
      ## ``implies = [<param> = <value>, ...]``: setting this parameter sets
      ## the others unless they are given explicitly.
    visibility*: CliVisibility
      ## ``visibility = shown | internal | hidden``.
    group*: string
      ## The ``group`` section the parameter was declared in, or empty.
    declaredIn*: seq[string]
      ## The path of the command that declared the parameter. A parameter
      ## inherited by nested commands keeps the path of the scope that
      ## declared it, which is what its configuration key is derived from.
    sourceFile*: string
    sourceLine*: int
      ## Where the declaration was written, from the compiler's line
      ## information.
    ext*: P
      ## The consumer's own declarations about this parameter.

  CliCommand*[C, P] = object
    ## One ``call:`` or ``subcmd "<name>":`` scope, or the root scope of a
    ## ``cli:`` block.
    name*: string
      ## The last segment of ``path``, or empty for an anonymous ``call:``
      ## at the root (and for the root scope itself).
    path*: seq[string]
      ## The full lexical path from the root of the ``cli:`` block. A
      ## ``subcmd "build": subcmd "target"`` has path ``["build", "target"]``;
      ## ``call:`` adds no segment.
    params*: seq[CliParam[P]]
      ## Every parameter visible in this scope, in declaration order: those
      ## of the enclosing scopes declared before this scope opened, then its
      ## own.
    help*: string
      ## ``subcmd "<name>", help = "<text>":``, ``call(help = "<text>"):``,
      ## or a ``help "<text>"`` statement in the scope's body.
    aliases*: seq[string]
      ## ``subcmd "<name>", aliases = ["<other>", ...]:``: further accepted
      ## spellings of the subcommand word.
    visibility*: CliVisibility
      ## ``subcmd "<name>", visibility = internal:``.
    anonymous*: bool
      ## The scope is a ``call:``: the command run when no subcommand word
      ## follows its enclosing scope. It shares that scope's ``path``, so this
      ## is what tells the two apart.
    depth*: int
      ## How many scopes enclose this one: 0 for the root, 1 for a scope
      ## directly under ``cli:``. A ``call:`` counts, although it adds no
      ## ``path`` segment, so ``depth`` and ``path`` together place a scope
      ## in the tree.
    sourceFile*: string
    sourceLine*: int
    ext*: C
      ## The consumer's own declarations about this command. A nested scope
      ## starts with a copy of its parent's ``ext``, so a consumer's
      ## command-level declarations are inherited exactly as parameters are.

  CliModel*[C, P] = object
    ## A whole ``cli:`` block.
    root*: CliCommand[C, P]
      ## The scope directly under ``cli:``. Its ``params`` are the
      ## parameters declared there, which every nested scope inherits.
    commands*: seq[CliCommand[C, P]]
      ## Every ``call:`` and ``subcmd`` scope, each one listed after the
      ## scopes nested inside it.
    groups*: seq[CliGroup]
      ## Every ``group`` section, in the order first declared.
    keyStyle*: CliConvention
      ## The convention of the ``file`` source: ``convention file = <c>``
      ## (or ``keyStyle <c>``) under ``cli:``.
    flagConvention*: CliConvention
      ## The convention of the ``cli`` source's long flags:
      ## ``convention cli = <c>`` under ``cli:``.
    fileSources*: seq[CliSourceConvention]
      ## Every named file source, ``convention "<name>" = <c>``, in
      ## declaration order.
    configSchema*: string
      ## ``configSchema "<id>"`` under ``cli:``: the identifier a
      ## configuration file must carry in its top-level ``schema`` string
      ## (``"tool.config.v1"``). Empty when the description declares none,
      ## and then the program loads no configuration file.

  PlainCliParam* = CliParam[NoCliExtension]
  PlainCliCommand* = CliCommand[NoCliExtension, NoCliExtension]
  PlainCliModel* = CliModel[NoCliExtension, NoCliExtension]

func isSet*(e: CliExpr): bool =
  ## Whether the expression was given.
  e.code.len > 0

const
  CliSourceCli* = "cli"
    ## The source name of the command line in conventions and overrides.
  CliSourceFile* = "file"
    ## The source name of every configuration file not named on its own.

const
  cksDeclared* = cnDeclared ## The older name of ``cnDeclared``.
  cksSnakeCase* = cnSnakeCase ## The older name of ``cnSnakeCase``.
  cksKebabCase* = cnKebabCase ## The older name of ``cnKebabCase``.

func isWordChar(ch: char): bool =
  ch in {'a'..'z', 'A'..'Z', '0'..'9'} or ord(ch) >= 128

func cliWords*(name: string): seq[string] =
  ## The words of a name, by the rules in "Naming conventions" above:
  ## ``writeReport`` → ``write``, ``Report``; ``HTTPPort`` → ``HTTP``,
  ## ``Port``; ``ipv6-address`` → ``ipv6``, ``address``.
  var word = ""
  for i, ch in name:
    if not isWordChar(ch):
      if word.len > 0:
        result.add(word)
        word = ""
      continue
    if ch in {'A'..'Z'} and word.len > 0:
      let prev = name[i - 1]
      let prevLower = prev in {'a'..'z', '0'..'9'} or ord(prev) >= 128
      let nextLower = i + 1 < name.len and name[i + 1] in {'a'..'z'}
      if prevLower or (prev in {'A'..'Z'} and nextLower):
        result.add(word)
        word = ""
    word.add(ch)
  if word.len > 0:
    result.add(word)

func lowerAscii(ch: char): char =
  if ch in {'A'..'Z'}: char(ord(ch) + 32) else: ch

func upperAscii(ch: char): char =
  if ch in {'a'..'z'}: char(ord(ch) - 32) else: ch

func cliConvert*(name: string; convention: CliConvention): string =
  ## ``name`` spelt in ``convention`` (see "Naming conventions" above).
  ## ``cnDeclared`` returns ``name`` unchanged, and so does any convention
  ## for a name with no word character.
  case convention
  of cnDeclared:
    return name
  of cnSnakeCase, cnKebabCase:
    let sep = if convention == cnSnakeCase: '_' else: '-'
    for word in cliWords(name):
      if result.len > 0:
        result.add(sep)
      for ch in word:
        result.add(lowerAscii(ch))
  of cnCamelCase:
    for i, word in cliWords(name):
      for j, ch in word:
        result.add(if i > 0 and j == 0: upperAscii(ch) else: lowerAscii(ch))
  if result.len == 0:
    result = name

func cliKeySegment*(segment: string; style: CliConvention): string =
  ## One derived key segment spelt in ``style`` (``cliConvert``).
  cliConvert(segment, style)

func cliOverride*(source: string; convention: CliConvention;
                  perSource: openArray[CliSourceSpelling];
                  perConvention: openArray[CliConventionSpelling]):
    tuple[found, bySource: bool; spelling: string] =
  ## The most specific override of a name in ``source``, whose convention
  ## is ``convention``: the ``perSource`` entry for ``source``, else the
  ## ``perConvention`` entry for ``convention``; ``found`` is false when
  ## neither is given. ``bySource`` tells which one it was.
  for o in perSource:
    if o.source == source:
      return (true, true, o.spelling)
  for o in perConvention:
    if o.convention == convention:
      return (true, false, o.spelling)
  (false, false, "")

func cliSpelling*(name, source: string; convention: CliConvention;
                  perSource: openArray[CliSourceSpelling] = [];
                  perConvention: openArray[CliConventionSpelling] = []):
    string =
  ## The spelling of the name ``name`` in ``source``: its override for the
  ## source, else its override for ``convention``, else ``name`` converted.
  let o = cliOverride(source, convention, perSource, perConvention)
  if o.found: o.spelling else: cliConvert(name, convention)

func cliDerivedKey*(path: openArray[string]; name: string;
                    style: CliConvention): string =
  ## The derived configuration key of a parameter ``name`` declared by the
  ## command at ``path``: the segments joined with ``.``, each spelt in
  ## ``style``.
  for segment in path:
    result.add(cliKeySegment(segment, style))
    result.add('.')
  result.add(cliKeySegment(name, style))

func cliSourceKey*(path: openArray[string]; name, source: string;
                   convention: CliConvention; declaredKey: string;
                   perSource: openArray[CliSourceSpelling] = [];
                   perConvention: openArray[CliConventionSpelling] = []):
    string =
  ## The configuration key of a parameter ``name`` declared by the command
  ## at ``path``, in the file source ``source`` (``"file"`` or a named one)
  ## whose convention is ``convention``. ``declaredKey`` is its ``key``, or
  ## empty. Most specific first: the source's own ``perSource`` entry (the
  ## whole key), ``declaredKey`` (every file source's), the
  ## ``perConvention`` entry for ``convention`` (the last segment), the
  ## conversion.
  var named: seq[CliSourceSpelling] = @[]
  for o in perSource:
    if o.source == source:
      named.add(o)
  if named.len == 0 and declaredKey.len > 0:
    named.add(CliSourceSpelling(source: source, spelling: declaredKey))
  let o = cliOverride(source, convention, named, perConvention)
  if o.found and o.bySource:
    return o.spelling
  for segment in path:
    result.add(cliConvert(segment, convention))
    result.add('.')
  result.add(if o.found: o.spelling else: cliConvert(name, convention))

func cliFileSourceConvention*[C, P](model: CliModel[C, P];
                                    source: string): CliConvention =
  ## The convention of the file source ``source``: a named one's, else the
  ## ``file`` source's.
  for s in model.fileSources:
    if s.source == source:
      return s.convention
  model.keyStyle
