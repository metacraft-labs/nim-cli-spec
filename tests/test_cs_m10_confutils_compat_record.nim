## test_cs_m10_confutils_compat_record: a command line described for
## confutils' type-based loader moves onto a clispec description without a
## visible change.
##
## The fixture is a generic ``record``-like command whose options are
## shaped like those of a real program that used confutils' type-based
## loader: value placeholders, long help in paragraphs (one built from a
## constant and one from a ``when`` expression), optional values that may
## also be the next word, flags that also set another parameter in
## command-line order, switches that refuse a false value,
## case-insensitive option names, ``-o=value``, and help requested in the
## loader's ways. It is described once here in clispec, with the opt-in
## compatibility rules on.
##
## The expected parse results and the expected options table are the
## output of the equivalent confutils type (the same options, as
## ``{.name.}``, ``{.abbr.}``, ``{.desc.}``, ``{.longDesc.}``,
## ``{.valueName.}``, ``{.implicitValue.}`` and ``{.alsoSets.}`` fields of
## an object) loaded by the nim-confutils fork at commit 331c5fa with
## ``load(argv, quitOnFailure = false, envVarsPrefix = "",
## negatableSwitches = false)`` and rendered with
## ``renderOptionsTable(surfaceFromType(T).globalFlags, 2, 30, 92)``,
## captured once and checked in: each parse result is printed in one
## normalised line (the fields, or the kind of error with the option and
## value it names), which this test prints the same way from clispec's
## result.

import std/[options, strutils, unittest]

import clispec

type
  Mode = enum
    early, late, lazy
  Depth = enum
    fast, full, none
  Toggle = distinct string

proc `==`(a, b: Toggle): bool {.borrow.}

proc parseCliValue(text: string; value: var Toggle) =
  let v = text.toLowerAscii
  if v notin ["on", "off"]:
    raiseCliValueError("on or off")
  value = Toggle(v)

const ExtraText = "This paragraph comes from a named constant and is " &
  "long enough to be wrapped by the table renderer."
const WideHelp = true

cliProgram(Rec, "rec record"):
  convention cli = kebabCase
  flagMatching ignoreStyle
  parsing shortEquals, helpWithAnyValue, helpInCluster,
    valueErrorsBeforeHelp, switchesRefuseFalse, lenientSwitchValues
  flag output is Option[string], short = 'o', valueName = "path",
    help = "Output file (default: <program>.out)"
  flag attach is Option[Mode], valueName = "early|late|lazy",
    alsoSets = [attachExplicit = "true"],
    help = "Attach mode. early=before the program starts; late=once it " &
      "runs; lazy=on the first use of a watched resource, which " &
      "can take a while.",
    longHelp = "Deprecated aliases: --legacy-attach, " &
      "--cooperative/--coop.\n" &
      "A second paragraph, long enough to wrap onto more than " &
      "one line of the table at a width of ninety-two columns."
  boolFlag attachExplicit is bool, sources = {}
  flag checkpointInterval is Option[int], valueName = "ms",
    help = "Checkpoint interval in milliseconds"
  boolFlag split is bool,
    help = "Split the recording into slices at checkpoints"
  flag portable is Option[Toggle], valueName = "on|off",
    optionalValue = some(Toggle("on")), acceptsNextWord = true,
    help = "Make the output usable on another machine (default off; " &
      "bare = on): bundle every file the recording names, so the " &
      "output alone is enough.",
    longHelp = ExtraText
  flag trace is Option[Depth], valueName = "fast|full|none",
    optionalValue = some(fast), acceptsNextWord = true,
    help = "Hardware trace depth (default none; bare = fast)."
  flag keepEnv is seq[string], valueName = "name",
    help = "Keep the environment variable NAME in the recorded program's " &
      "environment (repeatable). By default a recording keeps only " &
      "a short list of variables."
  boolFlag cooperative is bool, alias = "--coop",
    alsoSets = [attach = "late"],
    help = "Cooperative recording; a deprecated alias of --attach=late.",
    longHelp = "The program must already be linked with the cooperative " &
      "runtime."
  boolFlag legacyAttach is bool, alsoSets = [attach = "early"],
    help = "A deprecated alias of --attach=early."
  flag diag is seq[string], valueName = "axes",
    help = "Diagnostics axes (repeatable; the --diag-<axis> flags add to " &
      "the same list in command-line order)."
  boolFlag diagStrict is bool, alsoSets = [diag = "strict"],
    help = "The strict axis on its own (= --diag=strict)."
  boolFlag diagMemory is bool, alsoSets = [diag = "memory"],
    help = "The memory axis on its own (= --diag=memory)."
  boolFlag longSwitch is bool, perSource = [cli = "a-switch-with-a-long-name"],
    help = "A switch whose spelling fills the switch column."
  flag aslr is Option[Toggle], valueName = "on|off",
    help = "Address randomization (default on" &
      (when WideHelp: "; off on the legacy path" else: "") & ")."

