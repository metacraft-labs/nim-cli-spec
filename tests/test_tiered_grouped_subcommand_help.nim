## test_tiered_grouped_subcommand_help: command groups and tiers.
##
## The fixture ``tests/fixtures/tiered_help/kit_cli.nim`` sorts its
## subcommands into command groups (``group "<title>":`` around ``subcmd``
## statements) and marks the rarely used ones ``tier = secondary``, at the
## root and in a nested namespace that has a group of its own, beside a
## parameter group, a hidden ``secondary`` subcommand and an ``internal``
## namespace. The test drives the generated program through ``load`` and
## compares in full with golden pages under ``tests/fixtures/tiered_help/``:
##
## * ``-h`` and ``--help`` list the ``primary`` subcommands under their
##   headings and end with the line naming ``--help-all`` and the number of
##   commands it lists; ``--help-all`` and ``help --all`` (``parsing
##   helpWord``) list both tiers, at the root and in the nested namespace;
##   at 80 and 50 columns, styled, and in the classic layout (which knows no
##   groups or tiers);
## * ``--help=json`` (and ``--help-all=json``) carries ``"group"`` and
##   ``"tier"`` on every command, both tiers listed;
## * ``__complete`` and the engine offer ``secondary`` subcommands exactly
##   like ``primary`` ones, and ``--help-all`` among the help spellings.
##   Treating ``secondary`` as ``internal`` (leaving it out wherever an
##   internal subcommand is left out) removes those candidates and those
##   rows and fails here;
## * a program that declares neither (``depot``) is unchanged: its pages
##   equal, byte for byte, the goldens ``test_cs_m5b_help_matches_design``
##   pins (read from that test's source, so the two cannot drift), its JSON
##   has no ``"tier"`` key, ``--help-all`` is an unknown flag there and
##   completion does not offer it;
## * each invalid declaration (an unknown tier, ``tier`` given twice or on
##   ``call:``, ``call:`` inside a group, a group title listing both
##   subcommands and parameters) fails to compile with its message, and the
##   same fixture without the offending line compiles. The fixtures live in
##   ``tests/fixtures/cs_m2_invalid/`` with the other invalid declarations;
##   ``nim check`` is run on them here too.
##
## Nothing is mocked: the pages, the JSON and the completion answers come
## from the real generated program, and the compile failures from the real
## compiler.

import std/[json, os, osproc, strutils, tempfiles, unittest]

import clispec

import ./fixtures/cs_m5b_help/depot_cli
import ./fixtures/tiered_help/kit_cli

const
  goldenDir = currentSourcePath().parentDir() / "fixtures" / "tiered_help"
  rootShort = staticRead(goldenDir / "root_short.txt")
  rootAll = staticRead(goldenDir / "root_all.txt")
  rootShort50 = staticRead(goldenDir / "root_short_50.txt")
  rootAll50 = staticRead(goldenDir / "root_all_50.txt")
  repoShort = staticRead(goldenDir / "repo_short.txt")
  repoAll = staticRead(goldenDir / "repo_all.txt")
  internalShort = staticRead(goldenDir / "internal_short.txt")
  rootClassic = staticRead(goldenDir / "root_classic.txt")
  rootShortStyled = staticRead(goldenDir / "root_short_styled.txt").replace(
    "ESC", "\e")
  rootJson = staticRead(goldenDir / "kit_help_json.txt")

  rootFooter = "Run 'kit --help-all' to list all 8 commands, or " &
    "'kit <command> --help' for\ndetails.\n"
    ## The hint at 80 columns: ``init``, ``build``, ``test``, ``graph``,
    ## ``sync``, ``repo``, ``lock``, ``doctor``. Neither the hidden
    ## ``debug-dump`` nor the ``internal`` namespace (not listed at the
    ## root) counts.

func width(w: int): CliHelpLayout =
  ## The default layout at another width.
  result = cliDefaultHelpLayout
  result.width = w

proc helpOf(argv: openArray[string]): ref CliHelpRequest =
  try:
    discard Kit.load(@argv)
  except CliHelpRequest as e:
    return e

