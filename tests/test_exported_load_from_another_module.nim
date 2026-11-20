## test_exported_load_from_another_module: the ``load`` overload that takes
## no ``argv`` (it parses the process's own arguments) compiles and parses
## for a description declared with ``exported = true`` in one module and
## loaded from another, and for a description that is not exported.
##
## The generated procedures take a ``typedesc``, so their bodies are checked
## only where a module calls them: a description that is never loaded
## without ``argv`` does not show a broken body. This module calls that
## overload (in ``ownCommandLine``, compiled and not run, since its own
## command line is the test runner's), and builds and runs the fixture
## programs ``tests/fixtures/exported_load/relay.nim`` (which loads the
## description ``relay_cli.nim`` exports) and ``local.nim`` (declared and
## loaded in one module) with real command lines. Nothing is mocked.

import std/[os, osproc, strutils, tempfiles, unittest]

import clispec

import ./fixtures/exported_load/relay_cli

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()
  srcDir = repoDir / "src"
  fixturesDir = testsDir / "fixtures" / "exported_load"

proc compilerExe(): string =
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

proc ownCommandLine(): Relay {.used.} =
  ## Compiled, not run: instantiates the no-``argv`` ``load`` of the
  ## imported, exported description in this module.
  Relay.load()

proc beaconOwnCommandLine(): Beacon {.used.} =
  ## The same for the second description the fixture module exports.
  Beacon.load()

var scratch = ""

proc build(name: string): string =
  ## The fixture program ``name`` compiled into the scratch directory.
  if scratch.len == 0:
    scratch = createTempDir("clispec_exported_load_", "")
  result = scratch / addFileExt(name, ExeExt)
  let (output, code) = execCmdEx(quoteShellCommand([compilerExe(), "c",
    "--hints:off", "--skipParentCfg", "--skipUserCfg",
    "--path:" & srcDir, "--nimcache:" & (scratch / ("nimcache_" & name)),
    "-o:" & result, fixturesDir / (name & ".nim")]))
  checkpoint(output)
  doAssert code == 0, "the fixture " & name & " does not compile:\n" & output

proc run(exe: string; args: openArray[string]): tuple[output: string;
    code: int] =
  let (output, code) = execCmdEx(quoteShellCommand(@[exe] & @args),
    options = {poStdErrToStdOut})
  (output.strip(), code)

suite "test_exported_load_from_another_module":

  test "the importing module loads the exported description from argv":
    let c = Relay.load(@["--port=9", "send", "hi"])
    check c.port == 9
    check c.command == RelayCommand.send
    check c.send.message == "hi"

  test "two exported descriptions of one module load as their own types":
    check Beacon.load(@["--level=3"]).level == 3
    check Beacon.load(@[]).level == 1
    expect CliUsageError:
      discard Beacon.load(@["--port=9"])

  test "an exported description is loaded from the program's own arguments":
    let relay = build("relay")
    check run(relay, ["send", "hello"]) ==
      ("port=8080 quiet=false command=send message=hello", 0)
    check run(relay, ["-q", "--port", "7", "send", "x"]) ==
      ("port=7 quiet=true command=send message=x", 0)
    let bad = run(relay, ["--port=no", "send", "x"])
    check bad.code == 2
    check "port" in bad.output

  test "a description that is not exported is loaded the same way":
    let local = build("local")
    check run(local, []) == ("count=1", 0)
    check run(local, ["--count", "3"]) == ("count=3", 0)

if scratch.len > 0:
  removeDir(scratch)
