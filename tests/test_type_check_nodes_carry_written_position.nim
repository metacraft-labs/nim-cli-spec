## Every node of the code `cliModelTypeChecks` generates carries the
## position of the argument that was written wrong, not only its root.
##
## ``setLineInfo`` on a node does not reach its children, and the compiler
## reports a ``{.error.}`` at the position of whichever node of the pragma it
## reads. The children of a check that were created by the generator take
## the position of the code that created them, which a macro that hands the
## description on (reprobuild's ``package`` and ``defineCliInterface``) turns
## into the enclosing command's line: the error named the right parameter at
## the wrong line.
##
## The test runs the real generator on a real ``cli:`` body inside a macro
## (the only place a ``NimNode`` exists) and walks every node of every
## generated statement. No part of it is mocked.

import std/[macros, strutils, unittest]

import clispec

const csDefault = (when defined(csNever): 4 else: "four")

macro unpositionedNodes(body: untyped): untyped =
  ## The nodes of the generated checks whose line differs from the line the
  ## wrong argument was written on, as ``"<kind>@<line>"`` entries (a
  ## ``seq[string]`` literal).
  let model = parseCliModel[NoCliExtension, NoCliExtension](body,
    NoCliExtension())
  let want = model.commands[0].params[0].default.sourceLine
  var bad: seq[string] = @[]
  proc walk(n: NimNode) =
    if n.lineInfoObj.line != want:
      bad.add($n.kind & "@" & $n.lineInfoObj.line & " (want " & $want & ")")
    for child in n:
      walk(child)
  walk(cliModelTypeChecks(model))
  result = newLit(bad)

suite "cliModelTypeChecks positions every node of a check":
  test "a wrong-typed default's check is positioned throughout":
    const bad = unpositionedNodes:
      subcmd "c":
        flag jobs is int, default = csDefault
    check bad.len == 0
    if bad.len > 0:
      echo "  ", bad.join("\n  ")
