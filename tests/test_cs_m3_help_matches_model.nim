## test_cs_m3_help_matches_model: the help of every command lists exactly
## the parameters and subcommands its model says it should, with their help
## text, in both the human-readable and the machine-readable form.
##
## The expected sets are derived here from the model the description was
## parsed into (``Hx.cliModel``), by the listing rules the library documents:
## a command's help lists the parameters it accepts and those of its
## ``call:``; ``hidden`` items never; ``internal`` items only in the help of
## the command that declares or holds them, and never in the root's (primary)
## help. The derivation reads the model's own fields (``declaredIn``,
## ``visibility``, ``anonymous``), not the grammar the renderer uses, and the
## comparison runs both ways: nothing expected is missing and nothing else is
## listed. Two goldens fix the human-readable layout and the
## machine-readable form. Nothing is mocked.

import std/[json, sets, strutils, unittest]

import clispec

type
  Shade = enum
    light, dark

proc completeRemoteUrls(prefix: string): seq[string] =
  ## A completer: the description names it, the help JSON reports it.
  @[prefix]

cliProgram(Hx, "hx"):
  help "A help fixture"
  boolFlag verbose is bool, short = 'v', negatable = true,
    help = "Talk more"
  flag trace is string, visibility = internal, help = "Trace to a file"
  flag token is string, visibility = hidden
  group "Output", help = "Where results go":
    flag report is string, optionalValue = "report.json",
      help = "Write a report", env = ["HX_REPORT"]
  subcmd "build", help = "Build a project", aliases = ["b"]:
    flag jobs is int, short = 'j', default = 4, help = "Parallel jobs"
    flag shade is Shade, default = dark, help = "Theme"
    flag tags is seq[string], separator = ",", help = "Tags"
    flag graph is string, visibility = internal, help = "Dump the graph"
    flag key is string, visibility = hidden, help = "Never listed"
    flag libs is seq[string], alias = "-l", format = concat,
      help = "Libraries"
    pos target is string, help = "What to build"
    pos more is seq[string], repeated = true, required = false,
      help = "More targets"
  subcmd "internal", visibility = internal, help = "Debugging tools":
    subcmd "dump", help = "Dump state":
      pos what is string, default = "all", help = "What to dump"
    subcmd "probe", visibility = internal, help = "Probe a thing":
      boolFlag deep is bool
  subcmd "ghost", visibility = hidden, help = "Never listed":
    pos x is string
  subcmd "remote", help = "Remotes":
    flag url is string, required = true, help = "Remote URL",
      complete = completeRemoteUrls
    flag depth is int, visibility = internal, help = "Fetch depth"
    subcmd "add", help = "Add a remote":
      pos name is string
    subcmd "prune", visibility = internal, help = "Prune remotes":
      boolFlag all is bool
    call(help = "List remotes"):
      boolFlag long is bool, short = 'l', help = "Long listing"

const model = Hx.cliModel

proc namedCommands(): seq[PlainCliCommand] =
  ## The root and every subcmd (not the call: scopes, which have no help of
  ## their own).
  result.add(model.root)
  for cmd in model.commands:
    if not cmd.anonymous:
      result.add(cmd)

proc callOf(cmd: PlainCliCommand): seq[PlainCliCommand] =
  for other in model.commands:
    if other.anonymous and other.path == cmd.path and
        other.depth == cmd.depth + 1:
      result.add(other)

proc expectedParams(cmd: PlainCliCommand): seq[PlainCliParam] =
  ## The listing rules, applied to the model.
  var candidates = cmd.params
  for call in callOf(cmd):
    for p in call.params:
      var known = false
      for c in candidates:
        if c.name == p.name:
          known = true
      if not known:
        candidates.add(p)
  let isRoot = cmd.depth == 0
  for p in candidates:
    case p.visibility
    of cvShown:
      result.add(p)
    of cvHidden:
      discard
    of cvInternal:
      if not isRoot and p.declaredIn == cmd.path:
        result.add(p)

