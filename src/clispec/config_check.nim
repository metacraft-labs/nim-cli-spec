## Checking configuration against a description: the keys a program reads
## from its configuration files, as a table, and a validator over values.
##
## A description says which parameters a configuration file may set, under
## which key in each file source, with which value type and closed value set
## (``clispec/model``, "Names and configuration keys" and "Naming
## conventions"). A program that *writes* such a file for another program
## (a build system generating a tool's configuration, an installer, a
## migration) can check what it writes against the reader's description
## instead of finding out when the reader refuses it. This module provides
## the two forms that check takes:
##
## * ``cliConfigTableOf`` derives a ``CliConfigTable`` from a grammar: one
##   entry per key, sorted, with the value type, whether it is a list and
##   the closed value set. It is a plain value, so it can be computed once
##   into a ``const`` and read by compile-time code (a macro checking a
##   configuration snippet written in code) as well as at run time (a
##   validator walking a whole file). Deriving it is the only step that
##   reads the description; every check afterwards is a lookup in it.
## * ``cliCheckEntry`` checks one key and its value against the table, and
##   ``cliValidateDocument`` walks a whole document once, in file order. A
##   document is the format-independent value tree below
##   (``CliConfigDocument``): a format adapter (a TOML reader, say) turns a
##   file's text into it, with each value's line, and the checks are the
##   same for every format. This module reads no format itself and depends
##   on no serialization library.
##
## For a generated program's grammar (``Tool.cliGrammar``, see
## ``clispec/program``) the table is ``cliConfigTableOf(Tool.cliGrammar)``.
## A macro that builds its own model (a consumer's extension of the ``cli:``
## language) gets the code of the table's constant from
## ``cliConfigTableCode``, which fills in the facts only the compiler knows
## (each value's type and an enum's values) where the description's types
## are visible.
##
## Which keys a table holds
## ========================
##
## * A description that declares a ``configSchema`` is a program reading
##   files in clispec's own layout: every parameter that files may supply
##   has a key, derived or declared, and the file's top-level ``schema``
##   string (which must equal the identifier) and anything under the
##   top-level ``extensions`` table are the file's own, never parameters.
## * A description without one (an external tool's, whose files are in that
##   tool's own layout) holds only the keys the description spells itself,
##   with ``key`` or a ``perSource`` entry for a file source: a derived key
##   is clispec's convention, not a statement about the tool, so it is not
##   taken as one of the tool's keys, and nothing is reserved.
##
## Keys are spelt as the table's file source spells them (``file`` by
## default, or a named source the description declares). Several
## parameters may share one key (the same setting accepted by several
## subcommands); the table holds it once, as the first declaration gives it.
##
## What is checked
## ===============
##
## For each key: that it is a key of the table, or a table (a key prefix)
## that holds some; that a value has the parameter's configuration type
## (``CliConfigType``: a string, an integer, a float, which accepts an
## integer too, or a bool, and an array of these for a list parameter; a
## counted flag takes an integer); and that a value of a parameter with a
## closed value set is one of its texts. A key that is not in the table but
## differs from one only by naming convention (``pool-size`` against
## ``pool_size``) is reported with the table's spelling as a suggestion.
##
## The checks are the ones confutils applies when it loads a configuration
## layer, so a file a writer checked here loads there.

import std/[algorithm, macros, strutils, typetraits]

import ./[model, grammar, values]

export CliConfigType, cliChoiceTexts, cliChoiceTextsOf, cliIsEnum

