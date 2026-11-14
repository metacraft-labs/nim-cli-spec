## test_cs_m5_internal_parameters_work_unlisted: an ``internal`` parameter,
## wherever it is declared, is listed in no help screen and offered by no
## completion, is listed in the machine-readable help marked ``internal``,
## and works: given on the command line it fills its configuration field.
##
## The fixture declares internal parameters at the root, under a
## subcommand, inside a ``call:`` and under an internal subcommand (whose
## own help is otherwise complete), next to a shown and a hidden parameter
## at each place. For every command reachable by its words the test renders
## the human-readable help and requires no internal parameter's spelling in
## it, asks the completion engine for the flags of that command and requires
## no internal spelling among them, and reads the machine-readable help:
## every internal parameter the command accepts is listed there with
## ``"visibility": "internal"``, and no hidden one is. Then each internal
## parameter is given on the command line and read back from the typed
## configuration object. The expected sets are the fixture's own
## declarations, written out here; the shown parameters are checked as
## present too, so an empty help or an empty completion cannot pass.
## Nothing is mocked.

import std/[json, sets, strutils, unittest]

import clispec

cliProgram(Ip, "ip"):
  help "A visibility fixture"
  boolFlag verbose is bool, help = "Talk more"
  flag trace is string, visibility = internal, help = "Trace to a file"
  flag token is string, visibility = hidden, help = "Never listed"
  subcmd "build", help = "Build a project":
    flag jobs is int, help = "Parallel jobs"
    flag graph is string, visibility = internal, help = "Dump the graph"
    flag secret is string, visibility = hidden
    pos target is string, required = false
  subcmd "remote", help = "Remotes":
    subcmd "add", help = "Add a remote":
      pos name is string
    call(help = "List remotes"):
      boolFlag long is bool, help = "Long listing"
      flag probe is int, visibility = internal, help = "Probe depth"
  subcmd "internal", visibility = internal, help = "Debugging tools":
    flag dumpTo is string, help = "Where dumps go"
    flag raw is bool, visibility = internal, help = "Raw dumps"
    subcmd "dump", help = "Dump state":
      pos what is string, default = "all"

const
  internalSpellings = ["--trace", "--graph", "--probe", "--raw"]
  hiddenNames = ["token", "secret"]

type Place = object
  path: seq[string]
  shown: seq[string]
    ## Flags help and completion must list (inherited ones included).
  internal: seq[string]
    ## The internal parameters the command accepts (their names).

const places = [
  Place(path: @[], shown: @["--verbose"], internal: @["trace"]),
  Place(path: @["build"], shown: @["--verbose", "--jobs"],
    internal: @["trace", "graph"]),
  Place(path: @["remote"], shown: @["--verbose", "--long"],
    internal: @["trace", "probe"]),
  Place(path: @["remote", "add"], shown: @["--verbose"],
    internal: @["trace"]),
  Place(path: @["internal"], shown: @["--verbose", "--dumpTo"],
    internal: @["trace", "raw"]),
  Place(path: @["internal", "dump"], shown: @["--verbose", "--dumpTo"],
    internal: @["trace", "raw"]),
]

proc flagWords(words: seq[string]): seq[string] =
  ## The flags completion offers at ``words``.
  for c in Ip.complete(words & @["--"]):
    result.add(c.value)

suite "test_cs_m5_internal_parameters_work_unlisted":

  test "no help screen lists an internal parameter, at any level":
    for place in places:
      let text = Ip.helpText(place.path)
      checkpoint(place.path.join(" ") & ":\n" & text)
      for spelling in internalSpellings:
        check spelling notin text
      for spelling in place.shown:
        check spelling in text
      for name in hiddenNames:
        check ("--" & name) notin text

  test "the internal command's help still documents its namespace":
    let text = Ip.helpText(["internal"])
    check "dump" in text and "Dump state" in text
    check "--dumpTo" in text
    check "internal" notin Ip.helpText()

  test "completion never offers an internal or hidden parameter":
    for place in places:
      let offered = flagWords(place.path)
      checkpoint(place.path.join(" ") & ": " & offered.join(" "))
      for spelling in internalSpellings:
        check spelling notin offered
      for name in hiddenNames:
        check ("--" & name) notin offered
      for spelling in place.shown:
        check spelling in offered

  test "the machine-readable help lists them marked internal, never hidden":
    for place in places:
      let doc = parseJson(Ip.helpJson(place.path))
      var internal = initHashSet[string]()
      var everyName = initHashSet[string]()
      for p in doc["command"]["parameters"]:
        everyName.incl(p["name"].getStr)
        if p["visibility"].getStr == "internal":
          internal.incl(p["name"].getStr)
      checkpoint(place.path.join(" ") & ": " & $everyName)
      check internal == toHashSet(place.internal)
      for name in hiddenNames:
        check name notin everyName

  test "given on the command line, each one fills its field":
    let root = Ip.load(@["--trace", "t.log", "build", "--graph=g.dot",
      "app"])
    check root.trace == "t.log"
    check root.command == IpCommand.build
    check root.build.graph == "g.dot" and root.build.target == "app"
    let remote = Ip.load(@["remote", "--probe", "3", "--long"])
    check remote.remote.command == IpRemoteCommand.call
    check remote.remote.call.probe == 3 and remote.remote.call.long
    let inner = Ip.load(@["internal", "--raw", "dump", "--trace", "x"])
    check inner.internal.raw and inner.trace == "x"
    check inner.internal.command == IpInternalCommand.dump
    check inner.internal.dump.what == "all"
