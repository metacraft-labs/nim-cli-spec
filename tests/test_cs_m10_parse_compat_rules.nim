## test_cs_m10_parse_compat_rules: the opt-in parsing features that let a
## command line keep the behaviour of confutils' type-based loader, each one
## on its own, and each one's absence leaving today's behaviour unchanged.
##
## Every fixture is a real ``cliProgram`` description driven through the
## generated ``load`` (or the parser's phases on the generated grammar where
## the test is about candidates). ``Plain`` declares the same kinds of flags
## with no rule and no new argument, and pins today's answers to exactly the
## command lines the rules change.

import std/[json, options, strutils, unittest]

import clispec

cliProgram(Plain, "plain"):
  flag output is string, short = 'o'
  flag report is string, optionalValue = "on"
  flag attach is string, values = ["early", "late"]
  boolFlag split is bool
  boolFlag color is bool, negatable = true

cliProgram(Cs, "cs"):
  flagMatching ignoreCase
  flag output is string, short = 'o'
  boolFlag verbose is bool, short = 'v'
  boolFlag version is bool, short = 'V'
  boolFlag color is bool, negatable = true
  flag checkpointInterval is int, perSource = [cli = "checkpoint-interval"]

cliProgram(St, "st"):
  flagMatching ignoreStyle
  flag output is string, short = 'o'
  flag checkpointInterval is int, perSource = [cli = "checkpoint-interval"]

cliProgram(Rules, "rules"):
  parsing shortEquals, helpWithAnyValue, helpInCluster,
    valueErrorsBeforeHelp, lenientSwitchValues
  flag output is string, short = 'o', valueName = "path"
  flag jobs is int, short = 'j'
  flag level is Option[int], optionalValue = some(1), acceptsNextWord = true
  flag color is string, values = ["red", "blue"], optionalValue = "red",
    acceptsNextWord = true
  flag report is string, optionalValue = "on"
  boolFlag split is bool, short = 's', refuseFalse = true
  boolFlag keep is bool, short = 'k'
  flag attach is string, values = ["early", "late", "lazy"],
    alsoSets = [attachGiven = "true"]
  boolFlag attachGiven is bool, sources = {}
  boolFlag legacy is bool, alsoSets = [attach = "early"]
  boolFlag pager is bool, negatable = true, alsoSets = [attach = "lazy"]
  flag diag is seq[string]
  boolFlag diagStrict is bool, alsoSets = [diag = "strict"]
  pos rest is seq[string], required = false

cliProgram(Pos, "pos"):
  parsing valueErrorsBeforeHelp
  flag jobs is int, short = 'j'
  pos count is int, default = 0

cliProgram(Getopt, "getopt"):
  parsing colonValues, equalsTakesNext, lenientSwitchValues,
    helpWithAnyValue
  flag output is string, short = 'o'
  flag keepEnv is seq[string]
  flag jobs is int, short = 'j'
  boolFlag split is bool, short = 's', refuseFalse = true
  boolFlag keep is bool, short = 'k'
  flag quiet is int, counted = true, short = 'q'
  boolFlag color is bool, negatable = true
  flag trace is string, values = ["fast", "full"], optionalValue = "fast",
    acceptsNextWord = true
  pos rest is seq[string], required = false

cliProgram(ColonOnly, "colon"):
  parsing colonValues
  flag output is string, short = 'o'
  boolFlag keep is bool, short = 'k'
  pos rest is seq[string], required = false

cliProgram(NextOnly, "next"):
  parsing equalsTakesNext
  flag output is string, short = 'o'
  boolFlag keep is bool, short = 'k'
  pos rest is seq[string], required = false

cliProgram(RefuseAll, "refuse"):
  parsing switchesRefuseFalse
  boolFlag split is bool
  boolFlag keep is bool
  flag output is string

proc usageError(body: proc ()): ref CliUsageError =
  try:
    body()
  except CliUsageError as e:
    return e
  except CliHelpRequest:
    discard
  nil

proc helpAsked(body: proc ()): bool =
  try:
    body()
  except CliHelpRequest:
    return true
  except CliUsageError:
    discard
  false

proc idOf(g: CliGrammar; name: string): int =
  for id, p in g.params:
    if p.name == name:
      return id
  -1

