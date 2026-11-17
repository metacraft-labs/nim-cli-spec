## test_cs_m5c_styled_goldens: the ``depot`` fixture's styled pages in every
## palette, against golden files.
##
## The pages: ``depot -h``, ``depot build -h``, ``depot build --help`` and
## three usage errors (an unknown subcommand, an unknown flag and a value
## outside a closed set, each with its tip). The palettes: ``portable16``,
## dark 24-bit, dark 256, light 24-bit and light 256 (chosen with
## ``CliOptions.colorDepth`` and ``background``, the fixture's
## ``DEPOT_FIXTURE_DEPTH`` and ``DEPOT_FIXTURE_BACKGROUND``, with
## ``CliOptions.color = ccmAlways`` through pipes), and the users'
## overrides (``CLISPEC_COLORS`` and ``DEPOT_COLORS``, in a build with
## ``-d:clispec_user_colors=on``).
##
## The goldens are
## ``tests/fixtures/cs_m5c_colour/goldens/<palette>_<page>.txt``,
## with ``ESC`` written for the escape character. They are what the program
## prints, never typed by hand: run this test with
## ``CLISPEC_REGENERATE_GOLDENS=1`` to write them from the fixture's output
## (then review the diff). Otherwise a golden that differs from the output
## fails the test; nothing is updated.
##
## For each golden the test checks that it is what the fixture prints now;
## that without its escape sequences it is the plain page the fixture
## prints with ``CliOptions.color = ccmNever``, byte for byte, and that
## plain page is the library's; that it is the library's rendering of the
## page with the palette; and that its SGR sequences are exactly the
## palette's, which the test types out from the design's table (and
## compares with the library's constants): every span opens with one of the
## palette's values and closes with ``ESC[0m``, each element is styled
## with its own value where it appears, and an element whose override is
## empty is not styled at all.

import std/[os, sets, strutils, tables, tempfiles, unittest]

import clispec

import ./colour_harness
import ./fixtures/cs_m5b_help/depot_cli

const
  goldenDir = currentSourcePath().parentDir() / "fixtures" / "cs_m5c_colour" /
    "goldens"

  # The design's table, typed out: heading, literal, placeholder, error,
  # invalid, tip.
  specPortable16: CliPalette = ["1;34", "1", "35", "1;31", "4;35", "1;34"]
  specDark24: CliPalette = ["1;38;2;82;198;137", "1;38;2;83;192;210",
    "38;2;150;183;189", "1;38;2;255;147;139", "38;2;227;168;1",
    "1;38;2;82;198;137"]
  specDark256: CliPalette = ["1;38;5;42", "1;38;5;44", "38;5;152",
    "1;38;5;217", "38;5;178", "1;38;5;42"]
  specLight24: CliPalette = ["1;38;2;18;129;81", "1;38;2;9;125;140",
    "38;2;87;118;124", "1;38;2;214;47;53", "38;2;145;107;2",
    "1;38;2;18;129;81"]
  specLight256: CliPalette = ["1;38;5;22", "1;38;5;23", "38;5;242",
    "1;38;5;160", "38;5;94", "1;38;5;22"]

  usersShared = "heading=1;4:literal=36:tip="
  usersProgram = "literal=1;33:invalid=7:bg=light:junk:placeholder=red"

type
  Variant = object
    name: string
    build: string
      ## ``default`` or ``user_colors``.
    env: seq[(string, string)]
    palette: CliPalette
  Page = object
    name: string
    args: seq[string]
    path: seq[string]
      ## Help: the command's path; empty for an error.
    long: bool
    error: bool

func usersPalette(): CliPalette =
  ## light 24-bit (``bg=light``) with the overrides: the program's
  ## ``literal`` over the shared one, ``tip`` empty, ``invalid`` 7; the
  ## malformed ``placeholder=red`` and ``junk`` ignored.
  result = specLight24
  result[ctsHeading] = "1;4"
  result[ctsLiteral] = "1;33"
  result[ctsTip] = ""
  result[ctsOffending] = "7"

let
  always = ("DEPOT_FIXTURE_COLOR", "always")
  variants = @[
    Variant(name: "portable16", build: "default", env: @[always],
      palette: specPortable16),
    Variant(name: "dark-24", build: "default", env: @[always,
      ("DEPOT_FIXTURE_DEPTH", "24"), ("DEPOT_FIXTURE_BACKGROUND", "dark")],
      palette: specDark24),
    Variant(name: "dark-256", build: "default", env: @[always,
      ("DEPOT_FIXTURE_DEPTH", "256"), ("DEPOT_FIXTURE_BACKGROUND", "dark")],
      palette: specDark256),
    Variant(name: "light-24", build: "default", env: @[always,
      ("DEPOT_FIXTURE_DEPTH", "24"), ("DEPOT_FIXTURE_BACKGROUND", "light")],
      palette: specLight24),
    Variant(name: "light-256", build: "default", env: @[always,
      ("DEPOT_FIXTURE_DEPTH", "256"), ("DEPOT_FIXTURE_BACKGROUND", "light")],
      palette: specLight256),
    Variant(name: "users", build: "user_colors", env: @[always,
      ("DEPOT_FIXTURE_DEPTH", "24"), ("DEPOT_FIXTURE_BACKGROUND", "dark"),
      ("CLISPEC_COLORS", usersShared), ("DEPOT_COLORS", usersProgram)],
      palette: usersPalette())]
  pages = @[
    Page(name: "root_short", args: @["-h"]),
    Page(name: "build_short", args: @["build", "-h"], path: @["build"]),
    Page(name: "build_long", args: @["build", "--help"], path: @["build"],
      long: true),
    Page(name: "error_subcommand", args: @["biuld"], error: true),
    Page(name: "error_flag", args: @["build", "--job", "3"], error: true),
    Page(name: "error_value", args: @["build", "--profile", "relase"],
      error: true)]


