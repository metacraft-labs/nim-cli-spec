## Configuration files and the environment as sources of parameter values.
##
## A program's parameters can be supplied by three kinds of source, from
## the lowest precedence to the highest: configuration files, in the layers
## the program declares (lowest first), environment variables, and the
## command line. This module reads the first two into *candidates* (see
## ``clispec/origins``); ``clispec/parser`` merges them with the command
## line's.
##
## Layers belong to the program
## ============================
##
## Clispec does not decide which configuration files exist. A program lists
## its layers in a ``CliSources``, lowest precedence first, each with a name
## (``"system"``, ``"user"``, ``"project"``), a path and two flags:
## ``binding`` (every value the layer sets is *enforced*: no other source,
## the environment and the command line included, can override it) and
## ``required`` (a missing file is an error rather than an absent layer).
## The environment is passed in as a table, so nothing here reads the
## process's environment unless the program asks (``cliProcessEnv``).
##
## Configuration files
## ===================
##
## A file is read by a *format adapter* (``CliConfigFormat``), which turns
## its text into a flat list of entries: one per value, keyed by the full
## path of its key's segments (``[build]`` / ``jobs = 4`` and
## ``build.jobs = 4`` are both the entry ``build.jobs``), with the line it was
## written on. The adapter knows the format's syntax and nothing about the
## program. ``clispec/toml_source`` is the TOML adapter; an adapter for
## another format implements the same small interface (see
## ``CliConfigParser``).
##
## The program's schema, generated from its description, is then applied
## to the entries, the same way for every format:
##
## * the file must carry a top-level ``schema`` string equal to the
##   identifier the description declares (``configSchema "tool.config.v1"``
##   under ``cli:``);
## * every other key must be the configuration key of a parameter (see
##   ``clispec/model``, "Names and configuration keys"), except keys under a
##   top-level ``extensions`` table, which are the escape hatch for data the
##   program does not define and are never read;
## * each value must have its parameter's type (``CliConfigType``): a
##   string, an integer, a float (an integer is accepted too) or a bool, and
##   an array of these for a list parameter. A counted flag takes an
##   integer.
##
## An unknown key, a missing or wrong ``schema`` or a value of the wrong
## type is a ``CliConfigError`` naming the file, the line and the key.
## Values are read verbatim: nothing is interpolated or expanded.
##
## The environment
## ===============
##
## A parameter reads exactly the variables its ``env`` lists; the first one
## present in the table supplies the value, as text, converted like a
## command-line value. A list parameter's variable is one element, or, when
## the parameter declares a ``separator``, a delimited list of them. A
## variable that is present but empty supplies the empty string.

import std/[envvars, json, os, strutils, tables]

import ./[model, grammar, errors, origins]

export tables

type
  CliConfigValueKind* = enum
    ## The kind of a value a format adapter read.
    ccvString = "a string"
    ccvInteger = "an integer"
    ccvFloat = "a float"
    ccvBool = "a bool"
    ccvDateTime = "a date-time"
    ccvArray = "an array"
    ccvTable = "a table"
      ## A table inside an array (tables elsewhere are flattened into
      ## entries).
    ccvTableArray = "an array of tables"

  CliConfigValue* = object
    ## One value of a configuration file.
    kind*: CliConfigValueKind
    text*: string
      ## A scalar's value as text: a string's content, an integer in
      ## decimal, a float as Nim prints it, ``true`` or ``false``, a
      ## date-time as written.
    items*: seq[CliConfigValue]
      ## An array's elements.

  CliConfigEntry* = object
    ## One key of a configuration file with its value.
    key*: seq[string]
      ## The key's segments, from the top of the file (a table header's
      ## segments followed by the key's own).
    value*: CliConfigValue
    line*: int
      ## The line the key is written on (1-based).

  CliConfigDocument* = object
    ## What a format adapter read from a file.
    entries*: seq[CliConfigEntry]
      ## Every value, in file order. Tables (inline ones included) are
      ## flattened into their values; an array of tables is one entry of
      ## kind ``ccvTableArray`` on the line of its first header.

  CliConfigParser* = proc (path, content: string): CliConfigDocument {.
    gcsafe, raises: [CliConfigError].}
    ## A format adapter: reads ``content`` (the text of the file at
    ## ``path``) into a document, or raises a ``CliConfigError`` of kind
    ## ``cfeSyntax`` naming the file and the line. It checks the format's
    ## syntax only; the program's schema is applied afterwards.

  CliConfigFormat* = object
    ## A configuration-file format.
    name*: string
      ## The format's name (``"toml"``).
    parse*: CliConfigParser

  CliLayer* = object
    ## One configuration file a program reads.
    name*: string
      ## What origins and errors call the layer (``"user"``).
    path*: string
    binding*: bool
      ## Every value the layer sets is enforced: no other source can
      ## override it, and an attempt is recorded in the origin as ignored.
    required*: bool
      ## A missing file is an error; otherwise the layer is skipped.

  CliSources* = object
    ## Every source besides the command line, for one load.
    layers*: seq[CliLayer]
      ## Lowest precedence first.
    env*: Table[string, string]
      ## The environment: variable name to value.
    format*: CliConfigFormat
      ## How the layers' files are read.

  CliConfigKey* = object
    ## One key of a program's configuration-file schema.
    key*: string
    configType*: CliConfigType
    list*: bool
      ## The value is an array of ``configType``.
    param*: string
      ## The parameter's name.
    declaredIn*: seq[string]
      ## The path of the command that declares the parameter.
    help*: string

  CliConfigSchema* = object
    ## The schema of a program's configuration files, generated from its
    ## description.
    id*: string
      ## The identifier files declare in their ``schema`` string.
    keys*: seq[CliConfigKey]
      ## Every valid key, in declaration order.