suite "test_cs_m10_parse_compat_rules":

  test "without the rules, today's answers stand":
    check Plain.load(@["-o=v"]).output == "=v"
    check usageError(proc () = discard Plain.load(@["--OUTPUT", "x"])).msg ==
      "unknown flag '--OUTPUT' for 'plain'"
    check usageError(proc () = discard Plain.load(@["-O", "x"])).msg ==
      "unknown flag '-O' for 'plain'"
    check usageError(proc () = discard Plain.load(@["--help=1"])).msg ==
      "unknown flag '--help' for 'plain'"
    check usageError(proc () = discard Plain.load(@["-help"])).msg ==
      "unknown flag '-help' for 'plain'"
    check helpAsked(proc () = discard Plain.load(@["--attach=x", "-h"]))
    check helpAsked(proc () = discard Plain.load(@["extra", "-h"]))
    check Plain.load(@["--split=false"]).split == false
    check Plain.load(@["--split=on"]).split == true
    let empty = usageError(proc () = discard Plain.load(@["--split="]))
    check empty.kind == cekInvalidValue
    check empty.expected == "true or false"
    check usageError(proc () = discard Plain.load(@["--split=y"])).kind ==
      cekInvalidValue
    check usageError(proc () = discard Plain.load(@["--report", "x"])).msg ==
      "unexpected argument 'x' for 'plain'"
    let missing = usageError(proc () = discard Plain.load(@["--output"]))
    check missing.kind == cekMissingValue
    check missing.expected == ""
    # ``:`` attaches nothing, and a trailing ``=`` an empty value.
    check usageError(proc () = discard Plain.load(@["--output:x"])).msg ==
      "unknown flag '--output:x' for 'plain'"
    check Plain.load(@["-o:x"]).output == ":x"
    check Plain.load(@["--output="]).output == ""
    check usageError(proc () = discard Plain.load(@["--output=", "x"])).msg ==
      "unexpected argument 'x' for 'plain'"
    check usageError(proc () = discard Plain.load(@["--split=", "yes"])).kind ==
      cekUnexpectedPositional
    let j = parseJson(Plain.helpJson())
    check j["parsing"] == %*{"flagMatching": "exact", "rules": []}
    for p in j["command"]["parameters"]:
      check p["alsoSets"] == newJArray()
      check p["acceptsNextWord"].getBool == false
      check p["refuseFalse"].getBool == false
      check p["longHelp"].getStr == ""

  test "flagMatching ignoreCase: long and short spellings ignore ASCII case":
    check Cs.load(@["--OUTPUT", "a"]).output == "a"
    check Cs.load(@["-O", "a"]).output == "a"
    check Cs.load(@["-Oa"]).output == "a"
    check Cs.load(@["--CHECKPOINT-INTERVAL", "7"]).checkpointInterval == 7
    check Cs.load(@["--NO-COLOR"]).color == false
    # An exact spelling wins over a case-insensitive one.
    check Cs.load(@["-V"]).version and not Cs.load(@["-V"]).verbose
    check Cs.load(@["-v"]).verbose and not Cs.load(@["-v"]).version
    # Underscores are not ignored in this mode.
    check usageError(proc () = discard Cs.load(@["--out_put", "a"])).msg ==
      "unknown flag '--out_put' for 'cs'"
    check usageError(proc () =
      discard Cs.load(@["--checkpointInterval", "7"])).kind == cekUnknownFlag
    check helpAsked(proc () = discard Cs.load(@["--HELP"]))

  test "flagMatching ignoreStyle: as Nim's cmpIgnoreStyle compares":
    check St.load(@["--Out_Put", "a"]).output == "a"
    check St.load(@["--CHECKPOINT-INTERVAL", "7"]).checkpointInterval == 7
    check St.load(@["--check_point-interval", "7"]).checkpointInterval == 7
    for word in ["--checkpoint_interval", "--checkpointInterval",
                 "--checkpointinterval"]:
      let e = usageError(proc () = discard St.load(@[word, "7"]))
      checkpoint(word)
      check e.kind == cekUnknownFlag
      check e.spelling == word
    # The spelling the word used is what errors name.
    let e = usageError(proc () =
      discard St.load(@["--CHECKPOINT-INTERVAL", "x"]))
    check e.kind == cekInvalidValue
    check e.spelling == "--CHECKPOINT-INTERVAL"
    check parseJson(St.helpJson())["parsing"]["flagMatching"].getStr ==
      "ignoreStyle"

  test "shortEquals: -o=value gives the value":
    check Rules.load(@["-o=t.out"]).output == "t.out"
    check Rules.load(@["-o="]).output == ""
    check Rules.load(@["-ot.out"]).output == "t.out"
    check Rules.load(@["-o", "=x"]).output == "=x"
    check Rules.load(@["-k", "-j=4"]).jobs == 4
    check Rules.load(@["-kj=4"]).jobs == 4
    check Rules.load(@["-k=yes"]).keep
    check Rules.load(@["-k=0"]).keep == false
    let e = usageError(proc () = discard Rules.load(@["-s=off"]))
    check e.kind == cekSwitchFalseValue
    check e.spelling == "-s"
    check e.value == "off"

  test "acceptsNextWord: the next word when it is a valid value":
    check Rules.load(@["--level"]).level == some(1)
    check Rules.load(@["--level", "5"]).level == some(5)
    let r = Rules.load(@["--level", "x"])
    check r.level == some(1)
    check r.rest == @["x"]
    check Rules.load(@["--level=7"]).level == some(7)
    # A word that starts with ``-`` is never taken.
    check usageError(proc () = discard Rules.load(@["--level", "-3"])).msg ==
      "unknown flag '-3' for 'rules'"
    check Rules.load(@["--level", "--", "4"]).level == some(1)
    check Rules.load(@["--level", "--", "4"]).rest == @["4"]
    check Rules.load(@["--color", "blue"]).color == "blue"
    let g = Rules.load(@["--color", "green"])
    check g.color == "red"
    check g.rest == @["green"]
    # Without acceptsNextWord, an optional value stays bare.
    check Rules.load(@["--report", "x"]).report == "on"
    check Rules.load(@["--report", "x"]).rest == @["x"]

  test "acceptsNextWord without a value check uses the closed value set":
    let gr = Rules.cliGrammar
    let t = cliTokenize(gr, @["--color", "blue", "--level", "5"])
    check t.candidates[idOf(gr, "color")][0].text == "blue"
    check t.candidates[idOf(gr, "color")][0].valueArgvIndex == 1
    check t.candidates[idOf(gr, "level")][0].form == ccfBare
    check t.candidates[idOf(gr, "rest")][0].text == "5"

  test "alsoSets: each occurrence is a candidate at the flag's position":
    check Rules.load(@["--legacy", "--attach=lazy"]).attach == "lazy"
    check Rules.load(@["--attach=lazy", "--legacy"]).attach == "early"
    let a = Rules.load(@["--attach=late"])
    check a.attachGiven
    let l = Rules.load(@["--legacy"])
    check l.attach == "early"
    check l.legacy
    check not l.attachGiven
    check Rules.load(@["--diag=a", "--diagStrict", "--diag=b",
      "--diagStrict"]).diag == @["a", "strict", "b", "strict"]
    # A switch set to false, or negated, supplies nothing.
    check Rules.load(@["--attach=late", "--pager=false"]).attach == "late"
    check Rules.load(@["--attach=late", "--no-pager"]).attach == "late"
    check Rules.load(@["--attach=late", "--pager"]).attach == "lazy"
    let gr = Rules.cliGrammar
    let t = cliTokenize(gr, @["-k", "--legacy", "--attach", "late"])
    let cands = t.candidates[idOf(gr, "attach")]
    check cands.len == 2
    check cands[0].text == "early"
    check cands[0].argvIndex == 1
    check cands[0].spelling == "--legacy"
    check cands[0].setBy == "legacy"
    check cands[1].text == "late"
    check cands[1].setBy == ""
    let given = t.candidates[idOf(gr, "attachGiven")]
    check given.len == 1
    check given[0].setBy == "attach"
    check given[0].argvIndex == 2

  test "sources = {}: no spelling, no help row, set only through alsoSets":
    let e = usageError(proc () = discard Rules.load(@["--attachGiven"]))
    check e.kind == cekUnknownFlag
    check "attachGiven" notin Rules.helpText()
    for p in parseJson(Rules.helpJson())["command"]["parameters"]:
      check p["name"].getStr != "attachGiven"

  test "refuseFalse: a false value is its own error kind":
    for v in ["false", "off", "no", "0", "N", "Off"]:
      let e = usageError(proc () = discard Rules.load(@["--split=" & v]))
      checkpoint(v)
      check e.kind == cekSwitchFalseValue
      check e.spelling == "--split"
      check e.value == v
      check e.argvIndex == 0
    check Rules.load(@["--split=true"]).split
    check Rules.load(@["--split=on"]).split
    check Rules.load(@["--split"]).split
    let bad = usageError(proc () = discard Rules.load(@["--split=maybe"]))
    check bad.kind == cekInvalidValue
    check bad.value == "maybe"
    # Only the switch that declares it refuses.
    check Rules.load(@["--keep=false"]).keep == false

  test "switchesRefuseFalse: every switch refuses a false value":
    for flag in ["--split", "--keep"]:
      let e = usageError(proc () = discard RefuseAll.load(@[flag & "=no"]))
      checkpoint(flag)
      check e.kind == cekSwitchFalseValue
      check e.msg == "switch '" & flag & "' of 'refuse' takes no false " &
        "value (got '" & flag & "=no'); it is on when given and off " &
        "when omitted"
    check RefuseAll.load(@["--keep=yes"]).keep
    # Without lenientSwitchValues, the spellings are parseCliValue's.
    check usageError(proc () = discard RefuseAll.load(@["--keep=y"])).kind ==
      cekInvalidValue
    check usageError(proc () = discard RefuseAll.load(@["--keep="])).kind ==
      cekInvalidValue
    let j = parseJson(RefuseAll.helpJson())
    check j["parsing"]["rules"] == %*["switchesRefuseFalse"]
    for p in j["command"]["parameters"]:
      check p["refuseFalse"].getBool == (p["name"].getStr != "output")

  test "lenientSwitchValues: parseBool's spellings, empty is true":
    check Rules.load(@["--keep="]).keep
    check Rules.load(@["--keep=Y"]).keep
    check Rules.load(@["--keep=Y_E_S"]).keep
    check Rules.load(@["--keep=n"]).keep == false
    check Rules.load(@["--split="]).split
    let e = usageError(proc () = discard Rules.load(@["--keep=maybe"]))
    check e.kind == cekInvalidValue
    check e.value == "maybe"

  test "helpWithAnyValue and helpInCluster":
    check helpAsked(proc () = discard Rules.load(@["--help=1"]))
    check helpAsked(proc () = discard Rules.load(@["--help=true"]))
    check helpAsked(proc () = discard Rules.load(@["--help=false"]))
    check helpAsked(proc () = discard Rules.load(@["-help"]))
    check helpAsked(proc () = discard Rules.load(@["-kh"]))
    try:
      discard Rules.load(@["--help=json"])
      check false
    except CliHelpRequest as h:
      check h.json
    # ``h`` in a cluster after a letter that takes the rest of the word is
    # that letter's value.
    check Rules.load(@["-oh"]).output == "h"

  test "valueErrorsBeforeHelp: an earlier rejected value wins over help":
    let e = usageError(proc () =
      discard Rules.load(@["-j", "x", "--attach=bogus", "-h"]))
    check e.kind == cekInvalidValue
    check e.spelling == "-j"
    check e.value == "x"
    check e.argvIndex == 1
    check e.msg == "invalid value 'x' for '-j' of 'rules'; expected an " &
      "integer"
    let s = usageError(proc () =
      discard Rules.load(@["--attach=bogus", "--help"]))
    check s.msg == "invalid value 'bogus' for '--attach' of 'rules'; " &
      "expected one of: early, late, lazy"
    # A value after the help request is not looked at.
    check helpAsked(proc () = discard Rules.load(@["-h", "--attach=bogus"]))
    # An overridden earlier value is still a value that was written.
    check usageError(proc () = discard Rules.load(@["--attach=bogus",
      "--attach=late", "-h"])).value == "bogus"
    # A bare word before the help request that no positional accepts, or
    # that its positional rejects, is reported as it would be without the
    # help request.
    let extra = usageError(proc () = discard Pos.load(@["5", "extra", "-h"]))
    check extra.kind == cekUnexpectedPositional
    check extra.spelling == "extra"
    check extra.argvIndex == 1
    check extra.msg == usageError(proc () =
      discard Pos.load(@["5", "extra"])).msg
    let word = usageError(proc () = discard Pos.load(@["x", "--help"]))
    check word.kind == cekInvalidValue
    check word.value == "x"
    check word.argvIndex == 0
    check word.msg == usageError(proc () = discard Pos.load(@["x"])).msg
    # The earliest of a flag's value and a bare word is reported.
    check usageError(proc () =
      discard Pos.load(@["-j", "y", "extra", "-h"])).spelling == "-j"
    check usageError(proc () =
      discard Pos.load(@["extra", "-j", "y", "-h"])).kind ==
        cekInvalidValue
    check usageError(proc () =
      discard Pos.load(@["5", "6", "-j", "y", "-h"])).kind ==
        cekUnexpectedPositional
    check helpAsked(proc () = discard Pos.load(@["5", "-h", "extra"]))
    check helpAsked(proc () = discard Pos.load(@["5", "-h"]))
    # Which positional a word fills before a list positional is not known
    # until the command line is read, so those words do not stop help.
    check helpAsked(proc () = discard Rules.load(@["x", "-h"]))
    # Without a value check (the parser called directly), help wins.
    check helpAsked(proc () =
      discard cliTokenize(Rules.cliGrammar, @["--attach=bogus", "-h"]))

  test "a missing value names the declared placeholder":
    let e = usageError(proc () = discard Rules.load(@["--output"]))
    check e.kind == cekMissingValue
    check e.expected == "path"
    check e.msg == "flag '--output' of 'rules' needs a value"
    check usageError(proc () = discard Rules.load(@["-o"])).expected == "path"
    check usageError(proc () = discard Rules.load(@["--jobs"])).expected == ""

  # The expected answers below are what confutils' getopt (the fork at
  # 331c5fa, ``load(..., negatableSwitches = false)``) gives for the
  # equivalent options.

  test "colonValues: --name:value and -o:value":
    check Getopt.load(@["--output:t.out"]).output == "t.out"
    check Getopt.load(@["--output:"]).output == ""
    check Getopt.load(@["--output:a=b"]).output == "a=b"
    check Getopt.load(@["--output=a:b"]).output == "a:b"
    check Getopt.load(@["--output::x"]).output == ":x"
    check Getopt.load(@["-o:t.out"]).output == "t.out"
    check Getopt.load(@["-o:"]).output == ""
    check Getopt.load(@["-o::x"]).output == ":x"
    check Getopt.load(@["-k", "-j:4"]).jobs == 4
    check Getopt.load(@["-kj:4"]).jobs == 4
    check Getopt.load(@["-k:yes"]).keep
    check Getopt.load(@["-k:0"]).keep == false
    check Getopt.load(@["--keep:true"]).keep
    check Getopt.load(@["--keep:"]).keep
    check Getopt.load(@["--trace:full"]).trace == "full"
    check Getopt.load(@["--keepEnv:A", "--keepEnv=B"]).keepEnv == @["A", "B"]
    let f = usageError(proc () = discard Getopt.load(@["--split:off"]))
    check f.kind == cekSwitchFalseValue
    check f.spelling == "--split"
    check f.value == "off"
    check usageError(proc () = discard Getopt.load(@["-q:1"])).kind ==
      cekInvalidValue
    check usageError(proc () = discard Getopt.load(@["--no-color:x"])).kind ==
      cekInvalidValue
    let u = usageError(proc () = discard Getopt.load(@["--bogus:1"]))
    check u.kind == cekUnknownFlag
    check u.spelling == "--bogus"
    check helpAsked(proc () = discard Getopt.load(@["--help:1"]))
    try:
      discard Getopt.load(@["--help:json"])
      check false
    except CliHelpRequest as h:
      check h.json
    # A flag's value is taken verbatim, whatever it looks like.
    check Getopt.load(@["-o", "--x:y"]).output == "--x:y"
    check Getopt.load(@["--output", "--x:y"]).output == "--x:y"
    check Getopt.load(@["-o", "-o:z"]).output == "-o:z"
    check Getopt.load(@["--keepEnv", "--A:B"]).keepEnv == @["--A:B"]
    # After ``--`` every word is a positional.
    check Getopt.load(@["--", "--output:x"]).rest == @["--output:x"]
    # Under colonValues alone, a trailing ``:`` is an empty value.
    check ColonOnly.load(@["--output:"]).output == ""
    let c = ColonOnly.load(@["--output:", "x"])
    check c.output == ""
    check c.rest == @["x"]
    check ColonOnly.load(@["-o:x"]).output == "x"
    let gr = Getopt.cliGrammar
    let t = cliTokenize(gr, @["-k", "--output:a"])
    let cand = t.candidates[idOf(gr, "output")][0]
    check cand.spelling == "--output"
    check cand.text == "a"
    check cand.argvIndex == 1
    check cand.valueArgvIndex == -1

  test "equalsTakesNext: --name= value":
    check Getopt.load(@["--output=", "t.out"]).output == "t.out"
    check Getopt.load(@["--output:", "t.out"]).output == "t.out"
    check Getopt.load(@["--output="]).output == ""
    check Getopt.load(@["--output:"]).output == ""
    # A word starting with ``-`` is not taken; an empty word is.
    let x = usageError(proc () = discard Getopt.load(@["--output=", "-x"]))
    check x.kind == cekUnknownFlag
    check x.spelling == "-x"
    let s = Getopt.load(@["--output=", "--keep"])
    check s.output == ""
    check s.keep
    let e = Getopt.load(@["--output=", ""])
    check e.output == ""
    check e.rest.len == 0
    let ab = Getopt.load(@["--output=", "a", "b"])
    check ab.output == "a"
    check ab.rest == @["b"]
    check Getopt.load(@["--output=", "a=b"]).output == "a=b"
    check Getopt.load(@["--keepEnv=", "A", "--keepEnv:B", "--keepEnv:",
      "C"]).keepEnv == @["A", "B", "C"]
    # A switch's explicit value.
    check Getopt.load(@["--keep=", "yes"]).keep
    check Getopt.load(@["--keep=", "no"]).keep == false
    let no = usageError(proc () = discard Getopt.load(@["--split=", "no"]))
    check no.kind == cekSwitchFalseValue
    check no.value == "no"
    let maybe = usageError(proc () =
      discard Getopt.load(@["--split=", "maybe"]))
    check maybe.kind == cekInvalidValue
    check maybe.value == "maybe"
    let st = Getopt.load(@["--split:", "--trace"])
    check st.split
    check st.trace == "fast"
    # An optional value.
    check Getopt.load(@["--trace=", "full"]).trace == "full"
    let tb = usageError(proc () = discard Getopt.load(@["--trace=", "bogus"]))
    check tb.kind == cekInvalidValue
    check tb.value == "bogus"
    check usageError(proc () = discard Getopt.load(@["--trace="])).value == ""
    # Unknown flags and help.
    let ub = usageError(proc () = discard Getopt.load(@["--bogus=", "x"]))
    check ub.kind == cekUnknownFlag
    check ub.spelling == "--bogus"
    check helpAsked(proc () = discard Getopt.load(@["--help=", "x"]))
    check helpAsked(proc () = discard Getopt.load(@["--help:"]))
    check helpAsked(proc () = discard Getopt.load(@["--output=", "x", "-h"]))
    # The value of the flag before is never read as a flag.
    let v = Getopt.load(@["--output", "--a=", "b"])
    check v.output == "--a="
    check v.rest == @["b"]
    check Getopt.load(@["--output", "--a:", "b"]).output == "--a:"
    # A short flag never takes the next word after ``=`` or ``:``.
    let sh = Getopt.load(@["-o:", "t.out"])
    check sh.output == ""
    check sh.rest == @["t.out"]
    # After ``--``, nothing is joined.
    check Getopt.load(@["--", "--output=", "x"]).rest == @["--output=", "x"]
    # The candidate records where its value came from.
    let gr = Getopt.cliGrammar
    let t = cliTokenize(gr, @["-k", "--output=", "a", "--keep=", "on"])
    let o = t.candidates[idOf(gr, "output")][0]
    check o.text == "a"
    check o.spelling == "--output"
    check o.argvIndex == 1
    check o.valueArgvIndex == 2
    let k = t.candidates[idOf(gr, "keep")]
    check k[1].text == "true"
    check k[1].argvIndex == 3
    check k[1].valueArgvIndex == 4
    # Under equalsTakesNext alone, ``:`` attaches nothing.
    check NextOnly.load(@["--output=", "x"]).output == "x"
    check usageError(proc () = discard NextOnly.load(@["--output:", "x"])).msg ==
      "unknown flag '--output:' for 'next'"
    check NextOnly.load(@["-o:x"]).output == ":x"

  test "completion under colonValues and equalsTakesNext":
    proc values(cs: seq[CliCompletion]): seq[string] =
      for c in cs:
        result.add(c.value)
    check values(Getopt.complete(@["--trace:f"])) ==
      @["--trace:fast", "--trace:full"]
    check values(Getopt.complete(@["--trace=", ""])) == @["fast", "full"]
    check values(Getopt.complete(@["--trace:", "fu"])) == @["full"]
    check values(Getopt.complete(@["--keep=", ""])) == @["true", "false"]
    check values(Getopt.complete(@["--trace=", "--ou"])) == @["--output"]
    check values(Getopt.complete(@["--bogus=", ""])).len == 0
    # A taken value is skipped; one that starts with ``-`` is a flag.
    check values(Getopt.complete(@["--output=", "x", "--tr"])) ==
      @["--trace"]
    check values(Getopt.complete(@["--output=", "--keep", "--trace", ""])) ==
      @["fast", "full"]
    # The value of the flag before is not read as ``--name=``.
    check values(Getopt.complete(@["--output", "--keep=", ""])).len == 0
    # Without equalsTakesNext, the word after ``--keep=`` is a positional.
    check values(ColonOnly.complete(@["--keep=", ""])).len == 0
    check values(ColonOnly.complete(@["--keep:"])) == @["--keep:true",
      "--keep:false"]

  test "the help request carries the layout CliOptions names":
    try:
      discard Rules.load(@["-h"], CliOptions(helpLayout: CliHelpLayout(
        column: 40, helpFlag: "Show this help")))
      check false
    except CliHelpRequest as h:
      check h.text == Rules.helpText(layout = CliHelpLayout(column: 40,
        helpFlag: "Show this help"))
      check "  -h, --help" & repeat(' ', 28) & "Show this help\n" in h.text

  test "completion: the word after a bare acceptsNextWord flag":
    var values: seq[string] = @[]
    for c in Rules.complete(@["--color", ""]):
      values.add(c.value)
    check values == @["red", "blue"]
    # A taken value is skipped like any flag's value; a word that is not
    # one is the positional it would have been.
    values = @[]
    for c in Rules.complete(@["--color", "blue", "--ou"]):
      values.add(c.value)
    check values == @["--output"]

  test "the model and the JSON record the new declarations":
    let m = Rules.cliModel
    check m.parseRules == {cprShortEquals, cprHelpWithAnyValue,
      cprHelpInCluster, cprValueErrorsBeforeHelp, cprLenientSwitchValues}
    check Cs.cliModel.flagMatching == cfmIgnoreCase
    var byName: seq[string] = @[]
    for p in m.root.params:
      byName.add(p.name)
      case p.name
      of "output": check p.valueName == "path"
      of "level": check p.acceptsNextWord
      of "split": check p.refuseFalse
      of "attach":
        check p.alsoSets == @[CliAlsoSet(param: "attachGiven",
          text: "true")]
      of "attachGiven": check p.sources == {}
      else: discard
    check "attachGiven" in byName
    let j = parseJson(Rules.helpJson())
    check j["parsing"]["rules"] == %*["shortEquals", "helpWithAnyValue",
      "helpInCluster", "valueErrorsBeforeHelp", "lenientSwitchValues"]
    check Getopt.cliModel.parseRules == {cprHelpWithAnyValue,
      cprLenientSwitchValues, cprColonValues, cprEqualsTakesNext}
    check parseJson(Getopt.helpJson())["parsing"]["rules"] == %*[
      "helpWithAnyValue", "lenientSwitchValues", "colonValues",
      "equalsTakesNext"]
    for p in j["command"]["parameters"]:
      case p["name"].getStr
      of "output": check p["placeholder"].getStr == "path"
      of "jobs": check p["placeholder"].getStr == "int"
      of "color": check p["placeholder"].getStr == "red|blue"
      of "level": check p["acceptsNextWord"].getBool
      of "split": check p["refuseFalse"].getBool
      of "keep": check not p["refuseFalse"].getBool
      of "legacy":
        check p["alsoSets"] == %*[{"param": "attach", "value": "early"}]
      else: discard