proc values(cs: seq[CliCompletion]): seq[string] =
  for c in cs:
    result.add(c.value)

proc commandsIn(node: JsonNode; output: var seq[JsonNode]) =
  ## Every COMMAND object of a ``clispec-help/1`` document, depth first.
  output.add(node)
  for child in node["commands"]:
    commandsIn(child, output)

# The depot goldens, read from the test that pins them.
# ---------------------------------------------------------------------------

const designTest = staticRead(currentSourcePath().parentDir() /
  "test_cs_m5b_help_matches_design.nim")

func goldenOf(name: string): string =
  ## The triple-quoted constant ``name`` of the design test, as the compiler
  ## reads it there: a raw literal, after ``.replace("ESC", "\e")`` when
  ## the declaration applies it.
  let head = "\n  " & name & " = \"\"\""
  let at = designTest.find(head)
  doAssert at >= 0, "no golden named " & name
  let start = at + head.len
  let stop = designTest.find("\"\"\"", start)
  result = designTest[start ..< stop]
  if designTest.continuesWith(".replace(\"ESC\", \"\\e\")", stop + 3):
    result = result.replace("ESC", "\e")

# Compile failures.
# ---------------------------------------------------------------------------

const
  invalidDir = currentSourcePath().parentDir() / "fixtures" / "cs_m2_invalid"
  srcDir = currentSourcePath().parentDir().parentDir() / "src"
  invalidFixtures = ["tier_unknown", "tier_given_twice", "tier_on_call",
    "call_inside_group", "group_lists_commands_and_parameters"]

proc nimCheck(file, nimcache: string): tuple[output: string, exitCode: int] =
  ## ``nim check`` on ``file`` with the compiler that built this test,
  ## isolated from the user's and the checkout's configuration.
  var nim = getCurrentCompilerExe()
  if not fileExists(nim):
    nim = findExe("nim")
  execCmdEx(quoteShellCommand([nim, "check", "--hints:off",
    "--skipParentCfg", "--skipUserCfg", "--path:" & srcDir,
    "--nimcache:" & nimcache, file]))

