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
##
## Colour and errors: the styled root and ``build`` short pages at 80
## columns with their exact escape sequences (``color = always``); every
## golden page equals its styled form without the escape sequences; the
## error block (``cliErrorText``) of an unknown subcommand and a missing
## value, equal to the design's pages, of an unknown flag and of a value
## outside a closed set, plain and styled; the suggestion rules
## (Damerau–Levenshtein distance, the threshold at its edges, closest
## first, at most three, one per command) and that hidden items, internal
## parameters and an internal subcommand outside its holder are never
## suggested. The printers' choice of colour and width on a real terminal
## and through a pipe is ``test_cs_m5b_no_color_and_not_a_terminal``'s.

import std/[json, os, strutils, tempfiles, unittest]

import clispec

import ./fixtures/cs_m5b_help/depot_cli

type
  Shade = enum light, dark

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

cliProgram(Sg, "sg"):
  convention cli = kebabCase
  flag jobs is int, short = 'j', help = "Jobs"
  boolFlag color is bool, negatable = true, help = "Colour"
  flag secretKey is string, visibility = hidden, help = "Hidden"
  flag traceAll is bool, visibility = internal, help = "Internal"
  subcmd "push", help = "Push":
    discard
  subcmd "list", aliases = ["ls", "lst"], help = "List":
    flag mode is Shade, default = light, help = "Mode"
    pos shades is seq[Shade], repeated = true, required = false
  subcmd "secret", visibility = hidden, help = "Hidden":
    discard
  subcmd "debug", visibility = internal, help = "Internal":
    discard
  subcmd "remote", help = "Remotes":
    subcmd "prune", visibility = internal, help = "Internal, inside remote":
      discard

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

  # The styled pages: ESC stands for the escape character.
  rootShort80Styled = """Build and publish packages

ESC[1;92mUsage:ESC[0m ESC[1;96mdepotESC[0m ESC[36m[options]ESC[0m ESC[36m<command>ESC[0m

ESC[1;92mCommands:ESC[0m
  ESC[1;96mbuildESC[0m, ESC[1;96mbESC[0m         Build packages in the workspace
  ESC[1;96mremoteESC[0m, ESC[1;96mremotesESC[0m  Manage the remotes packages are published to

ESC[1;92mOptions:ESC[0m
  ESC[1;96m-vESC[0m, ESC[1;96m--verbose...ESC[0m     Print more output; repeat for more detail
  ESC[1;96m-qESC[0m, ESC[1;96m--quietESC[0m          Print only errors
      ESC[1;96m--colorESC[0m ESC[36m<WHEN>ESC[0m   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  ESC[1;96m-CESC[0m, ESC[1;96m--configESC[0m ESC[36m<PATH>ESC[0m  Read configuration from PATH instead of the workspace's
                       depot.toml [env: DEPOT_CONFIG]
  ESC[1;96m-hESC[0m, ESC[1;96m--helpESC[0m           Print help

Run 'ESC[1;96mdepotESC[0m ESC[36m<command>ESC[0m ESC[1;96m--helpESC[0m' for more on a command.
""".replace("ESC", "\e")

  buildShort80Styled = """Build packages in the workspace

ESC[1;92mUsage:ESC[0m ESC[1;96mdepotESC[0m ESC[1;96mbuildESC[0m ESC[36m[options]ESC[0m ESC[36m[<packages>...]ESC[0m

ESC[1;92mAliases:ESC[0m ESC[1;96mbESC[0m

ESC[1;92mArguments:ESC[0m
  ESC[36m[<packages>...]ESC[0m  Packages to build (default: every package)

ESC[1;92mOptions:ESC[0m
  ESC[1;96m-jESC[0m, ESC[1;96m--jobsESC[0m ESC[36m<N>ESC[0m                 Number of parallel jobs [default: 4]
                                 [env: DEPOT_JOBS]
      ESC[1;96m--profileESC[0m ESC[36m<debug|release>ESC[0m  Build profile [default: debug]
  ESC[1;96m-FESC[0m, ESC[1;96m--featureESC[0m ESC[36m<NAME>...ESC[0m        Enable a feature; may be given more than once
      ESC[1;96m--reportESC[0m[=ESC[36m<PATH>ESC[0m]          Write a build report (to build-report.json when
                                 no PATH is given)
      ESC[1;96m--target-dirESC[0m ESC[36m<DIR>ESC[0m         Directory for build outputs [default: target]
                                 [env: DEPOT_TARGET_DIR]
  ESC[1;96m-hESC[0m, ESC[1;96m--helpESC[0m                     Print help (see more with '--help')

ESC[1;92mGlobal Options:ESC[0m
  ESC[1;96m-vESC[0m, ESC[1;96m--verbose...ESC[0m     Print more output; repeat for more detail
  ESC[1;96m-qESC[0m, ESC[1;96m--quietESC[0m          Print only errors
      ESC[1;96m--colorESC[0m ESC[36m<WHEN>ESC[0m   When to colour the output [default: auto]
                       [possible values: auto, always, never] [env: DEPOT_COLOR]
  ESC[1;96m-CESC[0m, ESC[1;96m--configESC[0m ESC[36m<PATH>ESC[0m  Read configuration from PATH instead of the workspace's
                       depot.toml [env: DEPOT_CONFIG]

ESC[1;92mExamples:ESC[0m
  Build two packages in release mode
    ESC[1;96mdepot build -j 8 --profile release app libESC[0m

  Build everything with TLS and write a report
    ESC[1;96mdepot build --feature tls --reportESC[0m
""".replace("ESC", "\e")

  # The error blocks: an unknown subcommand and a missing value as the
  # design gives them, an unknown flag and a value outside a closed set.
  errBiuld = """error: unknown subcommand 'biuld' for 'depot'; expected one of: build, remote

  tip: a similar subcommand exists: 'build'

Usage: depot [options] <command>

For more information, try 'depot --help'.
"""

  errJobs = """error: flag '--jobs' of 'depot build' needs a value

Usage: depot build [options] [<packages>...]

For more information, try 'depot build --help'.
"""

  errJob = """error: unknown flag '--job' for 'depot build'

  tip: a similar flag exists: '--jobs'

Usage: depot build [options] [<packages>...]

For more information, try 'depot build --help'.
"""

  errProfile = """error: invalid value 'relase' for '--profile' of 'depot build'; expected one of: debug, release

  tip: a similar value exists: 'release'

Usage: depot build [options] [<packages>...]

For more information, try 'depot build --help'.
"""

  errBiuldStyled = """ESC[1;91merror:ESC[0m unknown subcommand 'ESC[33mbiuldESC[0m' for 'depot'; expected one of: build, remote

  ESC[1;92mtip:ESC[0m a similar subcommand exists: 'ESC[1;96mbuildESC[0m'

ESC[1;92mUsage:ESC[0m ESC[1;96mdepotESC[0m ESC[36m[options]ESC[0m ESC[36m<command>ESC[0m

For more information, try 'ESC[1;96mdepotESC[0m ESC[1;96m--helpESC[0m'.
""".replace("ESC", "\e")

  errProfileStyled = """ESC[1;91merror:ESC[0m invalid value 'ESC[33mrelaseESC[0m' for '--profile' of 'depot build'; expected one of: debug, release

  ESC[1;92mtip:ESC[0m a similar value exists: 'ESC[1;96mreleaseESC[0m'

ESC[1;92mUsage:ESC[0m ESC[1;96mdepotESC[0m ESC[1;96mbuildESC[0m ESC[36m[options]ESC[0m ESC[36m[<packages>...]ESC[0m

For more information, try 'ESC[1;96mdepotESC[0m ESC[1;96mbuildESC[0m ESC[1;96m--helpESC[0m'.
""".replace("ESC", "\e")

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