const
  forkLayout = CliHelpLayout(indent: 2, column: 30, width: 92,
    helpFlag: "Show this help", listMarker: false, canonicalFirst: true,
    notes: false)
    ## The layout of confutils' ``renderOptionsTable(flags, 2, 30, 92)``.

  expectedTable =
    "  -o, --output <path>         Output file (default: <program>.out)\n" &
    "  --attach <early|late|lazy>  Attach mode. early=before the program starts; late=once it\n" &
    "                              runs; lazy=on the first use of a watched resource, which can\n" &
    "                              take a while.\n" &
    "                              Deprecated aliases: --legacy-attach, --cooperative/--coop.\n" &
    "                              A second paragraph, long enough to wrap onto more than one\n" &
    "                              line of the table at a width of ninety-two columns.\n" &
    "  --checkpoint-interval <ms>  Checkpoint interval in milliseconds\n" &
    "  --split                     Split the recording into slices at checkpoints\n" &
    "  --portable[=<on|off>]       Make the output usable on another machine (default off; bare =\n" &
    "                              on): bundle every file the recording names, so the output\n" &
    "                              alone is enough.\n" &
    "                              This paragraph comes from a named constant and is long enough\n" &
    "                              to be wrapped by the table renderer.\n" &
    "  --trace[=<fast|full|none>]  Hardware trace depth (default none; bare = fast).\n" &
    "  --keep-env <name>           Keep the environment variable NAME in the recorded program's\n" &
    "                              environment (repeatable). By default a recording keeps only a\n" &
    "                              short list of variables.\n" &
    "  --cooperative, --coop       Cooperative recording; a deprecated alias of --attach=late.\n" &
    "                              The program must already be linked with the cooperative\n" &
    "                              runtime.\n" &
    "  --legacy-attach             A deprecated alias of --attach=early.\n" &
    "  --diag <axes>               Diagnostics axes (repeatable; the --diag-<axis> flags add to\n" &
    "                              the same list in command-line order).\n" &
    "  --diag-strict               The strict axis on its own (= --diag=strict).\n" &
    "  --diag-memory               The memory axis on its own (= --diag=memory).\n" &
    "  --a-switch-with-a-long-name\n" &
    "                              A switch whose spelling fills the switch column.\n" &
    "  --aslr <on|off>             Address randomization (default on; off on the legacy path).\n" &
    "  -h, --help                  Show this help\n"
    ## ``renderOptionsTable`` of the equivalent confutils type, verbatim.

  expectedParses: seq[tuple[argv: seq[string], line: string]] = @[
  (newSeq[string](), "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["-o", "t.out"], "output=t.out attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["-o=t.out"], "output=t.out attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["-ot.out"], "output=t.out attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["-O", "t.out"], "output=t.out attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--OUTPUT", "t.out"], "output=t.out attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--Out_Put", "t.out"], "output=t.out attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--checkpoint_interval", "5"], "unknown --checkpoint_interval"),
  (@["--checkpointInterval", "5"], "unknown --checkpointInterval"),
  (@["--CHECKPOINT-INTERVAL", "5"], "output=none attach=none attachExplicit=false checkpointInterval=5 split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--checkpoint-interval", "ten"], "invalid --checkpoint-interval ten"),
  (@["--split"], "output=none attach=none attachExplicit=false checkpointInterval=none split=true portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--split=true"], "output=none attach=none attachExplicit=false checkpointInterval=none split=true portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--split=on"], "output=none attach=none attachExplicit=false checkpointInterval=none split=true portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--split=Y"], "output=none attach=none attachExplicit=false checkpointInterval=none split=true portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--split="], "output=none attach=none attachExplicit=false checkpointInterval=none split=true portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--split=false"], "false --split=false"),
  (@["--split=off"], "false --split=off"),
  (@["--split=0"], "false --split=0"),
  (@["--split=maybe"], "invalid --split maybe"),
  (@["--legacy-attach=no"], "false --legacy-attach=no"),
  (@["--portable"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=on trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--portable", "off"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=off trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--portable", "ON"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=on trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--portable=off"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=off trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--portable", "maybe"], "unexpected maybe"),
  (@["--portable=maybe"], "invalid --portable maybe"),
  (@["--portable", "-o", "x"], "output=x attach=none attachExplicit=false checkpointInterval=none split=false portable=on trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--trace"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=fast keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--trace", "full"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=full keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--trace", "bogus"], "unexpected bogus"),
  (@["--trace=none"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--legacy-attach", "--attach=lazy"], "output=none attach=lazy attachExplicit=true checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=true diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--attach=lazy", "--legacy-attach"], "output=none attach=early attachExplicit=true checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=true diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--attach", "early", "--coop"], "output=none attach=late attachExplicit=true checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=true legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--coop"], "output=none attach=late attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=true legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--cooperative", "--legacy-attach"], "output=none attach=early attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=true legacyAttach=true diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--diag=strict", "--diag-memory", "--diag=none", "--diag-strict"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag=strict,memory,none,strict diagStrict=true diagMemory=true longSwitch=false aslr=none"),
  (@["--diag-memory", "--diag", "all"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag=memory,all diagStrict=false diagMemory=true longSwitch=false aslr=none"),
  (@["--keep-env", "A", "--keep-env=B"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv=A,B cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=none"),
  (@["--aslr", "ON"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=false aslr=on"),
  (@["--attach=bogus", "-h"], "invalid --attach bogus"),
  (@["prog", "-h"], "unexpected prog"),
  (@["--portable", "maybe", "-h"], "unexpected maybe"),
  (@["--attach=bogus", "prog", "-h"], "invalid --attach bogus"),
  (@["prog", "--attach=bogus", "-h"], "unexpected prog"),
  (@["-h", "--attach=bogus"], "help"),
  (@["--split=off", "-h"], "false --split=off"),
  (@["-h"], "help"),
  (@["--help"], "help"),
  (@["--help=1"], "help"),
  (@["--help=true"], "help"),
  (@["-help"], "help"),
  (@["--HELP"], "help"),
  (@["--output"], "missing --output"),
  (@["-o"], "missing -o"),
  (@["--bogus"], "unknown --bogus"),
  (@["--bogus=1"], "unknown --bogus"),
  (@["prog"], "unexpected prog"),
  (@["--a-switch-with-a-long-name"], "output=none attach=none attachExplicit=false checkpointInterval=none split=false portable=none trace=none keepEnv= cooperative=false legacyAttach=false diag= diagStrict=false diagMemory=false longSwitch=true aslr=none"),
  ]
    ## What the equivalent confutils type's ``load`` gives for each argv.

func show[T](o: Option[T]): string =
  if o.isNone: "none" else: $o.get

func show(o: Option[Toggle]): string =
  if o.isNone: "none" else: string(o.get)

proc line(argv: seq[string]): string =
  ## One argv's result in the normalised form of the expected lines.
  try:
    let c = Rec.load(argv)
    "output=" & show(c.output) & " attach=" & show(c.attach) &
      " attachExplicit=" & $c.attachExplicit &
      " checkpointInterval=" & show(c.checkpointInterval) &
      " split=" & $c.split & " portable=" & show(c.portable) &
      " trace=" & show(c.trace) & " keepEnv=" & c.keepEnv.join(",") &
      " cooperative=" & $c.cooperative & " legacyAttach=" & $c.legacyAttach &
      " diag=" & c.diag.join(",") & " diagStrict=" & $c.diagStrict &
      " diagMemory=" & $c.diagMemory & " longSwitch=" & $c.longSwitch &
      " aslr=" & show(c.aslr)
  except CliUsageError as e:
    case e.kind
    of cekUnknownFlag: "unknown " & e.spelling
    of cekMissingValue: "missing " & e.spelling
    of cekInvalidValue: "invalid " & e.spelling & " " & e.value
    of cekSwitchFalseValue: "false " & e.spelling & "=" & e.value
    of cekUnexpectedPositional: "unexpected " & e.spelling
    else: "other " & e.msg
  except CliHelpRequest:
    "help"

suite "test_cs_m10_confutils_compat_record":

  test "the options table is the confutils renderer's, byte for byte":
    check Rec.optionsTable(layout = forkLayout) == expectedTable
    check cliOptionsTable(Rec.cliGrammar, 0, forkLayout) == expectedTable

  test "every argv parses as the confutils loader parses it":
    check expectedParses.len >= 50
    for (argv, expected) in expectedParses:
      checkpoint($argv)
      check line(argv) == expected

  test "the full help keeps clispec's own frame around the same rows":
    let text = Rec.helpText(layout = forkLayout)
    check text.startsWith("Usage: rec record [options]\n\nOptions:\n")
    check text.endsWith(expectedTable)

  test "the structured errors carry what a program words itself":
    try:
      discard Rec.load(@["--split=off"])
      check false
    except CliUsageError as e:
      check e.kind == cekSwitchFalseValue
      check e.spelling == "--split"
      check e.value == "off"
      check e.argvIndex == 0
    try:
      discard Rec.load(@["--checkpoint-interval"])
      check false
    except CliUsageError as e:
      check e.kind == cekMissingValue
      check e.expected == "ms"
    try:
      discard Rec.load(@["-o", "a", "--attach=bogus", "--help"])
      check false
    except CliUsageError as e:
      check e.kind == cekInvalidValue
      check e.argvIndex == 2
      check e.expected == "one of: early, late, lazy"