type
  CliConfigValueKind* = enum
    ## The kind of a value in a configuration document.
    ccvString = "a string"
    ccvInteger = "an integer"
    ccvFloat = "a float"
    ccvBool = "a bool"
    ccvDateTime = "a date-time"
    ccvArray = "an array"
    ccvTable = "a table"
      ## A table: inside an array, or, when a check is asked about a key
      ## path itself (a section of a snippet), the section.
    ccvTableArray = "an array of tables"

  CliConfigValue* = object
    ## One value of a configuration document.
    kind*: CliConfigValueKind
    text*: string
      ## A scalar's value as text: a string's content, an integer in
      ## decimal, a float as Nim prints it, ``true`` or ``false``, a
      ## date-time as written.
    items*: seq[CliConfigValue]
      ## An array's elements.

  CliConfigEntry* = object
    ## One key of a configuration document with its value.
    key*: seq[string]
      ## The key's segments, from the top of the document (a table header's
      ## segments followed by the key's own).
    value*: CliConfigValue
    line*: int
      ## The line the key is written on (1-based), or 0 when the document
      ## has no lines (a value built in code).

  CliConfigDocument* = object
    ## A configuration document, flattened: what a format adapter read from
    ## a file, or what a writer built in code.
    entries*: seq[CliConfigEntry]
      ## Every value, in document order. Tables (inline ones included) are
      ## flattened into their values; an array of tables is one entry of
      ## kind ``ccvTableArray``.

  CliConfigTableEntry* = object
    ## One key of a ``CliConfigTable``.
    key*: string
      ## The key as the table's source spells it, segments joined with
      ## ``.``.
    segments*: seq[string]
    param*: string
      ## The name of the (first) parameter it sets.
    paramId*: int
      ## That parameter's id in the grammar.
    configType*: CliConfigType
    list*: bool
      ## The value is an array of ``configType``.
    choices*: seq[string]
      ## The closed value set's texts; empty when the set is open.
    order*: string
      ## The segments joined with NUL: the sort and search key.

  CliConfigTable* = object
    ## The configuration keys of one description in one file source,
    ## derived once (``cliConfigTableOf``) and then only read.
    program*: string
      ## The description's program name, for messages.
    source*: string
      ## The file source the keys are spelt for.
    convention*: CliConvention
      ## That source's naming convention.
    schema*: string
      ## The description's ``configSchema``; empty for an external tool's
      ## description (see "Which keys a table holds").
    entries*: seq[CliConfigTableEntry]
      ## Sorted by ``order``.
    prefixes*: seq[string]
      ## Every proper prefix of a key (a table that holds keys), as NUL
      ## joined segments, sorted.

  CliConfigIssueKind* = enum
    ## What a check found wrong. ``cikNone`` is a value that fits.
    cikNone = "no issue"
    cikUnknownKey = "unknown key"
      ## Neither a key of the table nor a table that holds one.
    cikWrongType = "wrong type"
      ## The value does not have the key's type (a section where a value
      ## belongs, or a value where a section does, included).
    cikNotAllowed = "value not allowed"
      ## A value outside the key's closed value set.
    cikMissingSchema = "missing schema"
      ## A whole file without the top-level ``schema`` string.
    cikWrongSchema = "wrong schema"
      ## A ``schema`` other than the description's.

  CliConfigIssue* = object
    ## One finding of a check.
    kind*: CliConfigIssueKind
    key*: string
      ## The key, segments joined with ``.`` (quoted where a segment needs
      ## it), as the document spells it.
    line*: int
      ## The entry's line, 0 when unknown.
    expected*: string
      ## What would have been accepted.
    found*: string
      ## What was there.
    suggestion*: string
      ## For ``cikUnknownKey``: the table's key that differs from this one
      ## only by naming convention, or empty.

const
  CliSchemaKey* = "schema"
    ## The top-level key a clispec configuration file declares its schema
    ## in.
  CliExtensionsKey* = "extensions"
    ## The top-level table a clispec program never reads: the escape hatch.

var cliConfigTableDerivations {.compileTime.}: int
  ## How many tables ``cliConfigTableOf`` has derived at compile time in
  ## this compilation (``cliConfigTableDerivationCount``).

proc cliConfigTableDerivationCount*(): int {.compileTime.} =
  ## The number of tables derived at compile time so far in this
  ## compilation. A consumer that promises to derive a description's table
  ## once, however many snippets it checks against it, tests that promise
  ## with this count.
  cliConfigTableDerivations

func orderOf(segments: openArray[string]): string =
  segments.join("\0")

func cliConfigKeyText*(segments: openArray[string]): string =
  ## A key as a message shows it: segments joined with ``.``, a segment
  ## that needs it quoted.
  for i, s in segments:
    if i > 0:
      result.add('.')
    var bare = s.len > 0
    for ch in s:
      if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
        bare = false
    if bare: result.add(s) else: result.add(escape(s))

func lowerBound(xs: openArray[string]; x: string): int =
  var lo = 0
  var hi = xs.len
  while lo < hi:
    let mid = (lo + hi) div 2
    if xs[mid] < x: lo = mid + 1 else: hi = mid
  lo

func entryIndex(t: CliConfigTable; order: string): int =
  ## The index of the entry whose order is ``order``, or -1.
  var lo = 0
  var hi = t.entries.len
  while lo < hi:
    let mid = (lo + hi) div 2
    if t.entries[mid].order < order: lo = mid + 1 else: hi = mid
  if lo < t.entries.len and t.entries[lo].order == order: lo else: -1

func isPrefix(t: CliConfigTable; order: string): bool =
  let i = lowerBound(t.prefixes, order)
  i < t.prefixes.len and t.prefixes[i] == order

