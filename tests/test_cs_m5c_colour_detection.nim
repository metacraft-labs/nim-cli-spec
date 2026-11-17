## test_cs_m5c_colour_detection: every input of the colour decision selects
## what the rules of ``clispec/styles`` name, both through the decision
## procs (``cliDecideStyle`` over a fake environment, terminal and query
## answer) and in real runs of the ``depot`` fixture
## (``tests/fixtures/cs_m5b_help/depot.nim``) on a pseudo-terminal the test
## opens and through pipes.
##
## The inputs: the stream (pipe or terminal), ``NO_COLOR`` (set, empty),
## ``FORCE_COLOR`` (``0``, ``false``, ``1``, ``2``, ``3``, empty, ``true``),
## ``CLICOLOR_FORCE``, ``CLICOLOR``, ``COLORTERM``, ``TERM`` (unset, ``dumb``,
## ``xterm``, ``xterm-256color``, ``screen*``, ``tmux*``), ``CI``,
## ``CliOptions.color``, ``colorDepth`` and ``background`` (the fixture's
## ``DEPOT_FIXTURE_*`` variables), ``COLORFGBG``, the users' ``bg=`` and the
## background query: answered dark, answered light, not answered (the
## program waits 100 ms and uses ``portable16``) and not sent under
## ``TERM=screen*``/``tmux*`` or when an earlier source answered.
##
## Each case names the style it expects (on or off, the depth, the
## background, hence the palette) and whether the query is sent. The
## decision procs must give exactly that, and a real run of the fixture
## must print ``depot build -h`` rendered with exactly that style (and send
## the query exactly when expected). The compile-time knobs are checked the
## same way: the decision procs with other configurations (and which
## variables they read), fixture builds with ``-d:`` defines, and the
## compile-time errors for bad define values, each paired with a valid one.
##
## Negative control: ``runCase`` reports a mismatch rather than asserting,
## so the test also runs cases against fixture builds that drop a rule
## through its knob (``-d:clispec_color_env=off`` ignores ``NO_COLOR``,
## ``FORCE_COLOR``, ``CLICOLOR`` and ``CLICOLOR_FORCE``;
## ``-d:clispec_colorfgbg=off`` ignores ``COLORFGBG``;
## ``-d:clispec_background_query=off`` never asks the terminal) and checks
## that exactly the cases that depend on the dropped rule then fail.
##
## A POSIX platform where no pseudo-terminal can be opened fails this test.
## On Windows the terminal cases are compiled out and the test says so (they
## are not counted as passes).

import std/[algorithm, os, sequtils, strutils, tables, tempfiles, unittest]

import clispec

import ./colour_harness
import ./fixtures/cs_m5b_help/depot_cli

const
  darkAnswer = "\e]11;rgb:1e1e/1e1e/2e2e\e\\\e]10;rgb:d4d4/d4d4/d4d4\e\\" &
    "\e[?62;22c"
    ## A dark theme's answer, ended by ST.
  lightAnswer = "\e]11;rgb:ffff/ffff/ffff\a\e]10;rgb:3333/3333/3333\a" &
    "\e[?64;1;22c"
    ## A light theme's answer, ended by BEL.

type
  Stream = enum onPipe, onTerm
  Case = object
    name: string
    stream: Stream
    env: seq[(string, string)]
      ## The environment, the fixture's ``DEPOT_FIXTURE_*`` included.
    answer: string
      ## What the terminal answers to the query ("" for nothing).
    on: bool
    depth: CliColorDepth
    background: CliBackground
    queried: bool
      ## The query is sent.

func styled(depth: CliColorDepth; background: CliBackground): CliStyle =
  ## The style the rules give for a depth and background.
  result = CliStyle(on: true, depth: depth, background: background)
  result.sgr =
    if depth == ccd16 or background == cbUnknown: cliPortable16
    elif background == cbDark and depth == ccd24: cliDark24
    elif background == cbDark: cliDark256
    elif depth == ccd24: cliLight24
    else: cliLight256

func expected(c: Case): CliStyle =
  if c.on: styled(c.depth, c.background) else: CliStyle()

func on(name: string; stream: Stream; env: seq[(string, string)];
        depth = ccd16; background = cbUnknown; answer = "";
        queried = false): Case =
  Case(name: name, stream: stream, env: env, on: true, depth: depth,
    background: background, answer: answer, queried: queried)

func off(name: string; stream: Stream; env: seq[(string, string)]): Case =
  Case(name: name, stream: stream, env: env, on: false, depth: ccdAuto,
    background: cbAuto)

