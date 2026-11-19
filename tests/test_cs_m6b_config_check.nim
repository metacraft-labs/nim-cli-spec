## test_cs_m6b_config_check: a description's configuration keys as a table,
## and the checks a writer runs against it.
##
## ``Svc`` is a program that reads clispec configuration files: every
## parameter files may supply has a key (snake_case), the file carries a
## ``schema`` string and may hold an ``extensions`` table. ``toolTable`` is
## an external tool's description, built by a macro the way a consumer with
## its own model builds it (``cliConfigTableCode``): it declares no
## ``configSchema``, so only the keys it spells itself are keys.
##
## Each check is exercised both ways: a document that fits, and one that
## breaks it, naming the key. Nothing is mocked: the tables come from real
## descriptions through the same code a consumer runs.

import std/[macros, strutils, unittest]

import clispec

type Mode = enum
  fast, safe

cliProgram(Svc, "svc"):
  configSchema "svc.config.v1"
  convention file = snakeCase
  flag poolSize is int, default = 4
  flag mode is Mode, default = safe
  flag level is string, values = ["low", "high"]
  flag tags is seq[string]
  flag verbose is int, counted = true
  subcmd "remote":
    flag pushUrl is string
    flag ratio is float

macro externalToolTable(body: untyped): untyped =
  let model = parseCliModel[NoCliExtension, NoCliExtension](body,
    NoCliExtension())
  cliConfigTableCode(model, "tool")

const toolTable = externalToolTable:
  convention file = kebabCase
  subcmd "build":
    flag targetDir is string, key = "build.target-dir"
    flag jobs is int, key = "build.jobs"
    flag color is string, values = ["auto", "always", "never"],
      key = "term.color"
    flag manifestPath is string
  subcmd "install":
    flag targetDir is string, key = "build.target-dir"

const svcTable = cliConfigTableOf(Svc.cliGrammar)

func str(s: string): CliConfigValue = CliConfigValue(kind: ccvString, text: s)
func num(i: int): CliConfigValue = CliConfigValue(kind: ccvInteger, text: $i)

proc doc(entries: varargs[(string, CliConfigValue)]): CliConfigDocument =
  for i, (k, v) in entries:
    result.entries.add(CliConfigEntry(key: k.split('.'), value: v,
      line: i + 1))

suite "test_cs_m6b_config_check":

  test "a program's table holds every file-sourced key, in its convention":
    check svcTable.schema == "svc.config.v1"
    check svcTable.convention == cnSnakeCase
    check svcTable.cliConfigTableKeys == @["level", "mode", "pool_size",
      "remote.push_url", "remote.ratio", "tags", "verbose"]

  test "an external tool's table holds only the keys it declares":
    check toolTable.schema == ""
    check toolTable.program == "tool"
    # manifestPath has a derived key only; targetDir is declared twice and
    # held once.
    check toolTable.cliConfigTableKeys == @["build.jobs", "build.target-dir",
      "term.color"]

  test "a fitting whole file has no issues":
    let d = doc(("schema", str"svc.config.v1"), ("pool_size", num 8),
      ("mode", str"fast"), ("level", str"high"),
      ("tags", CliConfigValue(kind: ccvArray, items: @[str"a", str"b"])),
      ("verbose", num 2), ("remote.ratio", num 1),
      ("extensions.anything", str"x"))
    check cliValidateDocument(svcTable, d).len == 0

  test "unknown key, wrong type and closed sets name the key and line":
    let d = doc(("schema", str"svc.config.v1"), ("pool-size", num 8),
      ("pool_size", str"8"), ("mode", str"slow"), ("level", str"mid"),
      ("tags", CliConfigValue(kind: ccvArray, items: @[num 1])))
    let issues = cliValidateDocument(svcTable, d)
    check issues.len == 5
    check issues[0].kind == cikUnknownKey
    check issues[0].line == 2
    check cliConfigIssueMessage(issues[0], "svc.toml") ==
      "svc.toml:2: unknown key 'pool-size' (did you mean 'pool_size'?)"
    check cliConfigIssueMessage(issues[1], "svc.toml") ==
      "svc.toml:3: key 'pool_size' has the string \"8\"; expected an integer"
    check cliConfigIssueMessage(issues[2], "svc.toml") ==
      "svc.toml:4: key 'mode' has the string \"slow\"; expected one of: " &
        "fast, safe"
    check issues[3].kind == cikNotAllowed
    check issues[3].key == "level"
    check issues[4].kind == cikWrongType
    check issues[4].expected == "an array of strings"

  test "the schema string is checked for a whole file only":
    check cliValidateDocument(svcTable, doc(("pool_size", num 1)))[0].kind ==
      cikMissingSchema
    check cliValidateDocument(svcTable, doc(("pool_size", num 1)),
      wholeFile = false).len == 0
    let wrong = cliValidateDocument(svcTable, doc(("schema", str"other")))
    check wrong[0].kind == cikWrongSchema
    check cliConfigIssueText(wrong[0]) ==
      "declares schema \"other\"; expected \"svc.config.v1\""

  test "sections: a table where a value belongs and the other way round":
    let section = CliConfigValue(kind: ccvTable)
    check cliCheckEntry(svcTable, ["remote"], section).kind == cikNone
    check cliCheckEntry(svcTable, ["remote", "push_url", "x"],
      str"y").kind == cikWrongType
    let r = cliCheckEntry(svcTable, ["remote"], str"y")
    check r.kind == cikWrongType
    check r.expected == "a table"
    check cliCheckEntry(svcTable, ["nowhere"], section).kind == cikUnknownKey

  test "an external tool has no reserved keys and no schema":
    check cliCheckEntry(toolTable, ["schema"], str"x").kind == cikUnknownKey
    check cliCheckEntry(toolTable, ["extensions", "x"], str"x").kind ==
      cikUnknownKey
    check cliValidateDocument(toolTable, doc(("build.jobs", num 2))).len == 0
    let bad = cliCheckEntry(toolTable, ["term", "color"], str"sometimes")
    check bad.kind == cikNotAllowed
    check bad.expected == "one of: auto, always, never"
    check cliCheckEntry(toolTable, ["build", "target_dir"],
      str"t").suggestion == "build.target-dir"

  test "shapes from Nim types, checked at compile time":
    const ok = cliCheckEntry(svcTable, ["pool_size"], cliConfigShapeOf(int))
    const wrong = cliCheckEntry(svcTable, ["pool_size"],
      cliConfigShapeOf(string, "8"))
    const lst = cliCheckEntry(svcTable, ["tags"], cliConfigShapeOf(seq[string]),
      textKnown = false)
    const unseen = cliCheckEntry(svcTable, ["mode"], cliConfigShapeOf(string),
      textKnown = false)
    check ok.kind == cikNone
    check wrong.kind == cikWrongType
    check lst.kind == cikNone
    check unseen.kind == cikNone

  test "derivations are counted at compile time":
    # Two tables above (``toolTable`` through ``cliConfigTableCode`` and
    # ``svcTable``) and none since: reading a constant derives nothing.
    const before = cliConfigTableDerivationCount()
    const again = cliCheckEntry(svcTable, ["mode"], str"fast")
    const after = cliConfigTableDerivationCount()
    check before == 2
    check after == before
    check again.kind == cikNone