func holdsKey(g: CliGrammar; p: CliGrammarParam): bool =
  p.configKey.len > 0 and csFile in p.sources and
    (g.configSchema.len > 0 or p.keyDeclared)

func cliConfigTableOf*(g: CliGrammar; source = CliSourceFile):
    CliConfigTable =
  ## The configuration keys of a grammar in the file source ``source``
  ## (``file``, or a named source the description declares; an undeclared
  ## name is read as ``file``). A grammar built by ``cliGrammarOf`` alone
  ## has no value types or closed sets yet (they need the compiler); use a
  ## generated program's ``cliGrammar`` or ``cliConfigTableCode``.
  when nimvm:
    {.cast(noSideEffect).}:
      inc cliConfigTableDerivations
  else:
    discard
  result.program = g.program
  result.source = if cliHasFileSource(g, source): source else: CliSourceFile
  result.convention = cliFileSourceConvention(g, result.source)
  result.schema = g.configSchema
  var entries: seq[CliConfigTableEntry] = @[]
  for id, p in g.params:
    if not holdsKey(g, p):
      continue
    let key = cliSourceKeyOf(p, result.source)
    let segments = key.split('.')
    entries.add(CliConfigTableEntry(key: key, segments: segments,
      param: p.name, paramId: id,
      configType: (if p.counted: cctInteger else: p.configType),
      list: p.isList and not p.counted, choices: p.choices,
      order: orderOf(segments)))
  # ``sort`` is a merge sort, so it is stable: of the parameters sharing a
  # key, the first declared stays first, and is the one kept.
  entries.sort(proc (a, b: CliConfigTableEntry): int = cmp(a.order, b.order))
  for e in entries:
    if result.entries.len > 0 and result.entries[^1].order == e.order:
      continue
    result.entries.add(e)
  for e in result.entries:
    for n in 1 ..< e.segments.len:
      result.prefixes.add(orderOf(e.segments[0 ..< n]))
  result.prefixes.sort()
  var unique: seq[string] = @[]
  for p in result.prefixes:
    if unique.len == 0 or unique[^1] != p:
      unique.add(p)
  result.prefixes = unique

func cliConfigFind*(t: CliConfigTable; segments: openArray[string]): int =
  ## The index in ``t.entries`` of the key ``segments``, or -1.
  entryIndex(t, orderOf(segments))

func cliConfigTableKeys*(t: CliConfigTable): seq[string] =
  ## Every key of the table, sorted.
  for e in t.entries:
    result.add(e.key)

func expectedText(t: CliConfigType; list: bool): string =
  let one = case t
    of cctString: "a string"
    of cctInteger: "an integer"
    of cctFloat: "a number"
    of cctBool: "true or false"
  if list: "an array of " & (case t
    of cctString: "strings"
    of cctInteger: "integers"
    of cctFloat: "numbers"
    of cctBool: "bools")
  else: one

func cliConfigExpectedText*(e: CliConfigTableEntry): string =
  ## What a key accepts, as a message says it: ``a string``, ``an array of
  ## integers``.
  expectedText(e.configType, e.list)

func cliConfigFoundText*(v: CliConfigValue): string =
  ## A value as a message names it: ``the string "x"``, ``an integer 4``,
  ## ``a table``.
  case v.kind
  of ccvString: "the string " & escape(v.text)
  of ccvInteger, ccvFloat, ccvBool, ccvDateTime: $v.kind & " " & v.text
  else: $v.kind

func fits(v: CliConfigValue; t: CliConfigType): bool =
  case t
  of cctString: v.kind == ccvString
  of cctInteger: v.kind == ccvInteger
  of cctFloat: v.kind in {ccvFloat, ccvInteger}
  of cctBool: v.kind == ccvBool

func wordsKey(segments: openArray[string]): string =
  ## A key with every segment reduced to its lower-case words, so two
  ## spellings of one key in different conventions compare equal.
  for i, s in segments:
    if i > 0:
      result.add('\0')
    result.add(cliConvert(s, cnSnakeCase).toLowerAscii)

func suggestionFor(t: CliConfigTable; segments: openArray[string]): string =
  let wanted = wordsKey(segments)
  for e in t.entries:
    if e.segments.len == segments.len and wordsKey(e.segments) == wanted:
      return e.key
  ""