const
  CliSchemaKey* = "schema"
    ## The top-level key every configuration file declares its schema in.
  CliExtensionsKey* = "extensions"
    ## The top-level table a program never reads: the escape hatch.

func keyText(segments: openArray[string]): string =
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

func keyIndex(segments: openArray[string]): string =
  ## A key's segments as one table key (segments may contain ``.``).
  segments.join("\0")

func cliConfigSchemaOf*(g: CliGrammar): CliConfigSchema =
  ## The configuration-file schema of a grammar: every parameter that a file
  ## may supply, with its key and type.
  result.id = g.configSchema
  for p in g.params:
    if p.configKey.len == 0 or csFile notin p.sources:
      continue
    result.keys.add(CliConfigKey(key: p.configKey, configType: p.configType,
      list: p.isList and not p.counted, param: p.name,
      declaredIn: p.declaredIn, help: p.help))

proc cliConfigSchemaJson*(s: CliConfigSchema): string =
  ## The schema as JSON, under the schema name ``clispec-config-schema/1``:
  ## ``{"schema", "id", "reserved": ["schema", "extensions"], "keys":
  ## [{"key", "type", "list", "parameter", "declaredIn", "help"}, ...]}``.
  ## Within that name keys are only ever added.
  var keys = newJArray()
  for k in s.keys:
    keys.add(%*{"key": k.key, "type": $k.configType, "list": k.list,
      "parameter": k.param, "declaredIn": k.declaredIn, "help": k.help})
  $(%*{"schema": "clispec-config-schema/1", "id": s.id,
    "reserved": [CliSchemaKey, CliExtensionsKey], "keys": keys})

func fits(v: CliConfigValue; t: CliConfigType): bool =
  case t
  of cctString: v.kind == ccvString
  of cctInteger: v.kind == ccvInteger
  of cctFloat: v.kind in {ccvFloat, ccvInteger}
  of cctBool: v.kind == ccvBool

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

func foundText(v: CliConfigValue): string =
  case v.kind
  of ccvString: "the string " & escape(v.text)
  of ccvInteger, ccvFloat, ccvBool, ccvDateTime: $v.kind & " " & v.text
  else: $v.kind