let cases = @[
  # The stream, and TERM (rule 6).
  off("a pipe is plain", onPipe, @[("TERM", "xterm-256color")]),
  on("a terminal with TERM=xterm: 16 colours", onTerm, @[("TERM", "xterm")]),
  off("a terminal without TERM is plain", onTerm, @[]),
  off("a terminal with an empty TERM is plain", onTerm, @[("TERM", "")]),
  off("a terminal with TERM=dumb is plain", onTerm, @[("TERM", "dumb")]),
  on("CI on a terminal without TERM", onTerm, @[("CI", "true")]),
  on("CI on a terminal with TERM=dumb", onTerm,
    @[("TERM", "dumb"), ("CI", "1")]),
  off("CI through a pipe is plain", onPipe, @[("CI", "true")]),
  # NO_COLOR (rule 2).
  off("NO_COLOR=1 on a terminal", onTerm,
    @[("TERM", "xterm"), ("NO_COLOR", "1")]),
  on("NO_COLOR empty is not set", onTerm,
    @[("TERM", "xterm"), ("NO_COLOR", "")]),
  off("NO_COLOR wins over FORCE_COLOR", onPipe,
    @[("NO_COLOR", "1"), ("FORCE_COLOR", "1")]),
  # FORCE_COLOR (rule 3, and depth rule 2).
  off("FORCE_COLOR=0 on a terminal", onTerm,
    @[("TERM", "xterm"), ("FORCE_COLOR", "0")]),
  off("FORCE_COLOR=false on a terminal", onTerm,
    @[("TERM", "xterm"), ("FORCE_COLOR", "false")]),
  on("FORCE_COLOR=1 through a pipe", onPipe, @[("FORCE_COLOR", "1")]),
  on("FORCE_COLOR empty through a pipe", onPipe, @[("FORCE_COLOR", "")]),
  on("FORCE_COLOR=true through a pipe", onPipe, @[("FORCE_COLOR", "true")]),
  on("FORCE_COLOR=2 with a dark COLORFGBG: dark, 256", onPipe,
    @[("FORCE_COLOR", "2"), ("COLORFGBG", "15;0")], ccd256, cbDark),
  on("FORCE_COLOR=3 with a light COLORFGBG: light, 24-bit", onPipe,
    @[("FORCE_COLOR", "3"), ("COLORFGBG", "0;15")], ccd24, cbLight),
  on("FORCE_COLOR=3, background unknown through a pipe: portable16",
    onPipe, @[("FORCE_COLOR", "3")]),
  off("FORCE_COLOR=0 wins over CLICOLOR_FORCE", onPipe,
    @[("FORCE_COLOR", "0"), ("CLICOLOR_FORCE", "1")]),
  on("FORCE_COLOR=1 wins over CLICOLOR=0", onPipe,
    @[("FORCE_COLOR", "1"), ("CLICOLOR", "0")]),
  # CLICOLOR_FORCE (rule 4) and CLICOLOR (rule 5).
  on("CLICOLOR_FORCE=1 through a pipe", onPipe, @[("CLICOLOR_FORCE", "1")]),
  off("CLICOLOR_FORCE=0 through a pipe", onPipe, @[("CLICOLOR_FORCE", "0")]),
  off("CLICOLOR_FORCE empty through a pipe", onPipe,
    @[("CLICOLOR_FORCE", "")]),
  on("CLICOLOR_FORCE wins over CLICOLOR=0", onPipe,
    @[("CLICOLOR_FORCE", "1"), ("CLICOLOR", "0")]),
  off("CLICOLOR=0 on a terminal", onTerm,
    @[("TERM", "xterm"), ("CLICOLOR", "0")]),
  on("CLICOLOR=1 on a terminal", onTerm,
    @[("TERM", "xterm"), ("CLICOLOR", "1")]),
  # CliOptions.color (rule 1).
  on("color = always through a pipe", onPipe,
    @[("DEPOT_FIXTURE_COLOR", "always")]),
  on("color = always wins over NO_COLOR and TERM=dumb", onPipe,
    @[("DEPOT_FIXTURE_COLOR", "always"), ("NO_COLOR", "1"),
      ("TERM", "dumb")]),
  off("color = never on a terminal", onTerm,
    @[("TERM", "xterm-256color"), ("DEPOT_FIXTURE_COLOR", "never")]),
  off("color = never wins over FORCE_COLOR", onPipe,
    @[("DEPOT_FIXTURE_COLOR", "never"), ("FORCE_COLOR", "3")]),
  # Depth: COLORTERM and TERM, with COLORFGBG for the background.
  on("COLORTERM=truecolor, COLORFGBG dark: dark, 24-bit", onTerm,
    @[("TERM", "xterm"), ("COLORTERM", "truecolor"), ("COLORFGBG", "15;0")],
    ccd24, cbDark),
  on("COLORTERM=24bit, COLORFGBG light: light, 24-bit", onTerm,
    @[("TERM", "xterm"), ("COLORTERM", "24bit"), ("COLORFGBG", "0;15")],
    ccd24, cbLight),
  on("COLORTERM=yes is not 24-bit", onTerm,
    @[("TERM", "xterm"), ("COLORTERM", "yes"), ("COLORFGBG", "15;0")]),
  on("TERM=xterm-256color, COLORFGBG dark: dark, 256", onTerm,
    @[("TERM", "xterm-256color"), ("COLORFGBG", "15;0")], ccd256, cbDark),
  on("TERM=xterm-256color, COLORFGBG 0;7: light, 256", onTerm,
    @[("TERM", "xterm-256color"), ("COLORFGBG", "0;7")], ccd256, cbLight),
  on("COLORFGBG with three fields: the last one", onTerm,
    @[("TERM", "xterm-256color"), ("COLORFGBG", "15;default;8")], ccd256,
    cbDark),
  on("TERM=putty-256 is 256", onTerm,
    @[("TERM", "putty-256"), ("COLORFGBG", "0;15")], ccd256, cbLight),
  on("COLORFGBG at depth 16 changes nothing", onTerm,
    @[("TERM", "xterm"), ("COLORFGBG", "15;0")]),
  # The query.
  on("the query answered dark: dark, 256", onTerm,
    @[("TERM", "xterm-256color")], ccd256, cbDark, darkAnswer, true),
  on("the query answered light: light, 256", onTerm,
    @[("TERM", "xterm-256color")], ccd256, cbLight, lightAnswer, true),
  on("the query answered light at 24-bit: light, 24-bit", onTerm,
    @[("TERM", "xterm-256color"), ("COLORTERM", "truecolor")], ccd24,
    cbLight, lightAnswer, true),
  on("the query not answered: portable16 after 100 ms", onTerm,
    @[("TERM", "xterm-256color")], ccd16, cbUnknown, "", true),
  on("an unparsable COLORFGBG leaves it to the query", onTerm,
    @[("TERM", "xterm-256color"), ("COLORFGBG", "default")], ccd256, cbDark,
    darkAnswer, true),
  on("no query under TERM=screen-256color", onTerm,
    @[("TERM", "screen-256color")], ccd16, cbUnknown, darkAnswer, false),
  on("no query under TERM=tmux-256color", onTerm,
    @[("TERM", "tmux-256color")], ccd16, cbUnknown, darkAnswer, false),
  on("no query at depth 16", onTerm, @[("TERM", "xterm")], ccd16,
    cbUnknown, darkAnswer, false),
  on("no query when COLORFGBG answered", onTerm,
    @[("TERM", "xterm-256color"), ("COLORFGBG", "0;15")], ccd256, cbLight,
    darkAnswer, false),
  on("no query through a pipe", onPipe,
    @[("TERM", "xterm-256color"), ("FORCE_COLOR", "1")], ccd16, cbUnknown),
  # CliOptions.colorDepth and CliOptions.background.
  on("colorDepth 24, background dark: dark, 24-bit", onPipe,
    @[("DEPOT_FIXTURE_COLOR", "always"), ("DEPOT_FIXTURE_DEPTH", "24"),
      ("DEPOT_FIXTURE_BACKGROUND", "dark")], ccd24, cbDark),
  on("colorDepth 256, background light: light, 256", onPipe,
    @[("DEPOT_FIXTURE_COLOR", "always"), ("DEPOT_FIXTURE_DEPTH", "256"),
      ("DEPOT_FIXTURE_BACKGROUND", "light")], ccd256, cbLight),
  on("colorDepth 16 wins over COLORTERM", onTerm,
    @[("TERM", "xterm-256color"), ("COLORTERM", "truecolor"),
      ("DEPOT_FIXTURE_DEPTH", "16"), ("DEPOT_FIXTURE_BACKGROUND", "dark")]),
  on("colorDepth 256 wins over COLORTERM and FORCE_COLOR=3", onPipe,
    @[("FORCE_COLOR", "3"), ("COLORTERM", "truecolor"),
      ("DEPOT_FIXTURE_DEPTH", "256"), ("COLORFGBG", "15;0")], ccd256,
    cbDark),
  on("background light wins over COLORFGBG and the query", onTerm,
    @[("TERM", "xterm-256color"), ("COLORFGBG", "15;0"),
      ("DEPOT_FIXTURE_BACKGROUND", "light")], ccd256, cbLight, darkAnswer,
    false),
  on("background unknown: portable16, no query", onTerm,
    @[("TERM", "xterm-256color"), ("COLORFGBG", "15;0"),
      ("DEPOT_FIXTURE_BACKGROUND", "unknown")], ccd16, cbUnknown,
    darkAnswer, false)]

