## Candidates and origins: what each source supplied for a parameter, and
## the record of how its value was decided.
##
## Every source a parameter can be supplied by (a configuration-file layer,
## the environment, the command line) contributes *candidates*: one per
## occurrence of the parameter in that source (``--tag a --tag b`` gives two;
## a list in a configuration file gives one per element). The merge
## (``clispec/parser``) picks the winners, and records for every parameter a
## ``CliOrigin``: the winning source, and every other candidate that was
## considered, with the value it carried and what happened to it.
##
## A program reads the origins through the origin object ``cliProgram``
## generates beside the configuration object (``Tool.loadWithOrigins``):
## one ``CliOrigin`` per field, in the same shape. That is what lets it
## explain an enforced setting, report its whole configuration and where
## each value came from, or pre-fill an editor with what a user would get.
##
## This module has no dependencies beyond the model, so a consumer that only
## parses its command line pays nothing for it.

import std/strutils

import ./model

type
  CliCandidateForm* = enum
    ## How a candidate was written.
    ccfValue    ## with a value: ``--jobs 4``, ``--jobs=4``, ``-j4``, a word,
                ## an environment variable, a configuration-file value
    ccfBare     ## a switch or an optional-value flag written bare
    ccfNegated  ## ``--no-<name>``
    ccfCount    ## one occurrence of a counted flag
    ccfEmpty    ## an empty list (``tags = []`` in a configuration file):
                ## the source supplies the list, and it has no elements

  CliCandidate* = object
    ## One value a source supplies for a parameter.
    source*: CliSource
    form*: CliCandidateForm
    text*: string
      ## The value as written (``ccfValue`` only).
    argvIndex*: int
      ## The index in argv of the flag (or of the positional word); -1 for a
      ## candidate that does not come from the command line.
    valueArgvIndex*: int
      ## The index of the word holding the value when it is not the flag's
      ## own word (``--jobs 4``), else -1.
    spelling*: string
      ## The spelling used: ``--jobs``, ``-j``, ``--no-verbose``. Empty for
      ## a positional and for a candidate from another source.
    layer*: int
      ## The index of its layer among the layers the program declared
      ## (lowest first) (``csFile``).
    layerName*: string
      ## The layer's name (``csFile``).
    binding*: bool
      ## The layer is binding: its values are enforced (``csFile``).
    path*: string
      ## The configuration file (``csFile``).
    line*: int
      ## The line of the file the value was written on (``csFile``).
    key*: string
      ## The configuration key as written in the file (``csFile``).
    variable*: string
      ## The environment variable (``csEnv``).
    verbatim*: bool
      ## The text is one element as it stands and is never split on the
      ## parameter's ``separator`` (an element of a configuration-file list).

  CliOriginKind* = enum
    ## Where a value came from.
    cokUnset = "unset"
      ## Nothing supplied it: the field holds its type's zero value.
    cokDefault = "default"
      ## The parameter's ``default``.
    cokFile = "file"
      ## A configuration file (path, line and the layer's name).
    cokEnv = "env"
      ## An environment variable.
    cokCli = "cli"
      ## The command line (argv index and the spelling used).
    cokImplied = "implied"
      ## Another parameter's ``implies``.
    cokEnforced = "enforced"
      ## A binding configuration layer, which no other source can override.

  CliSite* = object
    ## Where one value came from. Which fields are meaningful depends on
    ## ``kind``.
    kind*: CliOriginKind
    layer*: string
      ## The layer's name (``cokFile``, ``cokEnforced``).
    path*: string
      ## The configuration file (``cokFile``, ``cokEnforced``).
    line*: int
      ## Its line (``cokFile``, ``cokEnforced``).
    key*: string
      ## The configuration key (``cokFile``, ``cokEnforced``).
    variable*: string
      ## The environment variable (``cokEnv``).
    argvIndex*: int
      ## The index in argv (``cokCli``); -1 otherwise.
    spelling*: string
      ## The spelling used on the command line (``cokCli``); empty for a
      ## positional.
    impliedBy*: string
      ## The name of the parameter whose ``implies`` set the value
      ## (``cokImplied``).

  CliFate* = enum
    ## What became of a candidate that is not the winner.
    cfOverridden = "overridden"
      ## A later (higher) source, or a later occurrence in the same source,
      ## replaced it.
    cfCombined = "combined"
      ## It is part of the value: ``merge = append`` or a combine proc took
      ## it together with the winner.
    cfIgnoredByEnforcement = "ignored by enforcement"
      ## A binding layer below it enforces the value, so it was ignored.

  CliLoser* = object
    ## A candidate that was considered and is not the winner.
    value*: string
      ## The value as written (``true`` / ``false`` for a bare or negated
      ## switch, ``1`` for one occurrence of a counted flag, the optional
      ## value's marker ``<bare>`` for a bare optional-value flag).
    site*: CliSite
    fate*: CliFate

  CliOrigin* = object
    ## How one parameter's value was decided.
    winner*: CliSite
      ## The winning source. For a value collected from several candidates
      ## (a list, a counted flag, ``append``, a combine proc) it is the last
      ## candidate considered.
    values*: seq[string]
      ## The winning value as written: the winning source's candidates (a
      ## list's elements), or the ``default`` / ``implies`` expression.
    losers*: seq[CliLoser]
      ## Every other candidate, in the order the merge considered them:
      ## configuration layers lowest first, then the environment, then the
      ## command line, each in its own order.

  CliSourcedValue*[T] = object
    ## One source's value, as a combine proc receives it.
    value*: T
    origin*: CliSite

