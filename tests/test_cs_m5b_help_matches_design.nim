## test_cs_m5b_help_matches_design: the standard help page, rendered from
## a real ``cliProgram`` description and compared in full with the expected
## text: the short page (``-h``) and the long page (``--help``) of a
## program with subcommands, aliases, inherited flags, notes, a long
## description and examples, at 80 and 160 columns (the page is capped at
## 100) and at 50, where the sections switch to the next-line layout.
## Smaller fixtures pin the notes (the quoting of a text default, the
## possible values, counted flags and switches), group sections with an
## inherited flag, parameters' long help, ``parsing longHelpOnly``, and a
## left entry wider than 32 columns with a word longer than the line.
##
## The negative control: the same descriptions rendered with the classic
## layout (``cliClassicHelpLayout``, and any layout built field by field
## without ``style``) do not give these pages.

import std/[json, strutils, unittest]

import clispec

type
  When = enum auto, always, never
  Profile = enum debug, release
  Format = enum table, json
  Shade = enum light, dark

cliProgram(Depot, "depot"):
  help "Build and publish packages"
  convention cli = kebabCase
  flag verbose is int, counted = true, short = 'v',
    help = "Print more output; repeat for more detail"
  boolFlag quiet is bool, short = 'q', help = "Print only errors"
  flag color is When, default = auto, env = ["DEPOT_COLOR"],
    valueName = "WHEN", help = "When to colour the output"
  flag config is string, short = 'C', env = ["DEPOT_CONFIG"],
    valueName = "PATH",
    help = "Read configuration from PATH instead of the workspace's depot.toml"
  subcmd "build", help = "Build packages in the workspace", aliases = ["b"]:
    longHelp "Builds the named packages, or every package in the " &
      "workspace when none is named. Outputs go under the target " &
      "directory; a package whose inputs have not changed since its last " &
      "build is not rebuilt."
    flag jobs is int, short = 'j', default = 4, env = ["DEPOT_JOBS"],
      valueName = "N", help = "Number of parallel jobs"
    flag profile is Profile, default = debug, help = "Build profile"
    flag feature is seq[string], short = 'F', repeated = true,
      valueName = "NAME", help = "Enable a feature; may be given more than once"
    flag report is string, optionalValue = "build-report.json",
      valueName = "PATH",
      help = "Write a build report (to build-report.json when no PATH is given)"
    flag targetDir is string, default = "target",
      env = ["DEPOT_TARGET_DIR"], valueName = "DIR",
      help = "Directory for build outputs"
    pos packages is seq[string], repeated = true, required = false,
      help = "Packages to build (default: every package)"
    example "depot build -j 8 --profile release app lib",
      help = "Build two packages in release mode"
    example "depot build --feature tls --report",
      help = "Build everything with TLS and write a report"
  subcmd "remote", help = "Manage the remotes packages are published to",
      aliases = ["remotes"]:
    subcmd "add", help = "Add a remote":
      boolFlag mirror is bool, help = "Mirror every package to this remote"
      pos name is string
      pos url is string, position = 1
    subcmd "remove", help = "Remove a remote", aliases = ["rm"]:
      pos name is string
    subcmd "list", help = "List the remotes", aliases = ["ls"]:
      flag format is Format, default = table, help = "Output format"

cliProgram(Ph, "ph"):
  help "Notes and long help"
  flag level is int, counted = true, short = 'l', help = "Level"
  group "Output", help = "Where results go":
    flag out is string, default = "", help = "Output file"
  subcmd "run", help = "Run a thing":
    longHelp "First paragraph of the long help.\nSecond paragraph."
    flag name is string, required = true, help = "Name",
      longHelp = "More about the name."
    flag sep is string, default = "a b", help = "Separator"
    flag tag is string, default = "x", help = "Tag"
    boolFlag fast is bool, default = true, help = "Go fast"
    group "Output":
      flag fmt is Shade, default = dark, help = "Format"
    pos shade is Shade, help = "Shade"
cliProgram(Wd, "wd"):
  flag anExtremelyLongFlagNameThatIsWide is string, valueName = "SOMETHING",
    help = "Averyveryverylongwordwithoutanyspacesthatisnotbroken and more"
  flag host is string, short = 'h', help = "A flag of its own spelt -h"
  flag secret is string, visibility = hidden, help = "Never listed"
  flag trace is bool, visibility = internal, help = "Never listed either"

