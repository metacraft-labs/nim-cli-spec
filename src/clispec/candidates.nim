## Candidates: the values each source supplies for a parameter.
##
## The parser (``clispec/parser``) reads argv into *candidates*: one per
## occurrence of a parameter (``--tag a --tag b`` gives two), each recording
## the argv index it was found at and the spelling used. That is the command
## line's part of a value's origin; the merge and the generated code turn the
## candidates into the typed configuration object.
##
## A library that adds other sources (configuration files and the
## environment, as confutils does over a clispec description) supplies
## candidates of the same type for them, with ``source`` saying which kind of
## source it is, ``group`` which one of its kind, and ``site`` an index into
## its own record of where each came from. Clispec converts them like the
## command line's and names them in an error by their ``described`` text.
##
## This module has no dependencies beyond the model.

import ./model

type
  CliCandidateForm* = enum
    ## How a candidate was written.
    ccfValue    ## with a value: ``--jobs 4``, ``--jobs=4``, ``-j4``, a word,
                ## or a value another source supplied
    ccfBare     ## a switch or an optional-value flag written bare
    ccfNegated  ## ``--no-<name>``
    ccfCount    ## one occurrence of a counted flag
    ccfEmpty    ## an empty list another source supplied (``tags = []`` in
                ## a configuration file): that source supplies the list, and
                ## it has no elements

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
    verbatim*: bool
      ## The text is one element as it stands and is never split on the
      ## parameter's ``separator`` (an element of a configuration-file list).
    group*: int
      ## Which source of its kind supplied the candidate, for a kind that
      ## has several (the index of a configuration-file layer). Candidates
      ## with the same ``source`` and ``group`` make up one source's value.
      ## 0 for the command line.
    site*: int
      ## For a candidate another library supplied: an index into that
      ## library's own record of where the candidate came from. Unused for
      ## the command line, which ``argvIndex`` and ``spelling`` locate.
    described*: string
      ## Where the candidate came from, in words, for an error about its
      ## value (``environment variable TOOL_JOBS``); empty for the command
      ## line.

func cliCandidateValueText*(c: CliCandidate): string =
  ## A candidate's value as text (``true`` / ``false`` stand for a negated
  ## switch, ``1`` for one occurrence of a counted flag, ``<bare>`` for a
  ## bare optional-value flag, ``[]`` for an empty list).
  case c.form
  of ccfValue: c.text
  of ccfBare: "<bare>"
  of ccfNegated: "false"
  of ccfCount: "1"
  of ccfEmpty: "[]"

func cliSameSource*(a, b: CliCandidate): bool =
  ## Whether two candidates come from the same source: the same kind of
  ## source and the same ``group``.
  a.source == b.source and a.group == b.group

func cliCandidateGroups*(cands: openArray[CliCandidate]): seq[seq[CliCandidate]] =
  ## ``cands`` split into runs from one source each, in order.
  for c in cands:
    if result.len == 0 or not cliSameSource(result[^1][^1], c):
      result.add(@[c])
    else:
      result[^1].add(c)
