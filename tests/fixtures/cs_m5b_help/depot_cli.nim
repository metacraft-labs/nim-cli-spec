## The ``depot`` description the help design is pinned on
## (``tests/test_cs_m5b_help_matches_design.nim``,
## ``tests/test_cs_m5b_no_color_and_not_a_terminal.nim``): subcommands,
## aliases, inherited flags, a counted flag, notes, a long description and
## examples. ``depot.nim`` is the program built from it.

import clispec

type
  When* = enum auto, always, never
  Profile* = enum debug, release
  Format* = enum table, json

cliProgram(Depot, "depot", exported = true):
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
