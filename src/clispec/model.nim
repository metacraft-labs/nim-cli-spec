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

  PlainCliParam* = CliParam[NoCliExtension]
  PlainCliCommand* = CliCommand[NoCliExtension, NoCliExtension]
  PlainCliModel* = CliModel[NoCliExtension, NoCliExtension]