func kind*(o: CliOrigin): CliOriginKind =
  ## The winning source's kind.
  o.winner.kind

func cliCandidateValueText*(c: CliCandidate): string =
  ## A candidate's value as an origin records it.
  case c.form
  of ccfValue: c.text
  of ccfBare: "<bare>"
  of ccfNegated: "false"
  of ccfCount: "1"
  of ccfEmpty: "[]"

func cliSiteOf*(c: CliCandidate): CliSite =
  ## Where a candidate came from.
  case c.source
  of csFile:
    CliSite(kind: if c.binding: cokEnforced else: cokFile,
      layer: c.layerName, path: c.path, line: c.line, key: c.key,
      argvIndex: -1)
  of csEnv:
    CliSite(kind: cokEnv, variable: c.variable, argvIndex: -1)
  of csCli:
    CliSite(kind: cokCli, argvIndex: c.argvIndex, spelling: c.spelling)

func `$`*(s: CliSite): string =
  ## A human-readable description of a site: ``the command line ('--jobs',
  ## argument 2)``, ``environment variable TOOL_JOBS``,
  ## ``/etc/tool.toml:3 (layer 'system', enforced)``, ``the default``.
  case s.kind
  of cokUnset: "nothing"
  of cokDefault: "the default"
  of cokImplied: "implied by '" & s.impliedBy & "'"
  of cokEnv: "environment variable " & s.variable
  of cokCli:
    if s.spelling.len > 0:
      "the command line ('" & s.spelling & "', argument " &
        $s.argvIndex & ")"
    else:
      "the command line (argument " & $s.argvIndex & ")"
  of cokFile, cokEnforced:
    s.path & ":" & $s.line & " (layer '" & s.layer & "'" &
      (if s.kind == cokEnforced: ", binding)" else: ")")

func cliSourceDescription*(c: CliCandidate): string =
  ## Where a candidate came from, for an error message about a value it
  ## supplied: empty for the command line (its argv index and spelling say
  ## it), else what ``$`` of its site says.
  if c.source == csCli: "" else: $cliSiteOf(c)

func cliDescribe*(o: CliOrigin): string =
  ## A one-line explanation of an origin: the winner and every loser with
  ## its fate (for a debug report or an ``--explain`` option).
  result = o.values.join(", ") & " from " & $o.winner
  for loser in o.losers:
    result.add("; " & loser.value & " from " & $loser.site & " " &
      $loser.fate)

template cliCombineFits*(T: typedesc; combine: untyped): bool =
  ## Whether ``combine`` can be a parameter of type ``T``'s combine proc:
  ## callable as ``combine(candidates)`` with an
  ## ``openArray[CliSourcedValue[T]]`` and returning a ``T``. Used by the
  ## checks ``cliModelTypeChecks`` generates.
  compiles((block:
    let clispecCandidates: seq[CliSourcedValue[T]] = @[]
    let clispecProbe {.used.}: T = combine(clispecCandidates)
    clispecProbe))
