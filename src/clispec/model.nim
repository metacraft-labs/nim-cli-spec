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
## ``--output``). Its configuration-file key, ``configKey``, is derived from
## the path of the command that DECLARES it followed by its name, joined with
## ``.`` and spelt exactly as declared (``subcmd "build": flag jobs`` gives
## ``build.jobs``; a parameter declared directly under ``cli:`` or in the root
## ``call:`` gives just its name). ``key = "<dotted.key>"`` replaces the
## derived key. A parameter whose ``sources`` exclude files has no key.
## Environment variables are never derived: a parameter reads exactly the
## variables its ``env`` lists, and none when it lists none.

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
      ## The configuration-file key: ``key = "<dotted.key>"`` when given,
      ## else derived (see "Names and configuration keys" above). Empty when
      ## ``sources`` exclude files.
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

  PlainCliParam* = CliParam[NoCliExtension]
  PlainCliCommand* = CliCommand[NoCliExtension, NoCliExtension]
  PlainCliModel* = CliModel[NoCliExtension, NoCliExtension]

func isSet*(e: CliExpr): bool =
  ## Whether the expression was given.
  e.code.len > 0