proc errorOf(argv: openArray[string];
             options = CliOptions()): ref CliUsageError =
  try:
    discard Depot.load(@argv, options)
  except CliUsageError as e:
    return e

proc sgError(argv: openArray[string]): ref CliUsageError =
  try:
    discard Sg.load(@argv)
  except CliUsageError as e:
    return e

proc sgSuggestions(argv: openArray[string]): seq[string] =
  let e = sgError(argv)
  doAssert e != nil, "no usage error for " & $argv
  e.suggestions

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

  test "colour: the styled pages at 80 columns (color = always)":
    let opts = CliOptions(color: ccmAlways)
    let root = helpOf(["-h"], opts)
    check root.color == ccmAlways
    check root.render(80, true) == rootShort80Styled
    check helpOf(["build", "-h"], opts).render(80, true) == buildShort80Styled
    check Depot.helpText(styled = true) == rootShort80Styled
    check Depot.helpText(["build"], styled = true) == buildShort80Styled
    # The text the request carries stays plain and 80 columns wide.
    check root.text == rootShort80
    check cliStripStyles(rootShort80Styled) == rootShort80
    check cliStripStyles(buildShort80Styled) == buildShort80
    # Printed to a file (not a terminal): styled only when forced.
    let (f, path) = createTempFile("clispec_help_", ".txt")
    let saved = getEnv("COLUMNS")
    putEnv("COLUMNS", "80")
    try:
      cliPrintHelp(root, f)
      cliPrintHelp(helpOf(["-h"]), f)
      cliPrintHelp(helpOf(["-h"], CliOptions(color: ccmNever)), f)
      f.close()
      check readFile(path) == rootShort80Styled & rootShort80 & rootShort80
    finally:
      if saved.len > 0: putEnv("COLUMNS", saved) else: delEnv("COLUMNS")
      removeFile(path)

  test "every golden equals its styled page without escape sequences":
    let pages = [
      (rootShort80, Depot.helpText(styled = true)),
      (buildShort80, Depot.helpText(["build"], styled = true)),
      (buildLong80, Depot.helpText(["build"], long = true, styled = true)),
      (rootShort160, Depot.helpText(layout = width(160), styled = true)),
      (buildShort160, Depot.helpText(["build"], layout = width(160),
        styled = true)),
      (buildLong160, Depot.helpText(["build"], layout = width(160),
        long = true, styled = true)),
      (buildShort50, Depot.helpText(["build"], layout = width(50),
        styled = true)),
      (rootShort50, Depot.helpText(layout = width(50), styled = true)),
      (remoteShort80, Depot.helpText(["remote"], styled = true)),
      (remoteAddShort80, Depot.helpText(["remote", "add"], styled = true)),
      (remoteAddShort50, Depot.helpText(["remote", "add"],
        layout = width(50), styled = true)),
      (phRoot, Ph.helpText(styled = true)),
      (phRun, Ph.helpText(["run"], styled = true)),
      (phRunLong, Ph.helpText(["run"], long = true, styled = true)),
      (wd80, Wd.helpText(layout = width(80), styled = true)),
      (wd30, Wd.helpText(layout = width(30), styled = true)),
      (rootShort80, rootShort80Styled),
      (buildShort80, buildShort80Styled)]
    for (golden, styled) in pages:
      check "\e[" in styled
      check cliStripStyles(styled) == golden
      # Widths are those of the visible text.
      let plainLines = cliStripStyles(styled).splitLines()
      let styledLines = styled.splitLines()
      check plainLines.len == styledLines.len
      for k in 0 ..< min(plainLines.len, styledLines.len):
        check cliVisibleLen(styledLines[k]) == plainLines[k].len
    # The options table alone, too.
    check cliStripStyles(Depot.optionsTable(["build"], styled = true)) ==
      Depot.optionsTable(["build"])
    # The classic layout, styled when asked: the same text with escapes.
    let classic = Depot.helpText(["build"], layout = cliClassicHelpLayout)
    let classicStyled = Depot.helpText(["build"],
      layout = cliClassicHelpLayout, styled = true)
    check "\e[" in classicStyled
    check cliStripStyles(classicStyled) == classic

  test "a printer re-renders at its width only a layout that leaves it open":
    # The default layout leaves the width to the printer.
    check cliDefaultHelpLayout.width == 0
    let build = helpOf(["build", "-h"])
    check build.render(160, false) == buildShort160
    check build.render(50, false) == buildShort50
    check build.render(80, false) == buildShort80
    check build.render(50, true) == Depot.helpText(["build"],
      layout = width(50), styled = true)
    # A standard layout with a width keeps it.
    let fixed = helpOf(["build", "-h"], CliOptions(helpLayout: width(50)))
    check fixed.text == buildShort50
    check fixed.render(100, false) == buildShort50
    # The classic layout keeps its text, and is styled only when the
    # program asks for colour.
    let classic = Depot.helpText(["build"], layout = cliClassicHelpLayout)
    let auto = helpOf(["build", "-h"],
      CliOptions(helpLayout: cliClassicHelpLayout))
    check auto.text == classic
    check auto.render(50, true) == classic
    let forced = helpOf(["build", "-h"],
      CliOptions(helpLayout: cliClassicHelpLayout, color: ccmAlways))
    check forced.render(50, true) == Depot.helpText(["build"],
      layout = cliClassicHelpLayout, styled = true)
    check forced.render(50, false) == classic
    # JSON help and the version text are printed as they are.
    check helpOf(["--help=json"]).render.isNil
    check helpOf(["--version"], CliOptions(versionText: "depot 1.0")).render.isNil

  test "the error block: the design's pages, a flag and a value":
    let biuld = errorOf(["biuld"])
    check biuld.suggestions == @["build"]
    check biuld.msg ==
      "unknown subcommand 'biuld' for 'depot'; expected one of: build, remote"
    check biuld.usage == "depot [options] <command>"
    check biuld.helpCommand == "depot --help"
    check cliErrorText(biuld) == errBiuld
    let jobs = errorOf(["build", "--jobs"])
    check jobs.suggestions.len == 0
    check cliErrorText(jobs) == errJobs
    let job = errorOf(["build", "--job", "3"])
    check job.kind == cekUnknownFlag and job.suggestions == @["--jobs"]
    check cliErrorText(job) == errJob
    let profile = errorOf(["build", "--profile", "relase"])
    check profile.kind == cekInvalidValue
    check profile.suggestions == @["release"]
    check cliErrorText(profile) == errProfile
    # Styled: the exact escape sequences, and nothing else differs.
    check cliErrorText(biuld, styled = true) == errBiuldStyled
    check cliErrorText(profile, styled = true) == errProfileStyled
    for e in [biuld, jobs, job, profile]:
      check cliStripStyles(cliErrorText(e, styled = true)) == cliErrorText(e)
    # Several suggestions are listed quoted and comma-separated.
    check cliTipText(cekUnknownFlag, ["--jobs", "--joke"]) ==
      "some similar flags exist: '--jobs', '--joke'"
    check cliTipText(cekUnknownSubcommand, ["push"]) ==
      "a similar subcommand exists: 'push'"
    check cliTipText(cekInvalidValue, ["a", "b", "c"]) ==
      "some similar values exist: 'a', 'b', 'c'"
    # The usage line is never broken, whatever its length.
    let wide = errorOf(["remote", "add", "--mirror=x", "a", "b"])
    check "\nUsage: depot remote add [options] <name> <url>\n" in
      cliErrorText(wide)
    # The error carries the program's colour choice; help off: no hint.
    check errorOf(["biuld"], CliOptions(color: ccmAlways)).color == ccmAlways
    let off = errorOf(["biuld"], CliOptions(disableHelpFlag: true))
    check off.helpCommand == ""
    check "For more information" notin cliErrorText(off)
    # The wording of every kind is unchanged: msg is the kind's wording.
    check cliErrorText(job).startsWith("error: " & job.msg & "\n")

  test "Damerau-Levenshtein distance and the threshold":
    check cliEditDistance("biuld", "build") == 1   # a transposition
    check cliEditDistance("ab", "ba") == 1
    check cliEditDistance("ca", "abc") == 2        # not restricted
    check cliEditDistance("kitten", "sitting") == 3
    check cliEditDistance("", "abc") == 3
    check cliEditDistance("same", "same") == 0
    check cliEditDistance("pxxh", "push") == 2
    check cliEditDistance("pxxsh", "push") == 2
    # Distance at most 2 and less than half the typed word's length.
    check not cliIsSimilar("abcd", 2)    # 2 is not < 4 / 2
    check cliIsSimilar("abcde", 2)       # 2 < 5 / 2
    check cliIsSimilar("abc", 1)
    check not cliIsSimilar("ab", 1)
    check not cliIsSimilar("abcdefgh", 3)
    # Through the parser: length 4 at distance 2 is refused, length 5 not.
    check sgSuggestions(["pxxh"]).len == 0
    check sgSuggestions(["pxxsh"]) == @["push"]
    check sgSuggestions(["psuh"]) == @["push"]
    # Closest first, declaration order among equals, at most three.
    check cliEditDistance("deploy", "dexpoy") == 2
    for c in ["deplox", "deploys", "eploy", "deplyo"]:
      check cliEditDistance("deploy", c) == 1
    check cliSuggest("deploy", [("dexpoy", "dexpoy", "1"),
      ("deplox", "deplox", "2"), ("deploys", "deploys", "3"),
      ("eploy", "eploy", "4"), ("deplyo", "deplyo", "5")]) ==
      @["deplox", "deploys", "eploy"]
    check cliSuggest("deploy", [("dexpoy", "dexpoy", "1"),
      ("deplox", "deplox", "2")]) == @["deplox", "dexpoy"]
    # A command that matches by its name and its aliases is offered once,
    # by its name.
    check cliEditDistance("lsit", "list") == 1
    check cliEditDistance("lsit", "lst") == 1
    check sgSuggestions(["lsit"]) == @["list"]
    check sgSuggestions(["lts"]) == @["list"]
    # Flags: spellings as written, a negation, compared without dashes.
    check sgSuggestions(["--jbos", "1"]) == @["--jobs"]
    check sgSuggestions(["--no-colr"]) == @["--no-color"]
    check sgSuggestions(["--colr"]) == @["--color"]
    check sgSuggestions(["--hepl"]) == @["--help"]
    check sgSuggestions(["-x"]).len == 0
    # Values of a closed set, a list's element included.
    check sgSuggestions(["list", "--mode", "lihgt"]) == @["light"]
    check sgSuggestions(["list", "drak"]) == @["dark"]
    check sgSuggestions(["list", "--mode", "purple"]).len == 0

  test "hidden items and internal parameters are never suggested":
    # Each is accepted when spelt right.
    discard Sg.load(@["--secret-key", "k", "--trace-all", "secret"])
    discard Sg.load(@["debug"])
    discard Sg.load(@["remote", "prune"])
    check cliEditDistance("secrt", "secret") == 1
    check sgSuggestions(["secrt"]).len == 0
    check sgSuggestions(["--secret-kye", "k"]).len == 0
    check sgSuggestions(["--trace-al"]).len == 0
    # An internal subcommand: not at the root, which is the primary help;
    # inside the command that holds it, yes.
    check sgSuggestions(["debgu"]).len == 0
    check sgSuggestions(["remote", "prnue"]) == @["prune"]
    # The help words of a program are not suggested where they are off.
    let off = try:
        discard Sg.load(@["--hepl"], CliOptions(disableHelpFlag: true))
        @["(accepted)"]
      except CliUsageError as e:
        e.suggestions
    check off.len == 0

  test "unknown subcommands of the help procedures carry suggestions":
    try:
      discard Depot.helpText(["biuld"])
      check false
    except CliUsageError as e:
      check e.suggestions == @["build"]
      check cliErrorText(e) == errBiuld

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
