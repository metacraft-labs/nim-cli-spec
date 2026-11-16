## The ``kit`` description the tiered, grouped command help is pinned on
## (``tests/test_tiered_grouped_subcommand_help.nim``): subcommands in
## command groups and outside them, ``primary`` and ``secondary`` ones at
## the root and in a nested namespace (with a group of its own), a
## parameter group beside the command groups, a hidden ``secondary``
## subcommand (counted nowhere) and an ``internal`` namespace (counted only
## in its own help), under ``parsing helpWord`` so ``kit help --all`` asks
## for every tier.

import clispec

type
  When* = enum auto, always, never

cliProgram(Kit, "kit", exported = true):
  help "Develop, build and ship projects"
  convention cli = kebabCase
  parsing helpWord
  boolFlag verbose is bool, short = 'v', help = "Print more output"
  group "Output", help = "How results are shown":
    flag color is When, default = auto, help = "When to colour the output"
  subcmd "init", help = "Create a new project":
    pos dir is string, required = false, help = "Where to create it"
  group "Build Commands", help = "Turn sources into artifacts":
    subcmd "build", help = "Build the project", aliases = ["b"]:
      flag jobs is int, short = 'j', default = 4,
        help = "Number of parallel jobs"
    subcmd "test", help = "Run the tests":
      discard
    subcmd "graph", help = "Print the build graph", tier = secondary:
      discard
  group "Workspace Commands":
    subcmd "sync", help = "Fetch and fast-forward every repository":
      discard
    subcmd "repo", help = "Manage the repositories", tier = primary:
      subcmd "add", help = "Add a repository":
        pos url is string, help = "The repository's URL"
      subcmd "list", help = "List the repositories", aliases = ["ls"]:
        discard
      group "Maintenance", help = "Rarely needed by hand":
        subcmd "gc", help = "Collect unreachable objects", tier = secondary:
          discard
        subcmd "fsck", help = "Verify the object store", tier = secondary:
          discard
    subcmd "lock", help = "Refresh the lock files", tier = secondary:
      discard
  subcmd "doctor", help = "Diagnose the environment", tier = secondary:
    discard
  subcmd "debug-dump", visibility = hidden, tier = secondary:
    discard
  subcmd "internal", help = "Plumbing for other tools",
      visibility = internal:
    subcmd "cache-stats", help = "Print cache statistics":
      discard
    subcmd "cache-trim", help = "Trim the caches", tier = secondary:
      discard