proc cliLoadLayer*(g: CliGrammar; layer: CliLayer; index: int;
                   format: CliConfigFormat;
                   candidates: var seq[seq[CliCandidate]]) {.
    raises: [CliConfigError].} =
  ## Reads one layer's file and appends what it supplies to
  ## ``candidates`` (indexed by parameter id). A missing file is skipped
  ## unless the layer is ``required``. Raises ``CliConfigError`` for a file
  ## that cannot be read or does not fit the program's schema.
  if not fileExists(layer.path):
    if layer.required:
      raise newCliConfigError(cfeUnreadable, layer.path, layer = layer.name,
        detail = "no such file")
    return
  if g.configSchema.len == 0:
    raise newCliConfigError(cfeNoSchemaDeclared, layer.path,
      layer = layer.name)
  if format.parse.isNil:
    raise newCliConfigError(cfeNoFormat, layer.path, layer = layer.name)
  var content: string
  try:
    content = readFile(layer.path)
  except IOError as e:
    raise newCliConfigError(cfeUnreadable, layer.path, layer = layer.name,
      detail = e.msg)
  var doc: CliConfigDocument
  try:
    doc = format.parse(layer.path, content)
  except CliConfigError as e:
    # The adapter does not know the layer's name; add it.
    raise newCliConfigError(e.kind, (if e.path.len > 0: e.path
      else: layer.path), e.line, e.key, layer.name, e.expected, e.detail)

  var byKey = initTable[string, int]()
  for id, p in g.params:
    if p.configKey.len > 0 and csFile in p.sources:
      byKey[keyIndex(p.configKey.split('.'))] = id

  var schemaSeen = false
  for e in doc.entries:
    if e.key == @[CliSchemaKey]:
      schemaSeen = true
      if e.value.kind != ccvString or e.value.text != g.configSchema:
        raise newCliConfigError(cfeWrongSchema, layer.path, e.line,
          CliSchemaKey, layer.name, g.configSchema,
          (if e.value.kind == ccvString: e.value.text
           else: foundText(e.value)))
  if not schemaSeen:
    raise newCliConfigError(cfeMissingSchema, layer.path, layer = layer.name,
      expected = g.configSchema)

  for e in doc.entries:
    if e.key.len == 0 or e.key == @[CliSchemaKey] or
        e.key[0] == CliExtensionsKey:
      continue
    let key = keyText(e.key)
    let id = byKey.getOrDefault(keyIndex(e.key), -1)
    if id < 0:
      raise newCliConfigError(cfeUnknownKey, layer.path, e.line, key,
        layer.name)
    let p = g.params[id]
    let list = p.isList and not p.counted
    let t = if p.counted: cctInteger else: p.configType
    var ok = false
    if list:
      ok = e.value.kind == ccvArray
      if ok:
        for item in e.value.items:
          if not fits(item, t):
            ok = false
    else:
      ok = fits(e.value, t)
    if not ok:
      raise newCliConfigError(cfeWrongType, layer.path, e.line, key,
        layer.name, expectedText(t, list), foundText(e.value))
    var c = CliCandidate(source: csFile, form: ccfValue, argvIndex: -1,
      valueArgvIndex: -1, layer: index, layerName: layer.name,
      binding: layer.binding, path: layer.path, line: e.line, key: key)
    if list:
      if e.value.items.len == 0:
        c.form = ccfEmpty
        candidates[id].add(c)
      for item in e.value.items:
        c.text = item.text
        c.verbatim = true
        candidates[id].add(c)
    else:
      c.text = e.value.text
      candidates[id].add(c)

proc cliEnvCandidates*(g: CliGrammar; env: Table[string, string];
                       candidates: var seq[seq[CliCandidate]]) {.
    raises: [].} =
  ## Appends what the environment supplies to ``candidates``: for each
  ## parameter that the environment may supply, the first of its ``env``
  ## variables present in ``env``.
  for id, p in g.params:
    if csEnv notin p.sources:
      continue
    for name in p.env:
      if env.hasKey(name):
        candidates[id].add(CliCandidate(source: csEnv, form: ccfValue,
          text: env.getOrDefault(name), argvIndex: -1, valueArgvIndex: -1,
          layer: -1, variable: name))
        break

proc cliSourceCandidates*(g: CliGrammar; sources: CliSources):
    seq[seq[CliCandidate]] {.raises: [CliConfigError].} =
  ## Every candidate the layers and the environment supply, per parameter
  ## id, in the order the merge considers them: the layers lowest first,
  ## then the environment.
  result = newSeq[seq[CliCandidate]](g.params.len)
  for index, layer in sources.layers:
    cliLoadLayer(g, layer, index, sources.format, result)
  cliEnvCandidates(g, sources.env, result)

proc cliProcessEnv*(): Table[string, string] =
  ## The process's environment as a table, for a program that wants its
  ## parameters' ``env`` variables read from it.
  for name, value in envPairs():
    result[name] = value
