## Building a ``cli:`` body with ``quote``: turning the tree ``quote`` produces
## back into the tree the ``cli:`` language reads.
##
## A program can export its command line as a compile-time proc returning a
## ``cli:`` body, so that another program can splice the body under one of
## its own commands and accept the same words (see "Mounting another
## program's command line" in the README). Such a proc usually builds the
## body with ``quote``, and splices shared groups of declarations into it.
## ``quote`` hands back a tree in which every name is already bound to a
## symbol of the proc's own scope: ``required = false`` names the symbol
## ``system.false``, ``seq[string]`` has become a call of the ``[]``
## operator, and a spliced group of declarations is a statement list nested
## inside the body. The ``cli:`` language reads a body as written, the way a
## macro's untyped argument is, so the body has to be turned back into that
## form before clispec (or any consumer) reads it. ``cliUnbound`` does that.
##
## This module imports only ``std/macros``, so a library that exports its
## description pays for nothing else by using it.

import std/macros

func isStringLit(n: NimNode): bool =
  n.kind in {nnkStrLit .. nnkTripleStrLit}

proc cliUnbound*(n: NimNode): NimNode {.compileTime.} =
  ## ``n`` as the ``cli:`` language reads it, with the line information of
  ## every node kept:
  ##
  ## * every symbol (and symbol choice) ``quote`` bound becomes the
  ##   identifier it was written as;
  ## * a call of the ``[]`` operator (``quote``'s form of ``seq[string]``)
  ##   becomes the bracket expression it was written as;
  ## * string literals joined with ``&`` (a long ``help`` text split over
  ##   lines) are folded into the one literal the language requires there;
  ## * a statement list nested in a statement list (a group of declarations
  ##   spliced in) is flattened into it, since its statements belong to the
  ##   scope it was spliced into.
  ##
  ## Everything else is copied as it is.
  if n.kind == nnkInfix and n.len == 3 and n[0].eqIdent("&"):
    let left = cliUnbound(n[1])
    let right = cliUnbound(n[2])
    if left.isStringLit and right.isStringLit:
      result = newLit(left.strVal & right.strVal)
      result.copyLineInfo(n)
      return
  if n.kind == nnkCall and n.len >= 2 and
      n[0].kind in {nnkSym, nnkOpenSymChoice, nnkClosedSymChoice} and
      (if n[0].kind == nnkSym: $n[0] else: $n[0][0]) == "[]":
    result = nnkBracketExpr.newNimNode(n)
    for child in n[1 .. ^1]:
      result.add(cliUnbound(child))
    return
  case n.kind
  of nnkSym:
    result = ident($n)
    result.copyLineInfo(n)
  of nnkOpenSymChoice, nnkClosedSymChoice:
    result = ident($n[0])
    result.copyLineInfo(n)
  of nnkNone, nnkEmpty, nnkIdent, nnkCharLit .. nnkUInt64Lit,
      nnkFloatLit .. nnkFloat64Lit, nnkStrLit .. nnkTripleStrLit, nnkNilLit:
    result = n
  of nnkStmtList:
    result = n.kind.newNimNode(n)
    for child in n:
      let converted = cliUnbound(child)
      if converted.kind == nnkStmtList:
        for statement in converted:
          result.add(statement)
      else:
        result.add(converted)
  else:
    result = n.kind.newNimNode(n)
    for child in n:
      result.add(cliUnbound(child))