cliProgram(Lo, "lo"):
  parsing longHelpOnly
  flag depth is int, short = 'd', help = "Depth", longHelp = "How deep to go."

const
  rootShort80 = """Build and publish packages

Usage: depot [options] <command>

Commands:
  build, b         Build packages in the workspace
  remote, remotes  Manage the remotes packages are published to

Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's
                       depot.toml [env: DEPOT_CONFIG]
  -h, --help           Print help

Run 'depot <command> --help' for more on a command.
"""

  buildShort80 = """Build packages in the workspace

Usage: depot build [options] [<packages>...]

Aliases: b

Arguments:
  [<packages>...]  Packages to build (default: every package)

Options:
  -j, --jobs <N>                 Number of parallel jobs [default: 4]
                                 [env: DEPOT_JOBS]
      --profile <debug|release>  Build profile [default: debug]
  -F, --feature <NAME>...        Enable a feature; may be given more than once
      --report[=<PATH>]          Write a build report (to build-report.json when
                                 no PATH is given)
      --target-dir <DIR>         Directory for build outputs [default: target]
                                 [env: DEPOT_TARGET_DIR]
  -h, --help                     Print help (see more with '--help')

Global Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's
                       depot.toml [env: DEPOT_CONFIG]

Examples:
  Build two packages in release mode
    depot build -j 8 --profile release app lib

  Build everything with TLS and write a report
    depot build --feature tls --report
"""

  buildLong80 = """Build packages in the workspace

Builds the named packages, or every package in the workspace when none is named.
Outputs go under the target directory; a package whose inputs have not changed
since its last build is not rebuilt.

Usage: depot build [options] [<packages>...]

Aliases: b

Arguments:
  [<packages>...]  Packages to build (default: every package)

Options:
  -j, --jobs <N>                 Number of parallel jobs [default: 4]
                                 [env: DEPOT_JOBS]
      --profile <debug|release>  Build profile [default: debug]
  -F, --feature <NAME>...        Enable a feature; may be given more than once
      --report[=<PATH>]          Write a build report (to build-report.json when
                                 no PATH is given)
      --target-dir <DIR>         Directory for build outputs [default: target]
                                 [env: DEPOT_TARGET_DIR]
  -h, --help                     Print help

Global Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's
                       depot.toml [env: DEPOT_CONFIG]

Examples:
  Build two packages in release mode
    depot build -j 8 --profile release app lib

  Build everything with TLS and write a report
    depot build --feature tls --report
"""

  rootShort160 = """Build and publish packages

Usage: depot [options] <command>

Commands:
  build, b         Build packages in the workspace
  remote, remotes  Manage the remotes packages are published to

Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's depot.toml
                       [env: DEPOT_CONFIG]
  -h, --help           Print help

Run 'depot <command> --help' for more on a command.
"""

  buildShort160 = """Build packages in the workspace

Usage: depot build [options] [<packages>...]

Aliases: b

Arguments:
  [<packages>...]  Packages to build (default: every package)

Options:
  -j, --jobs <N>                 Number of parallel jobs [default: 4] [env: DEPOT_JOBS]
      --profile <debug|release>  Build profile [default: debug]
  -F, --feature <NAME>...        Enable a feature; may be given more than once
      --report[=<PATH>]          Write a build report (to build-report.json when no PATH is given)
      --target-dir <DIR>         Directory for build outputs [default: target]
                                 [env: DEPOT_TARGET_DIR]
  -h, --help                     Print help (see more with '--help')

Global Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's depot.toml
                       [env: DEPOT_CONFIG]

Examples:
  Build two packages in release mode
    depot build -j 8 --profile release app lib

  Build everything with TLS and write a report
    depot build --feature tls --report
"""

  buildLong160 = """Build packages in the workspace

Builds the named packages, or every package in the workspace when none is named. Outputs go under
the target directory; a package whose inputs have not changed since its last build is not rebuilt.

Usage: depot build [options] [<packages>...]

Aliases: b

Arguments:
  [<packages>...]  Packages to build (default: every package)

Options:
  -j, --jobs <N>                 Number of parallel jobs [default: 4] [env: DEPOT_JOBS]
      --profile <debug|release>  Build profile [default: debug]
  -F, --feature <NAME>...        Enable a feature; may be given more than once
      --report[=<PATH>]          Write a build report (to build-report.json when no PATH is given)
      --target-dir <DIR>         Directory for build outputs [default: target]
                                 [env: DEPOT_TARGET_DIR]
  -h, --help                     Print help

Global Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's depot.toml
                       [env: DEPOT_CONFIG]

Examples:
  Build two packages in release mode
    depot build -j 8 --profile release app lib

  Build everything with TLS and write a report
    depot build --feature tls --report
"""

  buildShort50 = """Build packages in the workspace

Usage: depot build [options] [<packages>...]

Aliases: b

Arguments:
  [<packages>...]
            Packages to build (default: every
            package)

Options:
  -j, --jobs <N>
            Number of parallel jobs [default: 4]
            [env: DEPOT_JOBS]
      --profile <debug|release>
            Build profile [default: debug]
  -F, --feature <NAME>...
            Enable a feature; may be given more
            than once
      --report[=<PATH>]
            Write a build report (to
            build-report.json when no PATH is
            given)
      --target-dir <DIR>
            Directory for build outputs
            [default: target]
            [env: DEPOT_TARGET_DIR]
  -h, --help
            Print help (see more with '--help')

Global Options:
  -v, --verbose...
            Print more output; repeat for more
            detail
  -q, --quiet
            Print only errors
      --color <WHEN>
            When to colour the output
            [default: auto]
            [possible values: auto, always, never]
            [env: DEPOT_COLOR]
  -C, --config <PATH>
            Read configuration from PATH instead
            of the workspace's depot.toml
            [env: DEPOT_CONFIG]

Examples:
  Build two packages in release mode
    depot build -j 8 --profile release app lib

  Build everything with TLS and write a report
    depot build --feature tls --report
"""

  rootShort50 = """Build and publish packages

Usage: depot [options] <command>

Commands:
  build, b
            Build packages in the workspace
  remote, remotes
            Manage the remotes packages are
            published to

Options:
  -v, --verbose...
            Print more output; repeat for more
            detail
  -q, --quiet
            Print only errors
      --color <WHEN>
            When to colour the output
            [default: auto]
            [possible values: auto, always, never]
            [env: DEPOT_COLOR]
  -C, --config <PATH>
            Read configuration from PATH instead
            of the workspace's depot.toml
            [env: DEPOT_CONFIG]
  -h, --help
            Print help

Run 'depot <command> --help' for more on a command.
"""

  remoteShort80 = """Manage the remotes packages are published to

Usage: depot remote [options] <command>

Aliases: remotes

Commands:
  add         Add a remote
  remove, rm  Remove a remote
  list, ls    List the remotes

Options:
  -h, --help  Print help

Global Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's
                       depot.toml [env: DEPOT_CONFIG]

Run 'depot remote <command> --help' for more on a command.
"""

  remoteAddShort80 = """Add a remote

Usage: depot remote add [options] <name> <url>

Arguments:
  <name>
  <url>

Options:
      --mirror  Mirror every package to this remote
  -h, --help    Print help

Global Options:
  -v, --verbose...     Print more output; repeat for more detail
  -q, --quiet          Print only errors
      --color <WHEN>   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  -C, --config <PATH>  Read configuration from PATH instead of the workspace's
                       depot.toml [env: DEPOT_CONFIG]
"""

  remoteAddShort50 = """Add a remote

Usage: depot remote add [options] <name> <url>

Arguments:
  <name>
  <url>

Options:
      --mirror
            Mirror every package to this remote
  -h, --help
            Print help

Global Options:
  -v, --verbose...
            Print more output; repeat for more
            detail
  -q, --quiet
            Print only errors
      --color <WHEN>
            When to colour the output
            [default: auto]
            [possible values: auto, always, never]
            [env: DEPOT_COLOR]
  -C, --config <PATH>
            Read configuration from PATH instead
            of the workspace's depot.toml
            [env: DEPOT_CONFIG]
"""

  phRoot = """Notes and long help

Usage: ph [options] <command>

Commands:
  run  Run a thing

Options:
  -l, --level...  Level
  -h, --help      Print help

Output:
  Where results go
  --out <string>  Output file [default: ""]

Run 'ph <command> --help' for more on a command.
"""

  phRun = """Run a thing

Usage: ph run [options] <shade>

Arguments:
  <shade>  Shade [possible values: light, dark]

Options:
      --name <string>  Name [required]
      --sep <string>   Separator [default: "a b"]
      --tag <string>   Tag [default: x]
      --fast           Go fast
  -h, --help           Print help (see more with '--help')

Output:
  Where results go
  --out <string>      Output file [default: ""]
  --fmt <light|dark>  Format [default: dark]

Global Options:
  -l, --level...  Level
"""

  phRunLong = """Run a thing

First paragraph of the long help.

Second paragraph.

Usage: ph run [options] <shade>

Arguments:
  <shade>  Shade [possible values: light, dark]

Options:
      --name <string>  Name [required]
                       More about the name.
      --sep <string>   Separator [default: "a b"]
      --tag <string>   Tag [default: x]
      --fast           Go fast
  -h, --help           Print help

Output:
  Where results go
  --out <string>      Output file [default: ""]
  --fmt <light|dark>  Format [default: dark]

Global Options:
  -l, --level...  Level
"""
  loLong = """Usage: lo [options]

Options:
  -d, --depth <int>  Depth
                     How deep to go.
      --help         Print help
"""

  wd80 = """Usage: wd [options]

Options:
      --anExtremelyLongFlagNameThatIsWide <SOMETHING>
                       Averyveryverylongwordwithoutanyspacesthatisnotbroken and
                       more
  -h, --host <string>  A flag of its own spelt -h
      --help           Print help
"""

  wd30 = """Usage: wd [options]

Options:
      --anExtremelyLongFlagNameThatIsWide <SOMETHING>
            Averyveryverylongwordwithoutanyspacesthatisnotbroken
            and more
  -h, --host <string>
            A flag of its own
            spelt -h
      --help
            Print help
"""