suite "test_tiered_grouped_subcommand_help":

  test "the model carries each subcommand's group and tier":
    var seen: seq[(string, string, CliTier)] = @[]
    for cmd in Kit.cliModel.commands:
      seen.add((cmd.path.join(" "), cmd.group, cmd.tier))
    for expected in [("init", "", ctPrimary),
                     ("build", "Build Commands", ctPrimary),
                     ("graph", "Build Commands", ctSecondary),
                     ("repo", "Workspace Commands", ctPrimary),
                     ("repo gc", "Maintenance", ctSecondary),
                     ("repo add", "", ctPrimary),
                     ("lock", "Workspace Commands", ctSecondary),
                     ("doctor", "", ctSecondary),
                     ("internal cache-trim", "", ctSecondary)]:
      check expected in seen
    check Kit.cliModel.root.tier == ctPrimary
    check cliHasSecondaryCommands(Kit.cliGrammar)
    check cliHasCommandGroups(Kit.cliGrammar)

  test "-h and --help: primary subcommands under their headings":
    let short = helpOf(["-h"])
    check short.text == rootShort
    check not short.long and not short.all and not short.json
    let long = helpOf(["--help"])
    check long.text == rootShort   # no long help anywhere: the same page
    check long.long and not long.all
    check Kit.helpText() == rootShort
    check rootShort.endsWith("\n\n" & rootFooter)
    for secondary in ["graph", "lock", "doctor", "debug-dump", "internal"]:
      check ("  " & secondary & " ") notin rootShort
    # The word help without --all is the long page of one tier.
    let word = helpOf(["help"])
    check word.text == rootShort and word.long and not word.all
    check helpOf(["help", "build", "--all"]).text == rootShort

  test "--help-all and help --all: both tiers under their headings":
    for argv in [@["--help-all"], @["help", "--all"], @["-v", "--help-all"]]:
      let e = helpOf(argv)
      check e.text == rootAll
      check e.long and e.all and not e.json
    check Kit.helpText(long = true, all = true) == rootAll
    check rootAll.endsWith(
      "\n\nRun 'kit <command> --help' for more on a command.\n")
    check "\nCommands:\n  init    Create a new project\n" &
      "  doctor  Diagnose the environment\n" in rootAll
    check "  graph     Print the build graph\n" in rootAll
    check "  lock  Refresh the lock files\n" in rootAll
    check "debug-dump" notin rootAll and "internal" notin rootAll

  test "a nested namespace: its own hint, its own group":
    check helpOf(["repo", "-h"]).text == repoShort
    check helpOf(["repo", "--help"]).text == repoShort
    check repoShort.endsWith("\n\nRun 'kit repo --help-all' to list all " &
      "4 commands, or 'kit repo <command> --help'\nfor details.\n")
    for argv in [@["repo", "--help-all"], @["repo", "help", "--all"]]:
      let e = helpOf(argv)
      check e.text == repoAll and e.all and e.commandPath == @["repo"]
    check "\nMaintenance:\n  Rarely needed by hand\n  gc    Collect " &
      "unreachable objects\n  fsck  Verify the object store\n" in repoAll
    # An internal namespace lists, and counts, its own subcommands.
    check helpOf(["internal", "-h"]).text == internalShort
    check "list all 2 commands" in internalShort
    # A command without subcommands: --help-all is its --help.
    check helpOf(["build", "--help-all"]).text ==
      Kit.helpText(["build"], long = true)
    check helpOf(["b", "--help-all"]).text == helpOf(["build", "-h"]).text

  test "50 columns, styled, and the classic layout":
    check Kit.helpText(layout = width(50)) == rootShort50
    check rootShort50.endsWith("\nRun 'kit --help-all' to list all 8 " &
      "commands, or\n'kit <command> --help' for details.\n")
    check Kit.helpText(layout = width(50), long = true, all = true) ==
      rootAll50
    check Kit.helpText(styled = true) == rootShortStyled
    check cliStripStyles(rootShortStyled) == rootShort
    check "\e[1;34mBuild Commands:\e[0m\n" in rootShortStyled
    check "'\e[1mkit\e[0m \e[1m--help-all\e[0m'" in rootShortStyled
    check cliStripStyles(Kit.helpText(long = true, all = true,
      styled = true)) == rootAll
    # The classic page has no groups and no tiers: every listed subcommand
    # under Commands:, whichever page is asked for.
    check Kit.helpText(layout = cliClassicHelpLayout) == rootClassic
    check Kit.helpText(layout = cliClassicHelpLayout, long = true,
      all = true) == rootClassic
    check "  doctor    Diagnose the environment\n" in rootClassic

  test "--help=json: group and tier on every command, both tiers":
    let e = helpOf(["--help=json"])
    check e.json and e.text == rootJson
    check Kit.helpJson() == rootJson
    check helpOf(["--help-all=json"]).text == rootJson
    var commands: seq[JsonNode] = @[]
    commandsIn(parseJson(rootJson)["command"], commands)
    var tiers: seq[string] = @[]
    for c in commands:
      check c.hasKey("group") and c.hasKey("tier")
      tiers.add(c["path"].to(seq[string]).join(" ") & "=" &
        c["tier"].getStr & "@" &
        (if c["group"].kind == JNull: "" else: c["group"].getStr))
    check tiers == @["=primary@", "init=primary@",
      "build=primary@Build Commands", "test=primary@Build Commands",
      "graph=secondary@Build Commands", "sync=primary@Workspace Commands",
      "repo=primary@Workspace Commands", "repo add=primary@",
      "repo list=primary@", "repo gc=secondary@Maintenance",
      "repo fsck=secondary@Maintenance",
      "lock=secondary@Workspace Commands", "doctor=secondary@"]

  test "completion offers secondary subcommands like primary ones":
    check values(Kit.complete(@[""])) == @["init", "build", "test", "graph",
      "sync", "repo", "lock", "doctor"]
    check values(Kit.complete(@["repo", ""])) ==
      @["add", "list", "gc", "fsck"]
    check values(Kit.complete(@["repo", "f"])) == @["fsck"]
    check values(Kit.complete(@["d"])) == @["doctor"]
    check values(Kit.complete(@["internal", ""])) ==
      @["cache-stats", "cache-trim"]
    check values(Kit.complete(@["--he"])) == @["--help", "--help-all"]
    check values(Kit.complete(@["repo", "--help-"])) == @["--help-all"]
    # Through the protocol a shell's script speaks.
    check Kit.completionReply(@["zsh", "l"]) ==
      "lock\tRefresh the lock files\n"
    check Kit.completionReply(@["fish", "repo", ""]) ==
      "add\tAdd a repository\nlist\tList the repositories\n" &
      "gc\tCollect unreachable objects\nfsck\tVerify the object store\n"
    try:
      discard Kit.load(@["__complete", "zsh", "do"])
      check false
    except CliCompletionRequest as e:
      check e.text == "doctor\tDiagnose the environment\n"
    # And the parser runs them.
    check Kit.load(@["doctor"]).command == KitCommand.doctor
    check Kit.load(@["repo", "gc"]).repo.command == KitRepoCommand.gc

  test "a program without groups or tiers is unchanged":
    let goldens = [
      ("rootShort80", Depot.helpText()),
      ("buildShort80", Depot.helpText(["build"])),
      ("buildLong80", Depot.helpText(["build"], long = true)),
      ("rootShort160", Depot.helpText(layout = width(160))),
      ("buildShort160", Depot.helpText(["build"], layout = width(160))),
      ("buildLong160", Depot.helpText(["build"], layout = width(160),
        long = true)),
      ("buildShort50", Depot.helpText(["build"], layout = width(50))),
      ("rootShort50", Depot.helpText(layout = width(50))),
      ("remoteShort80", Depot.helpText(["remote"])),
      ("remoteAddShort80", Depot.helpText(["remote", "add"])),
      ("remoteAddShort50", Depot.helpText(["remote", "add"],
        layout = width(50))),
      ("rootShort80Styled", Depot.helpText(styled = true)),
      ("buildShort80Styled", Depot.helpText(["build"], styled = true))]
    for (name, page) in goldens:
      checkpoint name
      check page == goldenOf(name)
    # all = true changes nothing where there is no secondary subcommand.
    check Depot.helpText(long = true, all = true) ==
      Depot.helpText(long = true)
    check not cliHasSecondaryCommands(Depot.cliGrammar)
    check not cliHasCommandGroups(Depot.cliGrammar)
    check "\"tier\"" notin Depot.helpJson()
    check "\"group\": \"" notin Depot.helpJson()
    check values(Depot.complete(@["--he"])) == @["--help"]
    try:
      discard Depot.load(@["--help-all"])
      check false
    except CliUsageError as e:
      check e.kind == cekUnknownFlag
      # Nothing about tiers is suggested to a program that has none.
      check "--help-all" notin e.suggestions
    check "--help-all" notin cliFlagSuggestions(Depot.cliGrammar, 0,
      "--help-al")
    check "--help-all" in cliFlagSuggestions(Kit.cliGrammar, 0, "--help-al")

  test "invalid declarations fail to compile, and compile without the line":
    let scratch = createTempDir("clispec_tiers_", "")
    for name in invalidFixtures:
      checkpoint name
      let fixture = invalidDir / name & ".nim"
      let text = readFile(fixture)
      var expected = ""
      var kept: seq[string] = @[]
      var removed = 0
      for line in text.splitLines():
        if line.startsWith("## expect: "):
          expected = line["## expect: ".len .. ^1]
        if line.strip().endsWith("# clispec-invalid"):
          inc removed
        else:
          kept.add(line)
      check expected.len > 0 and removed == 1
      let invalid = nimCheck(fixture, scratch / name & "_invalid")
      check invalid.exitCode != 0
      check expected in invalid.output
      let valid = scratch / name & "_valid.nim"
      writeFile(valid, kept.join("\n"))
      let fixed = nimCheck(valid, scratch / name & "_valid")
      check fixed.exitCode == 0
      if fixed.exitCode != 0:
        echo fixed.output
    removeDir(scratch)
