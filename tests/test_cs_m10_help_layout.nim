## test_cs_m10_help_layout: value placeholders, long help, help written as a
## constant expression, and the help layout (``CliHelpLayout``,
## ``cliOptionsTable``), each rendered and compared in full.
##
## ``Hl`` is a real ``cliProgram`` description; the texts below are what its
## generated ``helpText`` and ``optionsTable`` must produce. The default
## layout is today's (the existing help tests pin it for descriptions that
## use none of the new arguments); every field of the layout is exercised
## against it.

import std/[json, strutils, unittest]

import clispec

const Paragraph = "Second paragraph from a constant."
const Wide = false

cliProgram(Hl, "hl"):
  help "A help layout fixture"
  flag output is string, short = 'o', valueName = "path",
    help = "Where " & "to write", longHelp = "First more.\n\n" & Paragraph
  flag tags is seq[string], valueName = "tag",
    help = "Tags" & (when Wide: " (wide)" else: " (narrow)")
  flag jobs is int, default = 4, env = ["HL_JOBS"], help = "Parallel jobs"
  boolFlag cooperative is bool, alias = "--coop", help = "Cooperate"
  flag mode is string, values = ["a", "b"], optionalValue = "a",
    longHelp = "Only a long help."
  boolFlag color is bool, negatable = true,
    help = "Colour output, a description long enough to need wrapping " &
      "at a narrow width: averyveryveryverylongwordthatcannotbreak end."
  group "Extra", help = "More flags":
    flag level is int, help = "A level"
  pos target is string, help = "What", longHelp = "More about the target."

cliProgram(Hh, "hh"):
  flag host is string, short = 'h', help = "The host"

const plain = plainCliModel:
  flag output is string, help = Paragraph & " More.", longHelp = Paragraph

const
  defaultText = """Usage: hl [options] <target>

A help layout fixture

Arguments:
  <target>  What
            More about the target.

Options:
  -o, --output <path>    Where to write
                         First more.
                         Second paragraph from a constant.
  --tags <tag>...        Tags (narrow)
  --jobs <int>           Parallel jobs [default: 4] [env: HL_JOBS]
  --coop, --cooperative  Cooperate
  --mode[=<a|b>]         Only a long help.
  --[no-]color           Colour output, a description long enough to need wrapping at a narrow width: averyveryveryverylongwordthatcannotbreak end.

Extra:
  More flags
  --level <int>  A level
"""

  everyFieldLayout = CliHelpLayout(indent: 4, column: 24, width: 60,
    helpFlag: "Show help", listMarker: false, canonicalFirst: true,
    notes: false)

  everyFieldText = """Usage: hl [options] <target>

A help layout fixture

Arguments:
    <target>            What
                        More about the target.

Options:
    -o, --output <path>
                        Where to write
                        First more.
                        Second paragraph from a constant.
    --tags <tag>        Tags (narrow)
    --jobs <int>        Parallel jobs
    --cooperative, --coop
                        Cooperate
    --mode[=<a|b>]      Only a long help.
    --[no-]color        Colour output, a description long
                        enough to need wrapping at a narrow
                        width:
                        averyveryveryverylongwordthatcannotbreak
                        end.
    -h, --help          Show help

Extra:
    More flags
    --level <int>       A level
"""

  wrappedTable = """  -o, --output <path>   Where to write
                        First more.
                        Second paragraph from a constant.
  --tags <tag>...       Tags (narrow)
  --jobs <int>          Parallel jobs [default: 4] [env:
                        HL_JOBS]
  --coop, --cooperative
                        Cooperate
  --mode[=<a|b>]        Only a long help.
  --[no-]color          Colour output, a description long
                        enough to need wrapping at a narrow
                        width:
                        averyveryveryverylongwordthatcannotbreak
                        end.
"""

suite "test_cs_m10_help_layout":

  test "the default layout: placeholders and long help, nothing wrapped":
    check Hl.helpText() == defaultText
    check Hl.helpText(layout = CliHelpLayout()) == defaultText
    check cliHelpText(Hl.cliGrammar, 0, "hl") == defaultText

  test "every layout field at once":
    check Hl.helpText(layout = everyFieldLayout) == everyFieldText

  test "the options table alone, wrapped at a fixed column":
    check Hl.optionsTable(layout = CliHelpLayout(column: 24, width: 60)) ==
      wrappedTable
    check Hl.optionsTable(group = "Extra") == "  --level <int>  A level\n"
    check Hl.optionsTable(group = "None") == ""

  test "each field changes only its own part":
    let base = Hl.optionsTable()
    check base == defaultText.split("Options:\n")[1].split("\nExtra:")[0]
    check Hl.optionsTable(layout = CliHelpLayout(listMarker: false)) ==
      base.replace("--tags <tag>...     ", "--tags <tag>        ")
    check Hl.optionsTable(layout = CliHelpLayout(notes: false)) ==
      base.replace(" [default: 4] [env: HL_JOBS]", "")
    check Hl.optionsTable(layout = CliHelpLayout(canonicalFirst: true)) ==
      base.replace("--coop, --cooperative", "--cooperative, --coop")
    check Hl.optionsTable(layout = CliHelpLayout(helpFlag: "Show help")) ==
      base & "  -h, --help             Show help\n"
    var indented = ""
    for line in base.splitLines():
      if line.len > 0:
        indented.add("  " & line & "\n")
    check Hl.optionsTable(layout = CliHelpLayout(indent: 4)) == indented

  test "the help row lists only the spellings that request help":
    check Hh.optionsTable(layout = CliHelpLayout(helpFlag: "Show help")) ==
      "  -h, --host <string>  The host\n" &
      "  --help               Show help\n"

  test "help and longHelp written as constant expressions are evaluated":
    for p in Hl.cliModel.root.params:
      case p.name
      of "output":
        check p.help == "Where to write"
        check p.helpExpr.isSet == false
        check p.longHelp == "First more.\n\nSecond paragraph from a constant."
        check p.longHelpExpr.isSet
        check p.valueName == "path"
      of "tags":
        check p.help == "Tags (narrow)"
        check p.helpExpr.code ==
          "(\"Tags\" & (when Wide: \" (wide)\" else: \" (narrow)\"))"
      else: discard
    check plain.root.params[0].help == Paragraph & " More."
    check plain.root.params[0].longHelp == Paragraph

  test "the JSON carries the placeholder and the long help":
    let j = parseJson(Hl.helpJson())
    var seen = 0
    for p in j["command"]["parameters"]:
      case p["name"].getStr
      of "output":
        check p["placeholder"].getStr == "path"
        check p["valueName"].getStr == "string"
        check p["help"].getStr == "Where to write"
        check p["longHelp"].getStr ==
          "First more.\n\nSecond paragraph from a constant."
        inc seen
      of "mode":
        check p["placeholder"].getStr == "a|b"
        inc seen
      of "tags":
        check p["help"].getStr == "Tags (narrow)"
        inc seen
      else: discard
    check seen == 3