proc expectedCommands(cmd: PlainCliCommand): seq[PlainCliCommand] =
  for other in model.commands:
    if not other.anonymous and other.depth == cmd.depth + 1 and
        other.path.len == cmd.path.len + 1 and
        other.path[0 ..< ^1] == cmd.path:
      case other.visibility
      of cvShown: result.add(other)
      of cvHidden: discard
      of cvInternal:
        if cmd.depth > 0:
          result.add(other)

proc display(p: PlainCliParam): string =
  if p.kind == cpkFlag: "--" & p.name else: "<" & p.name & ">"

suite "test_cs_m3_help_matches_model":

  test "every command's help lists exactly its visible parameters":
    for cmd in namedCommands():
      let label = if cmd.path.len == 0: "root" else: cmd.path.join(" ")
      checkpoint(label)
      let text = Hx.helpText(cmd.path)
      let doc = parseJson(Hx.helpJson(cmd.path))
      let expected = expectedParams(cmd)
      var expectedNames = initHashSet[string]()
      for p in expected:
        expectedNames.incl(p.name)
      # Machine-readable: the same set, both ways.
      var listed = initHashSet[string]()
      for p in doc["command"]["parameters"]:
        listed.incl(p["name"].getStr)
      check listed == expectedNames
      # Human-readable: every expected parameter with its help text; no
      # other parameter of the whole model appears.
      for p in expected:
        check display(p) in text or ("--[no-]" & p.name) in text
        if p.help.len > 0:
          check p.help in text
      var everyName = initHashSet[string]()
      for other in namedCommands():
        for p in other.params:
          everyName.incl(p.name)
      for call in model.commands:
        for p in call.params:
          everyName.incl(p.name)
      for name in everyName:
        if name notin expectedNames:
          check ("--" & name & " ") notin text
          check ("--" & name & "\n") notin text
          check ("--" & name & "=") notin text
          check ("--" & name & "[") notin text
          check ("<" & name & ">") notin text

  test "every command's help lists exactly its visible subcommands":
    for cmd in namedCommands():
      checkpoint(if cmd.path.len == 0: "root" else: cmd.path.join(" "))
      let doc = parseJson(Hx.helpJson(cmd.path))
      var listed = initHashSet[string]()
      for c in doc["command"]["commands"]:
        listed.incl(c["name"].getStr)
      var expected = initHashSet[string]()
      for c in expectedCommands(cmd):
        expected.incl(c.name)
      check listed == expected
      let text = Hx.helpText(cmd.path)
      for c in expectedCommands(cmd):
        check ("  " & c.name) in text
        check c.help in text

  test "internal items appear only in their namespace's help":
    check "--trace" notin Hx.helpText()
    check "internal" notin Hx.helpText()
    check "--graph" in Hx.helpText(["build"])
    check "--depth" in Hx.helpText(["remote"])
    check "--depth" notin Hx.helpText(["remote", "add"])
    check "dump" in Hx.helpText(["internal"])
    check "probe" in Hx.helpText(["internal"])
    check "prune" in Hx.helpText(["remote"])
    for cmd in namedCommands():
      let text = Hx.helpText(cmd.path)
      check "--token" notin text
      check "--key" notin text
      if cmd.path != @["ghost"]:
        check "ghost" notin text

  test "human-readable layout (golden)":
    check Hx.helpText() == """Usage: hx [options] <command>

A help fixture

Commands:
  build, b  Build a project
  remote    Remotes

Options:
  -v, --[no-]verbose  Talk more

Output:
  Where results go
  --report[=<string>]  Write a report [env: HX_REPORT]
"""
    check Hx.helpText(["build"]) == """Usage: hx build [options] <target> [<more>...]

Build a project

Aliases: b

Arguments:
  <target>     What to build
  [<more>...]  More targets

Options:
  -v, --[no-]verbose     Talk more
  -j, --jobs <int>       Parallel jobs [default: 4]
  --shade <light|dark>   Theme [default: dark]
  --tags <string>[,...]  Tags
  --graph <string>       Dump the graph
  -l<string>..., --libs=<string>...
                         Libraries

Output:
  Where results go
  --report[=<string>]  Write a report [env: HX_REPORT]
"""

  test "machine-readable form (golden)":
    check Hx.helpJson(["remote"]) == """{
  "schema": "clispec-help/1",
  "program": "hx",
  "command": {
    "name": "remote",
    "path": [
      "remote"
    ],
    "aliases": [],
    "help": "Remotes",
    "visibility": "shown",
    "usage": "hx remote [options] [<command>]",
    "parameters": [
      {
        "name": "verbose",
        "kind": "flag",
        "spellings": [
          "--verbose",
          "-v"
        ],
        "negation": "--no-verbose",
        "value": "none",
        "format": "separate",
        "valueName": "bool",
        "choices": [],
        "list": false,
        "separator": null,
        "counted": false,
        "required": false,
        "default": null,
        "env": [],
        "help": "Talk more",
        "group": null,
        "visibility": "shown",
        "declaredIn": [],
        "dynamicCompletion": false,
        "completer": null,
        "configKeys": {
          "file": "verbose"
        }
      },
      {
        "name": "report",
        "kind": "flag",
        "spellings": [
          "--report"
        ],
        "negation": null,
        "value": "optional",
        "format": "separate",
        "valueName": "string",
        "choices": [],
        "list": false,
        "separator": null,
        "counted": false,
        "required": false,
        "default": null,
        "env": [
          "HX_REPORT"
        ],
        "help": "Write a report",
        "group": "Output",
        "visibility": "shown",
        "declaredIn": [],
        "dynamicCompletion": false,
        "completer": null,
        "configKeys": {
          "file": "report"
        }
      },
      {
        "name": "url",
        "kind": "flag",
        "spellings": [
          "--url"
        ],
        "negation": null,
        "value": "required",
        "format": "separate",
        "valueName": "string",
        "choices": [],
        "list": false,
        "separator": null,
        "counted": false,
        "required": true,
        "default": null,
        "env": [],
        "help": "Remote URL",
        "group": null,
        "visibility": "shown",
        "declaredIn": [
          "remote"
        ],
        "dynamicCompletion": true,
        "completer": "completeRemoteUrls",
        "configKeys": {
          "file": "remote.url"
        }
      },
      {
        "name": "depth",
        "kind": "flag",
        "spellings": [
          "--depth"
        ],
        "negation": null,
        "value": "required",
        "format": "separate",
        "valueName": "int",
        "choices": [],
        "list": false,
        "separator": null,
        "counted": false,
        "required": false,
        "default": null,
        "env": [],
        "help": "Fetch depth",
        "group": null,
        "visibility": "internal",
        "declaredIn": [
          "remote"
        ],
        "dynamicCompletion": false,
        "completer": null,
        "configKeys": {
          "file": "remote.depth"
        }
      },
      {
        "name": "long",
        "kind": "flag",
        "spellings": [
          "--long",
          "-l"
        ],
        "negation": null,
        "value": "none",
        "format": "separate",
        "valueName": "bool",
        "choices": [],
        "list": false,
        "separator": null,
        "counted": false,
        "required": false,
        "default": null,
        "env": [],
        "help": "Long listing",
        "group": null,
        "visibility": "shown",
        "declaredIn": [
          "remote"
        ],
        "dynamicCompletion": false,
        "completer": null,
        "configKeys": {
          "file": "remote.long"
        }
      }
    ],
    "commands": [
      {
        "name": "add",
        "path": [
          "remote",
          "add"
        ],
        "aliases": [],
        "help": "Add a remote",
        "visibility": "shown",
        "usage": "hx remote add [options] <name>",
        "parameters": [
          {
            "name": "verbose",
            "kind": "flag",
            "spellings": [
              "--verbose",
              "-v"
            ],
            "negation": "--no-verbose",
            "value": "none",
            "format": "separate",
            "valueName": "bool",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": false,
            "default": null,
            "env": [],
            "help": "Talk more",
            "group": null,
            "visibility": "shown",
            "declaredIn": [],
            "dynamicCompletion": false,
            "completer": null,
            "configKeys": {
              "file": "verbose"
            }
          },
          {
            "name": "report",
            "kind": "flag",
            "spellings": [
              "--report"
            ],
            "negation": null,
            "value": "optional",
            "format": "separate",
            "valueName": "string",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": false,
            "default": null,
            "env": [
              "HX_REPORT"
            ],
            "help": "Write a report",
            "group": "Output",
            "visibility": "shown",
            "declaredIn": [],
            "dynamicCompletion": false,
            "completer": null,
            "configKeys": {
              "file": "report"
            }
          },
          {
            "name": "url",
            "kind": "flag",
            "spellings": [
              "--url"
            ],
            "negation": null,
            "value": "required",
            "format": "separate",
            "valueName": "string",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": true,
            "default": null,
            "env": [],
            "help": "Remote URL",
            "group": null,
            "visibility": "shown",
            "declaredIn": [
              "remote"
            ],
            "dynamicCompletion": true,
            "completer": "completeRemoteUrls",
            "configKeys": {
              "file": "remote.url"
            }
          },
          {
            "name": "name",
            "kind": "positional",
            "spellings": [],
            "negation": null,
            "value": "required",
            "format": "separate",
            "valueName": "string",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": true,
            "default": null,
            "env": [],
            "help": "",
            "group": null,
            "visibility": "shown",
            "position": 0,
            "declaredIn": [
              "remote",
              "add"
            ],
            "dynamicCompletion": false,
            "completer": null,
            "configKeys": {
              "file": "remote.add.name"
            }
          }
        ],
        "commands": []
      },
      {
        "name": "prune",
        "path": [
          "remote",
          "prune"
        ],
        "aliases": [],
        "help": "Prune remotes",
        "visibility": "internal",
        "usage": "hx remote prune [options]",
        "parameters": [
          {
            "name": "verbose",
            "kind": "flag",
            "spellings": [
              "--verbose",
              "-v"
            ],
            "negation": "--no-verbose",
            "value": "none",
            "format": "separate",
            "valueName": "bool",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": false,
            "default": null,
            "env": [],
            "help": "Talk more",
            "group": null,
            "visibility": "shown",
            "declaredIn": [],
            "dynamicCompletion": false,
            "completer": null,
            "configKeys": {
              "file": "verbose"
            }
          },
          {
            "name": "report",
            "kind": "flag",
            "spellings": [
              "--report"
            ],
            "negation": null,
            "value": "optional",
            "format": "separate",
            "valueName": "string",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": false,
            "default": null,
            "env": [
              "HX_REPORT"
            ],
            "help": "Write a report",
            "group": "Output",
            "visibility": "shown",
            "declaredIn": [],
            "dynamicCompletion": false,
            "completer": null,
            "configKeys": {
              "file": "report"
            }
          },
          {
            "name": "url",
            "kind": "flag",
            "spellings": [
              "--url"
            ],
            "negation": null,
            "value": "required",
            "format": "separate",
            "valueName": "string",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": true,
            "default": null,
            "env": [],
            "help": "Remote URL",
            "group": null,
            "visibility": "shown",
            "declaredIn": [
              "remote"
            ],
            "dynamicCompletion": true,
            "completer": "completeRemoteUrls",
            "configKeys": {
              "file": "remote.url"
            }
          },
          {
            "name": "all",
            "kind": "flag",
            "spellings": [
              "--all"
            ],
            "negation": null,
            "value": "none",
            "format": "separate",
            "valueName": "bool",
            "choices": [],
            "list": false,
            "separator": null,
            "counted": false,
            "required": false,
            "default": null,
            "env": [],
            "help": "",
            "group": null,
            "visibility": "shown",
            "declaredIn": [
              "remote",
              "prune"
            ],
            "dynamicCompletion": false,
            "completer": null,
            "configKeys": {
              "file": "remote.prune.all"
            }
          }
        ],
        "commands": []
      }
    ]
  },
  "conventions": {
    "cli": "declared",
    "file": "declared"
  }
}
"""
