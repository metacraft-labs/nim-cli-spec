## test_run_time_types_have_no_location_fields: the types a program's
## description is carried in have no field a source location could be
## written in.
##
## Where a part of a description was written is for compile-time
## diagnostics only, so it is kept beside the model, in the located model
## ``parseCliModel`` returns (``CliLocatedModel``: a ``CliModel`` and a
## ``CliModelLocations``), and never inside it. Every type a program carries
## its description in (the model ``Tool.cliModel`` and ``plainCliModel``
## return, the grammar ``Tool.cliGrammar`` returns, a configuration table)
## is walked here, field by field and through every ``seq``, ``array``,
## ``tuple`` and nested object, at compile time. None may hold:
##
## * a field of one of the location types (``CliSourceLocation``,
##   ``CliParamLocations``, ``CliCommandLocations``, ``CliModelLocations``,
##   ``CliGrammarLocations``, ``CliLocatedModel``) or of the compiler's
##   ``LineInfo``;
## * a field whose name says it is a source location: one of
##   ``locationNames`` (``file``, ``line``, ``column``, ``location``,
##   ``sourcePath``, ``lineInfo``, ...) or a name ending in one of
##   ``locationSuffixes`` (``sourceFile``, ``declLine``, ``startColumn``,
##   ``writtenLocation``, ...), compared case- and underscore-insensitively.
##   No field of the model or the grammar is named so today
##   (``fileSources``, ``position``, ``source`` and ``path`` are not).
##
## The walk is checked against types that do hold locations (a walk that
## found nothing anywhere would pass the first checks vacuously), and the
## removed fields are checked one by one with ``compiles``. A field added back to any run-time type, under either kind
## of name or type, fails this test.
##
## The types are the library's own; nothing is mocked.

import std/[macros, strutils, unittest]

import clispec

type
  SampleCommandExt = object
    ## An extension a consumer might attach to commands.
    note: string
  SampleParamExt = object
    ## An extension a consumer might attach to parameters.
    role: int
    tags: seq[string]

  LocatedHolder = object
    ## Control: what the walk must find, by type.
    model: PlainCliModel
    locations: CliModelLocations
    problem: CliGrammarProblem

  NamedHolder = object
    ## Control: what the walk must find, by name.
    name: string
    source_line: int

const
  locationNames = ["file", "filename", "line", "lineno", "column", "col",
    "location", "loc", "lineinfo", "sourcepath", "srcpath", "at"]
    ## Field names that are a location by themselves.
  locationSuffixes = ["file", "filename", "line", "lineno", "column",
    "location", "lineinfo"]
    ## Endings that make a longer name one (``sourceFile``).

func namesALocation(name: string): bool =
  ## Whether a field's name says it holds a source location.
  let n = name.toLowerAscii.replace("_", "")
  if n in locationNames:
    return true
  for suffix in locationSuffixes:
    if n.endsWith(suffix):
      return true
  false

proc locationFields(T: typedesc; path: string; seen: var seq[string];
                    found: var seq[string]) =
  ## Appends to ``found`` every field reachable from ``T`` that could hold
  ## a source location, as its path from the walked type. ``seen`` holds the
  ## types already walked (the walk is over types, so a recursive type is
  ## walked once).
  when T is CliSourceLocation or T is CliParamLocations or
      T is CliCommandLocations or T is CliModelLocations or
      T is CliGrammarLocations or T is CliLocatedModel or T is LineInfo:
    found.add(path & ": " & $T)
  elif T is object or T is tuple:
    let name = $T
    if name in seen:
      return
    seen.add(name)
    var value = default(T)
    for fieldName, field in fieldPairs(value):
      if namesALocation(fieldName):
        found.add(path & "." & fieldName)
      locationFields(typeof(field), path & "." & fieldName, seen, found)
  elif T is seq or T is array:
    var value = default(T)
    locationFields(typeof(value[0]), path & "[]", seen, found)
  elif T is ref or T is ptr:
    var value = default(T)
    locationFields(typeof(value[]), path & "[]", seen, found)
  else:
    discard

proc locationFieldsOf(T: typedesc): seq[string] =
  ## Every location-holding field reachable from ``T``.
  var seen: seq[string] = @[]
  locationFields(T, $T, seen, result)

# Computed by the compiler: the walk is over types alone.
const
  inGrammar = locationFieldsOf(CliGrammar)
  inPlainModel = locationFieldsOf(PlainCliModel)
  inExtendedModel = locationFieldsOf(
    CliModel[SampleCommandExt, SampleParamExt])
  inConfigTable = locationFieldsOf(CliConfigTable)
  inColorConfig = locationFieldsOf(CliColorConfig)
  inLocatedHolder = locationFieldsOf(LocatedHolder)
  inNamedHolder = locationFieldsOf(NamedHolder)

suite "test_run_time_types_have_no_location_fields":

  test "the grammar a program carries has no location field":
    checkpoint($inGrammar)
    check inGrammar.len == 0

  test "the model a program carries has no location field":
    checkpoint($inPlainModel)
    check inPlainModel.len == 0
    # A consumer's extension types are walked too: they are its own, but
    # the library adds nothing around them.
    checkpoint($inExtendedModel)
    check inExtendedModel.len == 0

  test "a configuration table and the colour configuration have none":
    checkpoint($inConfigTable)
    check inConfigTable.len == 0
    checkpoint($inColorConfig)
    check inColorConfig.len == 0

  test "control: the walk finds a location by type and by name":
    checkpoint($inLocatedHolder)
    # ``problem.at`` is found twice: by its name and by its type.
    check inLocatedHolder == @["LocatedHolder.locations: CliModelLocations",
      "LocatedHolder.problem.at", "LocatedHolder.problem.at: CliSourceLocation"]
    checkpoint($inNamedHolder)
    check inNamedHolder == @["NamedHolder.source_line"]
    check locationFieldsOf(CliLocatedModel[NoCliExtension,
      NoCliExtension]).len == 1
    check namesALocation("sourceFile")
    check namesALocation("sourceColumn")
    check namesALocation("lineInfo")
    check namesALocation("line")
    check namesALocation("declared_line")
    check namesALocation("file")
    check namesALocation("startColumn")
    check namesALocation("writtenLocation")
    check not namesALocation("fileSources")
    check not namesALocation("position")
    check not namesALocation("source")
    check not namesALocation("path")
    check not namesALocation("declaredIn")

  test "no removed location field can be written":
    check not compiles(CliExpr().sourceFile)
    check not compiles(CliExpr().sourceLine)
    check not compiles(CliExpr().sourceColumn)
    check not compiles(CliExpr(code: "1", sourceLine: 1))
    check not compiles(PlainCliParam().sourceFile)
    check not compiles(PlainCliParam(sourceLine: 1))
    check not compiles(PlainCliCommand().sourceFile)
    check not compiles(PlainCliCommand(sourceLine: 1))
    check not compiles(CliGroup().sourceFile)
    check not compiles(CliRetired().sourceLine)
    check not compiles(CliGrammarCommand().sourceFile)
    check not compiles(CliGrammarCommand(sourceLine: 1))
    # Control: the fields that remain are writable the same way.
    check compiles(CliExpr(code: "1"))
    check compiles(PlainCliParam(name: "x"))
    check compiles(CliGrammarCommand(name: "x"))
    check compiles(CliSourceLocation(file: "f", line: 1, column: 2))