func cliCheckEntry*(t: CliConfigTable; segments: openArray[string];
                    value: CliConfigValue; textKnown = true;
                    line = 0): CliConfigIssue =
  ## Checks one key and its value. ``value`` of kind ``ccvTable`` asks
  ## whether ``segments`` may be a section. ``textKnown = false`` checks
  ## the kind only (a value computed later, whose text a compile-time check
  ## cannot see; the closed set is then left to the run-time check).
  ## Returns an issue of kind ``cikNone`` when the entry fits; the
  ## top-level ``schema`` string and the ``extensions`` table of a clispec
  ## file always do here (``cliValidateDocument`` checks the schema).
  result = CliConfigIssue(kind: cikNone, key: cliConfigKeyText(segments),
    line: line)
  if segments.len == 0:
    return
  if t.schema.len > 0 and (segments[0] == CliExtensionsKey or
      (segments.len == 1 and segments[0] == CliSchemaKey)):
    return
  let order = orderOf(segments)
  let i = entryIndex(t, order)
  if i < 0:
    if value.kind == ccvTable and isPrefix(t, order):
      return
    # A section or value under a key that takes a value: the key's type is
    # what is wrong.
    for n in countdown(segments.len - 1, 1):
      let k = entryIndex(t, orderOf(segments[0 ..< n]))
      if k >= 0:
        result.kind = cikWrongType
        result.key = cliConfigKeyText(segments[0 ..< n])
        result.expected = cliConfigExpectedText(t.entries[k])
        result.found = "a table"
        return
    if isPrefix(t, order):
      result.kind = cikWrongType
      result.expected = "a table"
      result.found = cliConfigFoundText(value)
      return
    result.kind = cikUnknownKey
    result.suggestion = suggestionFor(t, segments)
    return
  let e = t.entries[i]
  var ok = false
  if e.list:
    ok = value.kind == ccvArray
    if ok:
      for item in value.items:
        if not fits(item, e.configType):
          ok = false
  else:
    ok = fits(value, e.configType)
  if not ok:
    result.kind = cikWrongType
    result.expected = cliConfigExpectedText(e)
    result.found = cliConfigFoundText(value)
    return
  if textKnown and e.choices.len > 0:
    template check(v: CliConfigValue) =
      if v.text notin e.choices:
        result.kind = cikNotAllowed
        result.expected = "one of: " & e.choices.join(", ")
        result.found = cliConfigFoundText(v)
        return
    if e.list:
      for item in value.items:
        check(item)
    else:
      check(value)

func cliConfigIssueText*(issue: CliConfigIssue): string =
  ## What an issue says about its entry, without the file and line:
  ## ``unknown key 'x' (did you mean 'y'?)``, ``key 'x' has the string
  ## "a"; expected an integer``.
  case issue.kind
  of cikNone: ""
  of cikUnknownKey:
    "unknown key '" & issue.key & "'" &
      (if issue.suggestion.len > 0: " (did you mean '" & issue.suggestion &
        "'?)" else: "")
  of cikWrongType, cikNotAllowed:
    "key '" & issue.key & "' has " & issue.found & "; expected " &
      issue.expected
  of cikMissingSchema:
    "has no top-level `schema` string; expected schema = \"" &
      issue.expected & "\""
  of cikWrongSchema:
    "declares schema \"" & issue.found & "\"; expected \"" &
      issue.expected & "\""

func cliConfigIssueMessage*(issue: CliConfigIssue; path: string): string =
  ## An issue as one line naming the document: ``<path>[:<line>]: <text>``.
  (if path.len > 0: path else: "<no file>") &
    (if issue.line > 0: ":" & $issue.line else: "") & ": " &
    cliConfigIssueText(issue)

func cliValidateDocument*(t: CliConfigTable; doc: CliConfigDocument;
                          wholeFile = true): seq[CliConfigIssue] =
  ## Every issue of a document, in document order, from one pass over its
  ## entries. ``wholeFile`` checks the top-level ``schema`` string of a
  ## clispec file (a table with a ``schema``): it must be present and equal
  ## the description's; a snippet (``wholeFile = false``) need not carry
  ## one.
  var schemaSeen = false
  for e in doc.entries:
    if t.schema.len > 0 and e.key.len == 1 and e.key[0] == CliSchemaKey:
      schemaSeen = true
      if e.value.kind != ccvString or e.value.text != t.schema:
        result.add(CliConfigIssue(kind: cikWrongSchema, key: CliSchemaKey,
          line: e.line, expected: t.schema,
          found: (if e.value.kind == ccvString: e.value.text
                  else: cliConfigFoundText(e.value))))
      continue
    let issue = cliCheckEntry(t, e.key, e.value, line = e.line)
    if issue.kind != cikNone:
      result.add(issue)
  if wholeFile and t.schema.len > 0 and not schemaSeen:
    result.add(CliConfigIssue(kind: cikMissingSchema, expected: t.schema))

# ---------------------------------------------------------------------------
# Compile-time support: values described by their Nim types, and the code of
# a table's constant for a consumer's own model.
# ---------------------------------------------------------------------------