proc compilerExe(): string =
  ## The compiler that built this test.
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

var scratch = ""
var builds: Table[string, string]

proc exe(build: string): string =
  if scratch.len == 0:
    scratch = createTempDir("clispec_m5c_goldens_", "")
  if build notin builds:
    builds[build] = buildFixture(compilerExe(), scratch, build,
      if build == "user_colors": @["clispec_user_colors=on"] else: @[])
  builds[build]

proc printed(build: string; page: Page;
             env: openArray[(string, string)]): string =
  ## What the fixture prints for ``page``: help on standard output, an
  ## error on standard error (and nothing on the other).
  let r = throughPipes(exe(build), page.args, env)
  if page.error:
    doAssert r.code == 2 and r.output == "", $page.args & ": " & $r
    r.errors
  else:
    doAssert r.code == 0 and r.errors == "", $page.args & ": " & $r
    r.output

proc usageError(argv: openArray[string]): ref CliUsageError =
  try:
    discard Depot.load(@argv)
  except CliUsageError as e:
    return e
  doAssert false, "no usage error for " & $argv

proc rendered(page: Page; style: CliStyle): string =
  ## The library's rendering of ``page`` at 80 columns.
  if page.error:
    cliErrorText(usageError(page.args), style)
  else:
    var layout = cliDefaultHelpLayout
    layout.width = 80
    Depot.helpText(page.path, style, layout = layout, long = page.long)

func goldenPath(v: Variant; page: Page): string =
  goldenDir / (v.name & "_" & page.name & ".txt")

proc spans(text: string): seq[(string, string)] =
  ## Every styled span of ``text``: its SGR parameters and its text. Fails
  ## on an escape sequence that is not ``ESC[<digits and ;>m``, a span
  ## not closed by ``ESC[0m`` before the next one, and a stray reset.
  var i = 0
  while true:
    let at = text.find('\e', i)
    if at < 0:
      break
    doAssert text.continuesWith("\e[", at), "not a CSI at " & $at
    let m = text.find('m', at)
    doAssert m > at, "an unterminated sequence at " & $at
    let params = text[at + 2 ..< m]
    doAssert params.len > 0 and params.allCharsInSet({'0' .. '9', ';'}),
      "not an SGR: " & params.escape
    doAssert params != "0", "a reset that closes nothing at " & $at
    let close = text.find(CliStyleReset, m + 1)
    doAssert close > m + 1, "a span without text or reset at " & $at
    let inner = text[m + 1 ..< close]
    doAssert '\e' notin inner, "a span opened inside another at " & $at
    result.add((params, inner))
    i = close + CliStyleReset.len

suite "test_cs_m5c_styled_goldens":

  test "the library's palettes are the design's table":
    check cliPortable16 == specPortable16
    check cliDark24 == specDark24
    check cliDark256 == specDark256
    check cliLight24 == specLight24
    check cliLight256 == specLight256

  test "every page in every palette equals its golden":
    let regenerate = getEnv("CLISPEC_REGENERATE_GOLDENS").len > 0
    if regenerate:
      createDir(goldenDir)
    var compared = 0
    for v in variants:
      var used = initHashSet[string]()
      for page in pages:
        checkpoint(v.name & " " & page.name)
        let output = printed(v.build, page, v.env)
        let path = goldenPath(v, page)
        if regenerate:
          writeFile(path, output.replace("\e", "ESC"))
          echo "regenerated ", path
        check fileExists(path)
        let golden = readFile(path).replace("ESC", "\e")
        check golden == output
        # The plain page, from the program and from the library.
        let plain = printed(v.build, page, [("DEPOT_FIXTURE_COLOR", "never")])
        check "\e" notin plain
        check plain == rendered(page, CliStyle())
        check cliStripStyles(golden) == plain
        check golden != plain
        # The library's rendering with the palette.
        check golden == rendered(page, CliStyle(on: true, sgr: v.palette))
        # The SGR sequences: the palette's values and nothing else.
        var values = initHashSet[string]()
        for e in CliTextStyle:
          if v.palette[e].len > 0:
            values.incl(v.palette[e])
        for (params, inner) in spans(golden):
          checkpoint(params & " " & inner)
          check params in values
          used.incl(params)
        # Each element in its own value where it appears.
        template has(e: CliTextStyle; text: string) =
          if v.palette[e].len > 0:
            check ("\e[" & v.palette[e] & "m" & text & CliStyleReset) in golden
          else:
            check text in golden
            check ("m" & text & CliStyleReset) notin golden
        has(ctsHeading, "Usage:")
        has(ctsLiteral, "depot")
        if page.error:
          has(ctsError, "error:")
          has(ctsTip, "tip:")
          let word = if page.name == "error_value": "relase"
                     elif page.name == "error_flag": "--job"
                     else: "biuld"
          has(ctsOffending, word)
        else:
          has(ctsPlaceholder, "[options]")
        inc compared
      # Across the pages, every value of the palette is used.
      var values = initHashSet[string]()
      for e in CliTextStyle:
        if v.palette[e].len > 0:
          values.incl(v.palette[e])
      checkpoint(v.name)
      check used == values
    check compared == variants.len * pages.len

  test "an empty override leaves the element unstyled":
    let golden = readFile(goldenPath(variants[^1], pages[3])).replace(
      "ESC", "\e")
    check "\n\n  tip: a similar subcommand exists: '" in golden

  if scratch.len > 0 and dirExists(scratch):
    removeDir(scratch)