# ---------------------------------------------------------------------------
# The decision procs, over fake inputs.
# ---------------------------------------------------------------------------

type Fake = ref object
  env: Table[string, string]
  terminal: bool
  answer: string
  read: seq[string]
    ## Every variable looked up, in order.
  queries: int

proc inputs(f: Fake; program = "depot"): CliColorInputs =
  result.env = proc (name: string): CliEnvValue {.closure, gcsafe,
      raises: [].} =
    {.cast(gcsafe).}:
      f.read.add(name)
      if name in f.env: (true, f.env.getOrDefault(name)) else: (false, "")
  result.isTerminal = proc (): bool {.closure, gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      f.terminal
  result.queryBackground = proc (): string {.closure, gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      inc f.queries
      f.answer
  result.program = program

proc fake(env: openArray[(string, string)]; terminal = true;
          answer = ""): Fake =
  result = Fake(terminal: terminal, answer: answer)
  for (k, v) in env:
    result.env[k] = v

proc options(env: openArray[(string, string)]):
    (CliColorMode, CliColorDepth, CliBackground) =
  ## The fixture's ``CliOptions`` for the ``DEPOT_FIXTURE_*`` in ``env``.
  result = (ccmAuto, ccdAuto, cbAuto)
  for (k, v) in env:
    case k
    of "DEPOT_FIXTURE_COLOR":
      result[0] = (if v == "always": ccmAlways elif v == "never": ccmNever
                   else: ccmAuto)
    of "DEPOT_FIXTURE_DEPTH":
      result[1] = (case v
                   of "16": ccd16
                   of "256": ccd256
                   of "24": ccd24
                   else: ccdAuto)
    of "DEPOT_FIXTURE_BACKGROUND":
      result[2] = (case v
                   of "dark": cbDark
                   of "light": cbLight
                   of "unknown": cbUnknown
                   else: cbAuto)
    else: discard

proc decide(c: Case; f: Fake;
            config: static CliColorConfig = cliColorDefaults): CliStyle =
  let (color, depth, background) = options(c.env)
  cliDecideStyle(color, depth, background, f.inputs, config)

proc decided(c: Case): string =
  ## A mismatch between the case and the decision procs, or "".
  let f = fake(c.env, c.stream == onTerm, c.answer)
  let got = decide(c, f)
  if got != expected(c):
    return "decided " & $got & ", expected " & $expected(c)
  if (f.queries > 0) != c.queried:
    return "query asked " & $f.queries & " times, expected " & $c.queried

# ---------------------------------------------------------------------------
# Real runs.
# ---------------------------------------------------------------------------


proc compilerExe(): string =
  ## The compiler that built this test.
  result = getCurrentCompilerExe()
  if not fileExists(result):
    result = findExe("nim")

var scratch = ""
var builds: Table[string, string]

proc build(name: string; defines: openArray[string] = []): string =
  if scratch.len == 0:
    scratch = createTempDir("clispec_m5c_detect_", "")
  if name notin builds:
    builds[name] = buildFixture(compilerExe(), scratch, name, defines)
  builds[name]

proc page(width: int; style: CliStyle): string =
  var layout = cliDefaultHelpLayout
  layout.width = width
  Depot.helpText(["build"], style, layout = layout)

proc runCase(exe: string; c: Case): string =
  ## Runs ``depot build -h`` as the case says; a mismatch with what the
  ## case expects, or "".
  when defined(windows):
    if c.stream == onTerm:
      return ""
  var r: Outcome
  if c.stream == onTerm:
    when not defined(windows):
      r = onTerminal(exe, ["build", "-h"], c.env, 90, c.answer)
  else:
    r = throughPipes(exe, ["build", "-h"], c.env)
  let width = if c.stream == onTerm: 90 else: 80
  let want = page(width, expected(c))
  if r.code != 0:
    return "exit code " & $r.code & ": " & r.output & r.errors
  if r.output != want:
    return "printed:\n" & r.output.escape & "\nexpected:\n" & want.escape
  if cliStripStyles(r.output) != page(width, CliStyle()):
    return "not the plain page once the escapes are removed"
  if r.queried != c.queried:
    return "query sent: " & $r.queried & ", expected " & $c.queried
  if c.stream == onTerm and c.queried and c.answer.len == 0 and
      r.seconds < 0.1:
    return "an unanswered query did not wait 100 ms (" & $r.seconds & " s)"
  ""

when defined(windows):
  echo "NOT RUN on Windows: the terminal cases of this test need a POSIX " &
    "pseudo-terminal; they run on Linux and macOS. The pipe cases run."

suite "test_cs_m5c_colour_detection":

  test "the decision procs select what every case names":
    for c in cases:
      checkpoint(c.name)
      check decided(c) == ""

  test "a real run selects what every case names":
    let exe = build("default")
    var ran = 0
    for c in cases:
      checkpoint(c.name)
      check runCase(exe, c) == ""
      inc ran
    check ran == cases.len

  test "the users' bg= is the first background source":
    # Decision procs, with the users' overrides compiled in.
    const userOn = CliColorConfig(colors: ccmAuto, colorEnv: true,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: true,
      backgroundQuery: true, userColors: true)
    let env = @[("TERM", "xterm-256color"), ("COLORFGBG", "15;0"),
      ("DEPOT_COLORS", "bg=light"), ("DEPOT_FIXTURE_BACKGROUND", "dark")]
    let c = on("DEPOT_COLORS=bg=light over the rest", onTerm, env, ccd256,
      cbLight, darkAnswer, false)
    let f = fake(env, true, darkAnswer)
    check decide(c, f, userOn) == expected(c)
    check f.queries == 0
    # The program's variable over CLISPEC_COLORS.
    let both = fake({"TERM": "xterm-256color", "CLISPEC_COLORS": "bg=dark",
      "DEPOT_COLORS": "bg=light"}, true, darkAnswer)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, both.inputs,
      userOn).background == cbLight
    let shared = fake({"TERM": "xterm-256color",
      "CLISPEC_COLORS": "bg=light"}, true, darkAnswer)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, shared.inputs,
      userOn).sgr == cliLight256
    # Without the knob, bg= does not exist: CliOptions.background decides.
    let ignored = fake(env, true, darkAnswer)
    check decide(c, ignored).background == cbDark
    check "DEPOT_COLORS" notin ignored.read
    check "CLISPEC_COLORS" notin ignored.read
    # A real run of a build with the knob on, and of one without.
    let users = build("user_colors", ["clispec_user_colors=on"])
    check runCase(users, c) == ""
    check runCase(build("default"), c) != ""
    var dark = c
    dark.background = cbDark
    check runCase(build("default"), dark) == ""

  test "the decision reads only the variables its knobs leave":
    # The defaults, on a 256-colour terminal that answers the query: the
    # environment switches, TERM, COLORTERM, COLORFGBG and nothing else
    # (CI is not needed once TERM is usable; no users' variables).
    let f = fake({"TERM": "xterm-256color"}, true, darkAnswer)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, f.inputs) ==
      styled(ccd256, cbDark)
    check f.read.deduplicate.sorted == @["CLICOLOR", "CLICOLOR_FORCE",
      "COLORFGBG", "COLORTERM", "FORCE_COLOR", "NO_COLOR", "TERM"]
    check f.queries == 1
    # clispec_color_env=off: NO_COLOR, FORCE_COLOR, CLICOLOR* never read.
    const noEnv = CliColorConfig(colors: ccmAuto, colorEnv: false,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: true,
      backgroundQuery: true)
    let g = fake({"TERM": "xterm-256color", "NO_COLOR": "1",
      "FORCE_COLOR": "3", "CLICOLOR": "0"}, true, lightAnswer)
    let s = cliDecideStyle(ccmAuto, ccdAuto, cbAuto, g.inputs, noEnv)
    check s == styled(ccd256, cbLight)
    for name in ["NO_COLOR", "FORCE_COLOR", "CLICOLOR", "CLICOLOR_FORCE"]:
      check name notin g.read
    # clispec_colorfgbg=off: COLORFGBG is not read; the query decides.
    const noFgBg = CliColorConfig(colors: ccmAuto, colorEnv: true,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: false,
      backgroundQuery: true)
    let h = fake({"TERM": "xterm-256color", "COLORFGBG": "0;15"}, true,
      darkAnswer)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, h.inputs, noFgBg) ==
      styled(ccd256, cbDark)
    check "COLORFGBG" notin h.read
    # clispec_background_query=off: no query, background unknown.
    const noQuery = CliColorConfig(colors: ccmAuto, colorEnv: true,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: true,
      backgroundQuery: false)
    let q = fake({"TERM": "xterm-256color"}, true, darkAnswer)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, q.inputs, noQuery) ==
      cliPortable16Style
    check q.queries == 0
    # clispec_color_depth=256: no COLORTERM, TERM or FORCE_COLOR for depth,
    # CliOptions.colorDepth ignored.
    const fixed256 = CliColorConfig(colors: ccmAuto, colorEnv: true,
      colorDepth: ccd256, background: cbAuto, colorFgBg: true,
      backgroundQuery: true)
    let d = fake({"FORCE_COLOR": "3", "COLORTERM": "truecolor",
      "COLORFGBG": "15;0"}, false)
    check cliDecideStyle(ccmAuto, ccd24, cbAuto, d.inputs, fixed256) ==
      styled(ccd256, cbDark)
    check "COLORTERM" notin d.read
    check "TERM" notin d.read
    # clispec_background=light: no source read, no query, the option
    # ignored.
    const fixedLight = CliColorConfig(colors: ccmAuto, colorEnv: true,
      colorDepth: ccdAuto, background: cbLight, colorFgBg: true,
      backgroundQuery: true)
    let b = fake({"TERM": "xterm-256color", "COLORFGBG": "15;0"}, true,
      darkAnswer)
    check cliDecideStyle(ccmAuto, ccdAuto, cbDark, b.inputs, fixedLight) ==
      styled(ccd256, cbLight)
    check "COLORFGBG" notin b.read
    check b.queries == 0
    # clispec_background=unknown: portable16 whatever the depth.
    const fixedUnknown = CliColorConfig(colors: ccmAuto, colorEnv: true,
      colorDepth: ccdAuto, background: cbUnknown, colorFgBg: true,
      backgroundQuery: true)
    let u = fake({"TERM": "xterm-256color", "COLORTERM": "truecolor",
      "COLORFGBG": "15;0"}, true, darkAnswer)
    check cliDecideStyle(ccmAuto, ccdAuto, cbDark, u.inputs, fixedUnknown) ==
      cliPortable16Style
    check "COLORFGBG" notin u.read and u.queries == 0
    # clispec_colors=never: nothing styled, CliOptions.color ignored,
    # nothing read.
    const never = CliColorConfig(colors: ccmNever, colorEnv: true,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: true,
      backgroundQuery: true)
    let n = fake({"FORCE_COLOR": "1"}, true)
    check cliDecideStyle(ccmAlways, ccdAuto, cbAuto, n.inputs, never) ==
      CliStyle()
    check n.read.len == 0
    # clispec_colors=always: no on/off detection; CliOptions.color = never
    # still applies.
    const always = CliColorConfig(colors: ccmAlways, colorEnv: true,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: true,
      backgroundQuery: true)
    let a = fake({"NO_COLOR": "1", "TERM": "dumb"}, false)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, a.inputs, always) ==
      cliPortable16Style
    check "NO_COLOR" notin a.read
    check cliDecideStyle(ccmNever, ccdAuto, cbAuto, a.inputs, always) ==
      CliStyle()
    # clispec_user_colors off (the default): the variables are not read.
    let o = fake({"TERM": "xterm", "CLISPEC_COLORS": "heading=4"}, true)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, o.inputs) ==
      cliPortable16Style
    check "CLISPEC_COLORS" notin o.read and "DEPOT_COLORS" notin o.read

  test "the developer's palette and the users' overrides":
    const developer = CliColorConfig(colors: ccmAuto, colorEnv: true,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: true,
      backgroundQuery: true, userColors: true,
      palette: "heading=4:tip=")
    var want = cliDark24
    want[ctsHeading] = "4"
    want[ctsTip] = ""
    let f = fake({"TERM": "xterm-256color", "COLORTERM": "truecolor",
      "COLORFGBG": "15;0"}, true)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, f.inputs,
      developer).sgr == want
    # The users' over the developer's, the program's over CLISPEC_COLORS;
    # bad entries ignored one by one; never on or off.
    let g = fake({"TERM": "xterm", "CLISPEC_COLORS":
      "heading=1;33:literal=36:junk:error=red:tip=7",
      "DEPOT_COLORS": "literal=1;32:invalid=:nope=1"}, true)
    var users = cliPortable16
    users[ctsHeading] = "1;33"
    users[ctsLiteral] = "1;32"
    users[ctsTip] = "7"
    users[ctsOffending] = ""
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, g.inputs,
      developer).sgr == users
    let plain = fake({"CLISPEC_COLORS": "heading=1", "NO_COLOR": "1",
      "TERM": "xterm"}, true)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, plain.inputs,
      developer) == CliStyle()
    let empty = fake({"TERM": "xterm", "CLISPEC_COLORS": "",
      "DEPOT_COLORS": ""}, true)
    check cliDecideStyle(ccmAuto, ccdAuto, cbAuto, empty.inputs,
      developer).sgr == cliApply(cliPortable16, CliColorOverrides(
        elements: {ctsHeading, ctsTip}, sgr: ["4", "", "", "", "", ""]))
    check cliProgramColorsVariable("depot") == "DEPOT_COLORS"
    check cliProgramColorsVariable("my-tool.v2") == "MY_TOOL_V2_COLORS"
    var o = CliColorOverrides()
    check cliParseColors("heading=1:bg=light:literal=x:=3:a=b", o).len == 3
    check o.elements == {ctsHeading} and o.background == cbLight

  test "the query's answer, COLORFGBG and the terminals not asked":
    check cliParseBackgroundAnswer(darkAnswer) == cbDark
    check cliParseBackgroundAnswer(lightAnswer) == cbLight
    # 1 to 4 hex digits per channel, BEL or ST.
    check cliParseBackgroundAnswer("\e]11;rgb:0/0/0\a") == cbDark
    check cliParseBackgroundAnswer("\e]11;rgb:ff/ff/ff\e\\") == cbLight
    check cliParseBackgroundAnswer("\e]11;rgb:fff/fff/fff\a") == cbLight
    # No foreground: against 0.5.
    check cliParseBackgroundAnswer("\e]11;rgb:3030/3030/3030\a\e[?1c") ==
      cbDark
    # A dark foreground on a mid-grey background: light.
    check cliParseBackgroundAnswer("\e]11;rgb:8080/8080/8080\a" &
      "\e]10;rgb:1010/1010/1010\a") == cbLight
    # Unparsable: unknown.
    for bad in ["", "\e[?62c", "\e]11;rgb:ffff/ffff\a",
                "\e]11;rgb:fffff/0/0\a", "\e]11;rgb:ffff/ffff/ffff",
                "\e]11;rgba:ffff/ffff/ffff/ffff\a", "\e]11;rgb:gg/00/00\a"]:
      checkpoint(bad.escape)
      check cliParseBackgroundAnswer(bad) == cbUnknown
    check cliColorFgBgBackground("15;0") == cbDark
    check cliColorFgBgBackground("0;8") == cbDark
    check cliColorFgBgBackground("0;7") == cbLight
    check cliColorFgBgBackground("0;15") == cbLight
    check cliColorFgBgBackground("0;16") == cbUnknown
    check cliColorFgBgBackground("default;default") == cbUnknown
    check not cliQueryAllowed("dumb")
    check not cliQueryAllowed("screen")
    check not cliQueryAllowed("screen.xterm-256color")
    check not cliQueryAllowed("tmux-256color")
    check cliQueryAllowed("xterm-256color")

  test "the knobs' builds: fixed policies and inputs switched off":
    # clispec_colors=never: plain on a terminal, even when forced.
    let never = build("never", ["clispec_colors=never"])
    check runCase(never, off("never", onTerm,
      @[("TERM", "xterm-256color"), ("DEPOT_FIXTURE_COLOR", "always")])) == ""
    # clispec_colors=always: styled through a pipe whatever NO_COLOR says.
    let always = build("always", ["clispec_colors=always"])
    check runCase(always, on("always", onPipe, @[("NO_COLOR", "1")])) == ""
    check runCase(always, off("always, color = never", onPipe,
      @[("DEPOT_FIXTURE_COLOR", "never")])) == ""
    # clispec_color_depth=24 and clispec_background=dark: dark, 24-bit
    # with nothing detected, and no query.
    let fixed = build("fixed", ["clispec_color_depth=24",
      "clispec_background=dark"])
    check runCase(fixed, on("fixed", onTerm, @[("TERM", "xterm"),
      ("COLORFGBG", "0;15")], ccd24, cbDark, lightAnswer, false)) == ""
    # clispec_background=unknown: portable16, no query.
    let unknown = build("unknown", ["clispec_background=unknown"])
    check runCase(unknown, on("unknown", onTerm,
      @[("TERM", "xterm-256color"), ("COLORFGBG", "15;0")], ccd16,
      cbUnknown, darkAnswer, false)) == ""
    # clispec_palette: the developer's restyling, at every depth.
    let restyled = build("palette", ["clispec_palette=heading=4;1:tip="])
    var want = cliPortable16Style
    want.sgr[ctsHeading] = "4;1"
    want.sgr[ctsTip] = ""
    let r = throughPipes(restyled, ["build", "-h"],
      [("DEPOT_FIXTURE_COLOR", "always")])
    check r.output == page(80, want)
    want = styled(ccd256, cbLight)
    want.sgr[ctsHeading] = "4;1"
    want.sgr[ctsTip] = ""
    let l = throughPipes(restyled, ["build", "-h"],
      [("DEPOT_FIXTURE_COLOR", "always"), ("DEPOT_FIXTURE_DEPTH", "256"),
       ("DEPOT_FIXTURE_BACKGROUND", "light")])
    check l.output == page(80, want)

  test "a bad define value is a compile-time error naming it":
    if scratch.len == 0:
      scratch = createTempDir("clispec_m5c_detect_", "")
    for (define, words) in [
        ("clispec_colors=sometimes", @["clispec_colors",
          "auto, always, never"]),
        ("clispec_color_env=maybe", @["clispec_color_env", "on, yes"]),
        ("clispec_color_depth=99", @["clispec_color_depth",
          "auto, 16, 256, 24"]),
        ("clispec_background=grey", @["clispec_background",
          "auto, dark, light, unknown"]),
        ("clispec_colorfgbg=2", @["clispec_colorfgbg"]),
        ("clispec_background_query=x", @["clispec_background_query"]),
        ("clispec_user_colors=yes please", @["clispec_user_colors"]),
        ("clispec_palette=heading=red", @["clispec_palette", "heading=red"]),
        ("clispec_palette=title=1", @["clispec_palette", "unknown name"]),
        ("clispec_palette=bg=dark", @["clispec_palette",
          "clispec_background"])]:
      checkpoint(define)
      let (output, code) = nimCommand(compilerExe(), scratch, "check",
        "check", [define])
      check code != 0
      for w in words:
        check w in output
    # The same defines with a valid value compile.
    let (output, code) = nimCommand(compilerExe(), scratch, "check", "check",
      ["clispec_colors=Always", "clispec_color_env=no",
       "clispec_color_depth=256", "clispec_background=light",
       "clispec_colorfgbg=0", "clispec_background_query=none",
       "clispec_user_colors=yes", "clispec_palette=heading=1;4:tip="])
    checkpoint(output)
    check code == 0

  test "negative control: a build that drops a rule fails its cases":
    # The same cases against builds that ignore one input through its
    # knob: exactly the cases that depend on it must now fail.
    proc failing(exe: string): seq[string] =
      for c in cases:
        when defined(windows):
          if c.stream == onTerm:
            continue
        if runCase(exe, c) != "":
          result.add(c.name)
    let noEnv = build("no_env", ["clispec_color_env=off"])
    let envFails = failing(noEnv)
    checkpoint($envFails)
    for name in ["NO_COLOR=1 on a terminal", "FORCE_COLOR=0 on a terminal",
                 "FORCE_COLOR=false on a terminal",
                 "FORCE_COLOR=1 through a pipe",
                 "CLICOLOR_FORCE=1 through a pipe",
                 "CLICOLOR=0 on a terminal",
                 "FORCE_COLOR=2 with a dark COLORFGBG: dark, 256"]:
      when defined(windows):
        if "terminal" in name: continue
      check name in envFails
    check "a pipe is plain" notin envFails
    check "the query answered dark: dark, 256" notin envFails
    let noFgBg = build("no_fgbg", ["clispec_colorfgbg=off"])
    let fgbgFails = failing(noFgBg)
    checkpoint($fgbgFails)
    when not defined(windows):
      check "TERM=xterm-256color, COLORFGBG dark: dark, 256" in fgbgFails
      check "no query when COLORFGBG answered" in fgbgFails
      check "the query answered dark: dark, 256" notin fgbgFails
    check "FORCE_COLOR=2 with a dark COLORFGBG: dark, 256" in fgbgFails
    check "NO_COLOR wins over FORCE_COLOR" notin fgbgFails
    when not defined(windows):
      let noQuery = build("no_query", ["clispec_background_query=off"])
      let queryFails = failing(noQuery)
      checkpoint($queryFails)
      check "the query answered dark: dark, 256" in queryFails
      check "the query answered light: light, 256" in queryFails
      check "the query not answered: portable16 after 100 ms" in queryFails
      check "no query under TERM=screen-256color" notin queryFails
      check "TERM=xterm-256color, COLORFGBG dark: dark, 256" notin queryFails
    # And the decision procs: with the knob off, a case that needs the
    # dropped rule decides otherwise.
    const noEnvConfig = CliColorConfig(colors: ccmAuto, colorEnv: false,
      colorDepth: ccdAuto, background: cbAuto, colorFgBg: true,
      backgroundQuery: true)
    let c = cases.filterIt(it.name == "NO_COLOR=1 on a terminal")[0]
    check decide(c, fake(c.env, true), noEnvConfig) != expected(c)
    check decided(c) == ""

  if scratch.len > 0 and dirExists(scratch):
    removeDir(scratch)