template cliConfigElementType*(T: typedesc): typedesc =
  ## ``T``'s element type for a ``seq``, else ``T``.
  when T is seq: typeof(default(T)[0]) else: T

func cliConfigValueKindOf*[T](t: typedesc[T]): CliConfigValueKind =
  ## The kind of value a Nim value of type ``T`` is written as in a
  ## configuration document: integers as integers, floats as floats,
  ## ``bool`` as a bool, a ``seq`` as an array, everything else (strings,
  ## enums, characters, paths) as a string.
  when T is seq:
    ccvArray
  elif T is distinct:
    cliConfigValueKindOf(distinctBase(T))
  elif T is bool:
    ccvBool
  elif T is SomeFloat:
    ccvFloat
  elif T is SomeInteger or T is range:
    ccvInteger
  else:
    ccvString

func cliConfigShapeOf*[T](t: typedesc[T]; text = ""): CliConfigValue =
  ## A value of type ``T`` as a check sees it before it exists: its kind,
  ## the kind of its element for a ``seq``, and ``text`` when the caller
  ## knows it (a literal).
  result = CliConfigValue(kind: cliConfigValueKindOf(T), text: text)
  when T is seq:
    result.items = @[CliConfigValue(
      kind: cliConfigValueKindOf(cliConfigElementType(T)))]

func cliConfigTypeFor*[T](t: typedesc[T]): CliConfigType =
  ## ``cliConfigTypeOf`` (``clispec/values``), for generated code.
  cliConfigTypeOf(T)

proc cliConfigTableCode*[C, P](model: CliModel[C, P]; program: string;
                               source = CliSourceFile): NimNode =
  ## The code of an expression whose value is the ``CliConfigTable`` of
  ## ``model`` in ``source``, for a macro that builds its own model (with an
  ## extension) and wants the table as a constant: ``cliConfigTableOf``
  ## over the model's grammar, with the facts only the compiler knows filled
  ## in for every parameter that has a key: its value type
  ## (``cliConfigTypeFor`` of the declared type) and closed value set (the
  ## ``values`` entries, or an enum's values). The derivation runs where the
  ## code is evaluated, so a ``const`` holding it derives the table once.
  ## Place it where the description's types are visible and where
  ## ``clispec/config_check`` is imported. A model that is not a parseable
  ## program's command line (an external tool's) still has a table: the
  ## grammar problems ``cliGrammarOf`` reports concern parsing, not keys.
  ## The grammar the code carries keeps only what the table reads (no
  ## commands, help texts or completers).
  var problems: seq[CliGrammarProblem] = @[]
  var decls: seq[CliParam[P]] = @[]
  var g = cliGrammarOf(model, program, problems, decls)
  g.commands = @[]
  g.groups = @[]
  for p in g.params.mitems:
    p.help = ""
    p.longHelp = ""
    p.completer = ""
    p.alsoSets = @[]
  let gv = genSym(nskVar, "configGrammar")
  var body = newStmtList(newVarStmt(gv, newLit(g)))
  for id, p in g.params:
    if not holdsKey(g, p):
      continue
    let decl = decls[id]
    let fieldType = parseExpr(p.nimType)
    let param = nnkBracketExpr.newTree(newDotExpr(gv, ident("params")),
      newLit(id))
    body.add(newAssignment(newDotExpr(param, ident("isList")),
      infix(fieldType, "is", ident("seq"))))
    body.add(newAssignment(newDotExpr(param, ident("configType")),
      newCall(ident("cliConfigTypeFor"), fieldType.copyNimTree)))
    let elemType = newCall(ident("cliConfigElementType"),
      fieldType.copyNimTree)
    if decl.values.len > 0:
      var lit = nnkBracket.newTree()
      for v in decl.values:
        lit.add(parseExpr(v.code))
      let vs = genSym(nskLet, "values")
      let letVs = newLetStmt(vs, newCall(ident("@"), lit))
      letVs[0][1] = nnkBracketExpr.newTree(ident("seq"), elemType)
      body.add(newStmtList(letVs, newAssignment(
        newDotExpr(param, ident("choices")),
        newCall(ident("cliChoiceTextsOf"), vs))))
    else:
      body.add(nnkWhenStmt.newTree(nnkElifBranch.newTree(
        newCall(ident("cliIsEnum"), elemType.copyNimTree),
        newStmtList(newAssignment(newDotExpr(param, ident("choices")),
          newCall(ident("cliChoiceTexts"), elemType.copyNimTree))))))
  body.add(newCall(ident("cliConfigTableOf"), gv, newLit(source)))
  nnkBlockStmt.newTree(newEmptyNode(), body)
