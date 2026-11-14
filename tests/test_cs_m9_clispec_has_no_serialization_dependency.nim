## test_cs_m9_clispec_has_no_serialization_dependency: clispec depends on
## no serialization library. It describes and parses a command line;
## configuration files, and the format libraries that read them
## (``nim-serialization`` and the ``nim-*-serialization`` family built on
## it), belong to confutils, which is instantiated over a clispec
## description.
##
## Checked where a dependency can be declared or taken:
##
## * ``clispec.nimble``: no ``requires`` or ``taskRequires`` names one;
## * ``flake.nix``: no input names one, and the dev shell exports no
##   ``CLISPEC_FORMAT_PATHS`` (the variable that once carried their paths);
## * ``repro.nim``: no fetch or path names one;
## * ``src/``: no module imports one.
##
## Vacuity guards: each reader must find what it reads (the nimble file's
## ``requires``, the flake's inputs, the sources' imports), and the checks
## must reject a text that does declare one, so an unreadable file or a
## broken matcher fails the test instead of passing it. The files are read
## as text, the form they are written in; nothing is mocked.

import std/[os, strutils, unittest]

const
  testsDir = currentSourcePath().parentDir()
  repoDir = testsDir.parentDir()
  # Spelled in pieces so this file's own text does not match them.
  forbidden = ["serial" & "ization", "fast" & "streams"]
  formatPathsVar = "CLISPEC_" & "FORMAT_PATHS"

func namesSerialization(text: string): bool =
  ## Whether ``text`` names a serialization library (``serialization``,
  ## ``toml_serialization``, ``nim-json-serialization``, ...) or the stream
  ## library they read through.
  let lower = text.toLowerAscii()
  for word in forbidden:
    if word in lower:
      return true

func codeLines(text, comment: string): seq[string] =
  ## The lines of ``text`` that are not comments, stripped.
  for line in text.splitLines():
    let code = line.strip()
    if code.len > 0 and not code.startsWith(comment):
      result.add(code)

func nimbleRequires(text: string): seq[string] =
  ## Every ``requires`` / ``taskRequires`` line of a nimble file.
  for code in codeLines(text, "#"):
    if code.startsWith("requires ") or code.startsWith("taskRequires "):
      result.add(code)

func flakeInputs(text: string): seq[string] =
  ## Every line of the flake's ``inputs = { ... };`` block.
  let start = text.find("inputs = {")
  if start < 0:
    return
  let stop = text.find("\n  };", start)
  if stop < 0:
    return
  for code in codeLines(text[start ..< stop], "#"):
    result.add(code)

func imports(text: string): seq[string] =
  ## Every ``import`` / ``from ... import`` / ``include`` statement of a Nim
  ## module, with its continuation lines.
  var current = ""
  for line in text.splitLines():
    let code = line.strip()
    if code.startsWith("#"):
      continue
    if code.startsWith("import ") or code.startsWith("from ") or
        code.startsWith("include "):
      if current.len > 0:
        result.add(current)
      current = code
    elif current.len > 0 and line.startsWith("  ") and code.len > 0:
      current.add(" " & code)
    else:
      if current.len > 0:
        result.add(current)
      current = ""
  if current.len > 0:
    result.add(current)

func withoutTestPaths(line: string): string =
  ## ``line`` without its ``"tests/<module>.nim"`` literals.
  result = line
  while true:
    let start = result.find("\"tests/")
    if start < 0:
      break
    let stop = result.find('"', start + 1)
    if stop < 0:
      break
    result = result[0 ..< start] & result[stop + 1 .. ^1]

proc sourceFiles(): seq[string] =
  for path in walkDirRec(repoDir / "src"):
    if path.endsWith(".nim"):
      result.add(path)

suite "test_cs_m9_clispec_has_no_serialization_dependency":

  test "the matchers reject a text that declares one":
    check namesSerialization(
      "taskRequires \"test\", \"https://github.com/status-im/" &
      "nim-toml-" & "serial" & "ization#b5b387e6\"")
    check namesSerialization("import " & "fast" & "streams/inputs")
    check nimbleRequires("requires \"a\"\n# requires \"b\"\n").len == 1
    check imports("import std/os\nimport a,\n  b\nlet x = 1\n") ==
      @["import std/os", "import a, b"]
    check withoutTestPaths("T(source: \"tests/x.nim\"), \"toml_" & "serial" &
      "ization\"") == "T(source: ), \"toml_" & "serial" & "ization\""

  test "clispec.nimble requires none":
    let declared = nimbleRequires(readFile(repoDir / "clispec.nimble"))
    check declared.len > 0          # requires "nim >= ..."
    for line in declared:
      checkpoint(line)
      check not namesSerialization(line)

  test "flake.nix takes none as an input and exports no format paths":
    let text = readFile(repoDir / "flake.nix")
    let inputs = flakeInputs(text)
    check inputs.len > 0            # nixos-modules, nixpkgs, ...
    for line in inputs:
      checkpoint(line)
      check not namesSerialization(line)
    check formatPathsVar notin text

  test "repro.nim fetches none and puts none on a path":
    let lines = codeLines(readFile(repoDir / "repro.nim"), "#")
    check lines.len > 0
    var testEntries = 0
    for line in lines:
      if line.startsWith("##"):
        continue
      # A test module's own name (this one's says what it checks) is not a
      # dependency.
      let code = withoutTestPaths(line)
      if code != line:
        inc testEntries
      checkpoint(line)
      check not namesSerialization(code)
      check formatPathsVar notin code
    check testEntries > 0         # the test list was read and set aside

  test "no module of the library imports one":
    let files = sourceFiles()
    check files.len > 5
    var seen = 0
    for path in files:
      for statement in imports(readFile(path)):
        inc seen
        checkpoint(path.relativePath(repoDir) & ": " & statement)
        check not namesSerialization(statement)
    check seen >= files.len         # every module imports something