func width(w: int): CliHelpLayout =
  ## The default layout at another width.
  result = cliDefaultHelpLayout
  result.width = w

proc helpOf(argv: openArray[string];
            options = CliOptions()): ref CliHelpRequest =
  try:
    discard Depot.load(@argv, options)
  except CliHelpRequest as e:
    return e

suite "test_cs_m5b_help_matches_design":

  test "the default pages at 80 columns":
    check Depot.helpText() == rootShort80
    check Depot.helpText(["build"]) == buildShort80
    check Depot.helpText(["build"], long = true) == buildLong80
    check Depot.helpText(["b"], long = true) == buildLong80
    check cliHelpText(Depot.cliGrammar, 0, "depot") == rootShort80
    check Depot.helpText(layout = width(80)) == rootShort80
    check Depot.helpText(layout = width(0)) == rootShort80

  test "the help load raises: -h is the short page, --help the long one":
    let root = helpOf(["-h"])
    check root.text == rootShort80 and not root.long and not root.json
    check helpOf(["--help"]).text == rootShort80
    let short = helpOf(["build", "-h"])
    check short.commandPath == @["build"]
    check short.text == buildShort80 and not short.long
    let long = helpOf(["b", "--help"])
    check long.text == buildLong80 and long.long
    check helpOf(["remote", "-h"]).text == remoteShort80
    check helpOf(["remotes", "add", "--help"]).text == remoteAddShort80

  test "160 columns: the page is capped at 100":
    check Depot.helpText(layout = width(160)) == rootShort160
    check Depot.helpText(["build"], layout = width(160)) == buildShort160
    check Depot.helpText(["build"], layout = width(160), long = true) ==
      buildLong160
    check Depot.helpText(["build"], layout = width(100), long = true) ==
      buildLong160
    check helpOf(["build", "--help"],
      CliOptions(helpLayout: width(160))).text == buildLong160
    for golden in [rootShort160, buildShort160, buildLong160]:
      for line in golden.splitLines():
        check line.len <= 100

  test "50 columns: the next-line layout":
    check Depot.helpText(["build"], layout = width(50)) == buildShort50
    check Depot.helpText(layout = width(50)) == rootShort50
    check Depot.helpText(["remote", "add"], layout = width(50)) ==
      remoteAddShort50
    # Usage and example lines are never broken.
    check "\nUsage: depot build [options] [<packages>...]\n" in buildShort50
    check "\n    depot build -j 8 --profile release app lib\n" in buildShort50

  test "the short and the long page differ only where --help shows more":
    # The long page is the short one with the command's longHelp after its
    # help line and the help row's plain wording.
    let longText = Depot.helpText(["build"], long = true)
    let afterSummary = longText.split("\n\nUsage:", 1)[1]
    check ("Build packages in the workspace\n\nUsage:" & afterSummary).replace(
      "  -h, --help                     Print help\n",
      "  -h, --help                     Print help (see more with '--help')\n") ==
      buildShort80
    # Nothing more to see: both pages say ``Print help``.
    check Depot.helpText(["remote"], long = true) == remoteShort80
    check Depot.helpText(long = true) == rootShort80

  test "the version row when the program has a version text":
    let opts = CliOptions(versionText: "depot 1.0")
    check helpOf(["-h"], opts).text == rootShort80.replace(
      "  -h, --help           Print help\n",
      "  -h, --help           Print help\n" &
      "      --version        Print version\n")
    var worded = cliDefaultHelpLayout
    worded.versionFlag = "Show the version"
    check "      --version        Show the version\n" in
      helpOf(["-h"], CliOptions(versionText: "1", helpLayout: worded)).text
    # Without a version text, and in the classic layout, no row.
    check "--version" notin helpOf(["-h"]).text
    check "--version" notin helpOf(["-h"], CliOptions(versionText: "1",
      helpLayout: cliClassicHelpLayout)).text

  test "notes, groups and parameters' long help":
    check Ph.helpText() == phRoot
    check Ph.helpText(["run"]) == phRun
    check Ph.helpText(["run"], long = true) == phRunLong

  test "parsing longHelpOnly: --help is the long page":
    try:
      discard Lo.load(@["--help"])
      check false
    except CliHelpRequest as e:
      check e.long
      check e.text == loLong
    try:
      discard Lo.load(@["-h"])
      check false
    except CliUsageError as e:
      check e.kind == cekUnknownFlag

  test "a wide entry, a long word, hidden and internal items":
    # The entry wider than 32 characters puts its description on the next
    # line, under the column of the others; the word longer than the line
    # is kept whole; hidden and internal parameters are not listed.
    check Wd.helpText(layout = width(80)) == wd80
    check Wd.helpText(layout = width(30)) == wd30

  test "the options table alone":
    check Depot.optionsTable(["build"]) ==
      buildShort80.split("\nOptions:\n")[1].split("\nGlobal Options:")[0]
    check Ph.optionsTable(["run"], group = "Output") ==
      "  --out <string>      Output file [default: \"\"]\n" &
      "  --fmt <light|dark>  Format [default: dark]\n"

  test "examples and the command's long help in the JSON":
    let j = parseJson(Depot.helpJson(["build"]))["command"]
    check j["longHelp"].getStr.startsWith("Builds the named packages")
    check j["examples"] == %*[
      {"command": "depot build -j 8 --profile release app lib",
       "help": "Build two packages in release mode"},
      {"command": "depot build --feature tls --report",
       "help": "Build everything with TLS and write a report"}]
    let root = parseJson(Depot.helpJson())["command"]
    check root["examples"].len == 0
    check root["longHelp"].getStr == ""

  test "the model carries examples and longHelp":
    for cmd in Depot.cliModel.commands:
      if cmd.path == @["build"]:
        check cmd.examples.len == 2
        check cmd.examples[1] == CliExample(
          command: "depot build --feature tls --report",
          help: "Build everything with TLS and write a report")
        check cmd.longHelp.endsWith("is not rebuilt.")
      else:
        check cmd.examples.len == 0
        check cmd.longHelp == ""

  test "longHelp in a command's head, examples at the root":
    const m = plainCliModel:
      example "tool --check", help = "Check " & "everything"
      subcmd "build", longHelp = "Builds " & "it.":
        discard
    check m.root.examples == @[CliExample(command: "tool --check",
      help: "Check everything")]
    check m.commands[0].longHelp == "Builds it."
    check m.commands[0].examples.len == 0

  test "negative control: the classic layout does not give these pages":
    let pages = [
      (rootShort80, Depot.helpText(layout = cliClassicHelpLayout)),
      (buildShort80, Depot.helpText(["build"], layout = cliClassicHelpLayout)),
      (buildLong80, Depot.helpText(["build"], layout = cliClassicHelpLayout,
        long = true)),
      (buildShort80, Depot.helpText(["build"],
        layout = CliHelpLayout(width: 80, canonicalFirst: true,
          helpFlag: "Print help"))),
      (remoteShort80, Depot.helpText(["remote"], layout = CliHelpLayout())),
      (buildLong80, helpOf(["build", "--help"],
        CliOptions(helpLayout: cliClassicHelpLayout)).text)]
    for (golden, classic) in pages:
      check classic != golden
      check classic.startsWith("Usage: depot")
    check cliClassicHelpLayout == CliHelpLayout()
    check cliClassicHelpLayout.style == chsClassic
    check cliDefaultHelpLayout.style == chsStandard
