## test_cs_m5_engine_completes_every_level: the completion engine generated
## for a fixture command tree offers exactly the right candidates at every
## kind of word position: subcommand words and aliases at each level, flag
## spellings (long, negated, alias, short, ``--flag=`` for an ``equals``
## flag), values of closed sets and enums, a ``complete`` completer's
## dynamic values (with the context it is called with), ``--flag=<partial>``
## words, list elements after a separator, the word after a flag that takes
## the next word, an optional-value flag that does not, short-flag clusters,
## positionals in order, and the words after ``--``. Visibility is checked
## too: hidden items and internal parameters are never offered, an internal
## subcommand only inside its namespace.
##
## Every comparison is against the exact sequence of candidates (values and
## descriptions), never "contains", so an extra or a missing candidate
## fails. The second suite checks the protocol answer the shell scripts
## read (``completionReply``): its per-shell line format, bash's reading of
## the raw command line and its quoting, PowerShell's encoded words and
## quoting, and the request raised from ``load``. The third checks, on any
## OS, the command line the end-to-end test runs PowerShell with
## (``tests/powershell_driver.nim``): no script file, so no execution
## policy can refuse it on Windows.
##
## The engine runs on the grammar the real ``cliProgram`` macro generated
## from a real description; the completers are ordinary procs of this file.
## Nothing is mocked.

import std/[base64, strutils, unicode, unittest]

import clispec
import ./powershell_driver

type
  Mode = enum
    debug, release

var lastContext: CliCompletionContext
  ## The context the last call of ``remoteNames`` received.

proc remoteNames(ctx: CliCompletionContext): seq[CliCompletion] =
  ## A dynamic completer: three names, one with a description. It lists
  ## everything; the engine keeps those that start with the prefix.
  lastContext = ctx
  @[CliCompletion(value: "origin", description: "the default remote"),
    CliCompletion(value: "upstream"), CliCompletion(value: "other")]

proc failing(ctx: CliCompletionContext): seq[CliCompletion] =
  ## A completer that fails: the engine offers nothing for it.
  raise newException(IOError, "cannot list")

proc spaced(ctx: CliCompletionContext): seq[CliCompletion] =
  ## Values a shell must quote, and one that cannot be offered.
  @[CliCompletion(value: "my file.txt"), CliCompletion(value: "it's"),
    CliCompletion(value: "two\nlines"),
    CliCompletion(value: "$HOME", description: "a\tdollar\nsign")]

proc accented(ctx: CliCompletionContext): seq[CliCompletion] =
  ## Non-ASCII values, one holding PowerShell's typographic quotes.
  @[CliCompletion(value: "\u00FCber"),
    CliCompletion(value: "caf\u00E9 \u2018x\u2019")]

cliProgram(Fx, "fx"):
  help "A completion fixture"
  boolFlag verbose is bool, short = 'v', negatable = true, help = "Talk more"
  flag color is string, values = ["auto", "always", "never"],
    format = equals, help = "When to color"
  flag trace is string, visibility = internal, help = "Trace to a file"
  flag token is string, visibility = hidden
  subcmd "build", help = "Build a project", aliases = ["b", "make"]:
    flag jobs is int, short = 'j', help = "Parallel jobs"
    flag mode is Mode, help = "Build mode"
    flag report is string, optionalValue = "report.json",
      help = "Write a report"
    flag tags is seq[string], separator = ",",
      values = ["fast", "safe", "small"]
    flag define is seq[string], alias = "-D", format = concat
    flag remote is string, complete = remoteNames, help = "A remote"
    flag level is int, format = equals
    flag note is string, complete = spaced
    flag graph is string, visibility = internal
    pos target is string, values = ["app", "lib", "all"]
    pos extra is seq[string], repeated = true, required = false,
      complete = remoteNames
  subcmd "remote", help = "Remotes":
    subcmd "add", help = "Add a remote":
      flag broken is string, complete = failing
      flag label is string, complete = accented
      pos name is string, complete = remoteNames
    subcmd "remove", aliases = ["rm"]:
      pos name is string
    call(help = "List remotes"):
      boolFlag long is bool, short = 'l', help = "Long listing"
  subcmd "internal", visibility = internal, help = "Debugging":
    subcmd "dump", help = "Dump state":
      boolFlag deep is bool
    subcmd "probe", visibility = internal, help = "Probe":
      boolFlag all is bool
    subcmd "secret", visibility = hidden:
      boolFlag all is bool
  subcmd "ghost", visibility = hidden:
    pos x is string

proc values(cs: seq[CliCompletion]): seq[string] =
  for c in cs:
    result.add(c.value)

proc at(words: varargs[string]): seq[string] =
  ## The candidates for the last word of ``words``.
  values(Fx.complete(@words))

suite "test_cs_m5_engine_completes_every_level":

  test "subcommands at the root, with descriptions":
    check Fx.complete(@[""]) == @[
      CliCompletion(value: "build", description: "Build a project"),
      CliCompletion(value: "remote", description: "Remotes")]
    check Fx.complete(@[]) == Fx.complete(@[""])

  test "a subcommand by prefix, an alias when the name does not match":
    check at("b") == @["build"]
    check at("m") == @["make"]
    check at("re") == @["remote"]
    check at("x").len == 0

  test "internal subcommands only inside their namespace, hidden never":
    check at("i").len == 0
    check at("g").len == 0
    check at("internal", "") == @["dump", "probe"]
    check at("internal", "s").len == 0
    check at("remote", "") == @["add", "remove"]
    check at("remote", "rm") == @["rm"]

  test "flags: every spelling, help last, internal and hidden never":
    check at("-") == @["--verbose", "--no-verbose", "-v", "--color=",
      "--help", "-h"]
    check at("--") == @["--verbose", "--no-verbose", "--color=", "--help"]
    check at("--t").len == 0
    check at("--no") == @["--no-verbose"]
    check Fx.complete(@["--v"]) == @[
      CliCompletion(value: "--verbose", description: "Talk more")]
    check at("build", "--") == @["--verbose", "--no-verbose", "--color=",
      "--jobs", "--mode", "--report", "--tags", "--define", "--remote",
      "--level=", "--note", "--help"]
    check at("build", "--g").len == 0
    check at("b", "-j") == @["-j"]

  test "flags of a command and of its call: together":
    check at("remote", "-") == @["--verbose", "--no-verbose", "-v",
      "--color=", "--long", "-l", "--help", "-h"]

  test "--help is not offered when the program turns it off":
    check values(Fx.complete(@["--h"],
      options = CliOptions(disableHelpFlag: true))).len == 0

  test "enum and closed-set values after a flag that takes the next word":
    check at("build", "--mode", "") == @["debug", "release"]
    check at("build", "--mode", "r") == @["release"]
    check at("b", "--mode", "") == @["debug", "release"]
    check at("build", "-j", "").len == 0

  test "values written as --flag=<partial>":
    check at("--color=") == @["--color=auto", "--color=always",
      "--color=never"]
    check at("--color=a") == @["--color=auto", "--color=always"]
    check at("build", "--mode=d") == @["--mode=debug"]
    check at("build", "--verbose=") == @["--verbose=true", "--verbose=false"]
    check at("build", "--level=").len == 0

  test "list elements after a separator":
    check at("build", "--tags", "fast,s") == @["fast,safe", "fast,small"]
    check at("build", "--tags=s") == @["--tags=safe", "--tags=small"]

  test "a dynamic completer, and the context it receives":
    check Fx.complete(@["build", "--remote", ""]) == @[
      CliCompletion(value: "origin", description: "the default remote"),
      CliCompletion(value: "upstream"), CliCompletion(value: "other")]
    check lastContext.program == "fx"
    check lastContext.param == "remote"
    check lastContext.commandPath == @["build"]
    check lastContext.words == @["build", "--remote"]
    check lastContext.prefix == ""
    check at("build", "--remote=o") == @["--remote=origin", "--remote=other"]
    check lastContext.prefix == "o"
    check at("remote", "add", "u") == @["upstream"]
    check lastContext.commandPath == @["remote", "add"]
    check lastContext.param == "name"

  test "a completer that raises offers nothing":
    check at("remote", "add", "--broken", "").len == 0
    check at("remote", "add", "--broken=").len == 0

  test "an optional-value flag never takes the next word":
    check at("build", "--report", "") == @["app", "lib", "all"]

  test "positionals in order; a list positional takes the rest":
    check at("build", "") == @["app", "lib", "all"]
    check at("build", "a") == @["app", "all"]
    check at("build", "app", "") == @["origin", "upstream", "other"]
    check at("build", "app", "x", "u") == @["upstream"]
    check at("build", "-v", "--jobs", "4", "app", "o") == @["origin", "other"]

  test "short clusters: the last letter's value is the next word":
    check at("build", "-vj", "").len == 0
    check at("build", "-vj", "4", "") == @["app", "lib", "all"]
    check at("build", "-vj4", "") == @["app", "lib", "all"]

  test "after --, only positionals":
    check at("build", "--", "") == @["app", "lib", "all"]
    check at("build", "--", "a") == @["app", "all"]
    check at("build", "--", "-").len == 0

  test "an internal parameter the user typed still gets its values":
    check at("build", "--graph", "").len == 0
    check at("--trace", "").len == 0
    check at("--trace", "x", "") == @["build", "remote"]

  test "the cursor in the middle of the words":
    check values(Fx.complete(@["build", "--m", "release"], cursor = 1)) ==
      @["--mode"]
    check values(Fx.complete(@["build"], cursor = 1)) ==
      values(Fx.complete(@["build", ""]))

suite "test_cs_m5_engine_completes_every_level: the protocol":

  proc ps(words: varargs[string]): seq[string] =
    result = @["powershell"]
    for w in words:
      result.add(":" & encode(w))

  test "zsh and fish: value<TAB>description per line":
    check Fx.completionReply(@["zsh", ""]) ==
      "build\tBuild a project\nremote\tRemotes\n"
    check Fx.completionReply(@["fish", "build", "--mode", ""]) ==
      "debug\nrelease\n"
    check Fx.completionReply(@["fish", "zzz"]) == ""

  test "line breaks never reach the answer":
    check Fx.completionReply(@["zsh", "build", "--note", ""]) ==
      "my file.txt\nit's\n$HOME\ta dollar sign\n"

  test "bash: the raw line, word breaks and quoting":
    const breaks = "\"'><=;|&(:"
    check Fx.completionReply(@["bash", breaks, "fx bu"]) == "build\n"
    check Fx.completionReply(@["bash", breaks, "fx build --mode=d"]) ==
      "debug\n"
    check Fx.completionReply(@["bash", " ", "fx build --mode=d"]) ==
      "--mode=debug\n"
    check Fx.completionReply(@["bash", breaks, "fx build --note my"]) ==
      "my\\ file.txt\n"
    check Fx.completionReply(@["bash", breaks, "fx build --note 'my"]) ==
      "my file.txt\n"
    check Fx.completionReply(@["bash", breaks, "fx build --note \"my"]) ==
      "my file.txt\n"
    check Fx.completionReply(@["bash", breaks, "fx build --note my\\ "]) ==
      "my\\ file.txt\n"
    check Fx.completionReply(@["bash", breaks, "fx build --note "]) ==
      "my\\ file.txt\nit\\'s\n\\$HOME\n"
    check Fx.completionReply(@["bash", breaks, "fx build --note 'i"]) == ""
    check Fx.completionReply(@["bash", breaks,
      "echo hi; fx remote r"]) == "remove\n"
    check Fx.completionReply(@["bash", breaks, "fx  remote  "]) ==
      "add\nremove\n"
    # A word mixing closed quotes and escapes is replaced whole.
    check Fx.completionReply(@["bash", breaks, "fx build --note m'y '"]) ==
      "my\\ file.txt\n"
    check Fx.completionReply(@["bash", breaks, "fx build --note \"m\"y\\ f"]) ==
      "my\\ file.txt\n"
    # After the last word break, the earlier quoted part is kept.
    check Fx.completionReply(@["bash", breaks,
      "fx build --note='my' --mode=r"]) == "release\n"
    check Fx.completionReply(@["bash", breaks, "fx build '--mode'=r"]) ==
      "release\n"
    check Fx.completionReply(@["bash", breaks, "fx re\\\nmo"]) ==
      "remote\n"

  test "bash: reading the command line with POSIX quoting":
    check cliReadShellLine("fx 'a b'\"c\\\"d\"e\\ f g").words ==
      @["fx", "a bc\"de f", "g"]
    check cliReadShellLine("fx \"\\$x\\y\" '\\n'").words ==
      @["fx", "$x\\y", "\\n"]
    check cliReadShellLine("fx re\\\nmote ").words == @["fx", "remote", ""]
    check cliReadShellLine("fx a \\\n").words == @["fx", "a", ""]
    check cliReadShellLine("a | fx x>out y").words == @["fx", "x", "out", "y"]
    let open = cliReadShellLine("fx --note=\"my f")
    check open.words == @["fx", "--note=my f"]
    check open.raw == "--note=\"my f"
    check open.openQuote == 7

  test "powershell: encoded words, quoted completion text":
    check Fx.completionReply(ps("bu")) == "build\tbuild\tBuild a project\n"
    check Fx.completionReply(ps("build", "--note", "my")) ==
      "'my file.txt'\tmy file.txt\tmy file.txt\n"
    check Fx.completionReply(ps("build", "--note", "i")) ==
      "'it''s'\tit's\tit's\n"
    check Fx.completionReply(@["powershell", "YnU="]) == ""
    # Non-ASCII words arrive as UTF-8 and come back unchanged; PowerShell's
    # typographic quotes are doubled inside the quoted completion text.
    check Fx.completionReply(ps("remote", "add", "--label", "\u00FC")) ==
      "\u00FCber\t\u00FCber\t\u00FCber\n"
    check Fx.completionReply(ps("remote", "add", "--label", "c")) ==
      "'caf\u00E9 \u2018\u2018x\u2019\u2019'\tcaf\u00E9 \u2018x\u2019\t" &
      "caf\u00E9 \u2018x\u2019\n"
    check Fx.completionReply(ps("remote", "add", "--label", "")) ==
      "\u00FCber\t\u00FCber\t\u00FCber\n" &
      "'caf\u00E9 \u2018\u2018x\u2019\u2019'\tcaf\u00E9 \u2018x\u2019\t" &
      "caf\u00E9 \u2018x\u2019\n"
    check Fx.completionReply(@["powershell", ":!!"]) == ""

  test "malformed requests get an empty answer":
    check Fx.completionReply(@[]) == ""
    check Fx.completionReply(@["tcsh", "x"]) == ""
    check Fx.completionReply(@["bash", "="]) == ""

  test "load raises the request, as a help request":
    var answered = ""
    try:
      discard Fx.load(@["__complete", "fish", "re"])
    except CliCompletionRequest as e:
      answered = e.text
      check e.shell == "fish"
    check answered == "remote\tRemotes\n"
    var asHelp = false
    try:
      discard Fx.load(@["__complete", "zsh", ""])
    except CliHelpRequest as e:
      asHelp = e.text.startsWith("build\t")
    check asHelp

  test "the entry word is the consumer's to choose or turn off":
    var answered = ""
    try:
      discard Fx.load(@["--complete-me", "zsh", "re"],
        CliOptions(completionEntry: "--complete-me"))
    except CliCompletionRequest as e:
      answered = e.text
    check answered == "remote\tRemotes\n"
    expect CliUsageError:
      discard Fx.load(@["__complete", "zsh", "re"],
        CliOptions(disableCompletionEntry: true))

  test "every shell's script runs the program with the entry word":
    for shell in CliShell:
      let script = Fx.completionScript(shell)
      checkpoint($shell & ":\n" & script)
      check "fx" in script
      check "__complete" in script
      check $shell in script
    check "command 'my tool' 'x y' bash" in cliCompletionScript(cshBash,
      "my tool", options = CliOptions(completionEntry: "x y"))
    check "& 'it''s' '__complete' powershell" in cliCompletionScript(
      cshPowerShell, "it's")
    check "& 'a\u2019\u2019b' '__complete' powershell" in
      cliCompletionScript(cshPowerShell, "a\u2019b")
    # Placeholders are filled in one pass: a value holding placeholder
    # text is not substituted again.
    check "command '$NAME' __complete bash" in cliCompletionScript(cshBash,
      "x", command = "$NAME")
    # The program name in the comments cannot end a comment line.
    for shell in CliShell:
      check "completion for a rm -rf b, generated" in
        cliCompletionScript(shell, "a\nrm -rf b")

func fromUtf16le(bytes: string): string =
  ## The inverse of ``utf16le``, written independently of it.
  var i = 0
  while i + 1 < bytes.len:
    var unit = ord(bytes[i]) or (ord(bytes[i + 1]) shl 8)
    i += 2
    if unit in 0xD800 .. 0xDBFF and i + 1 < bytes.len:
      let low = ord(bytes[i]) or (ord(bytes[i + 1]) shl 8)
      i += 2
      unit = 0x10000 + ((unit - 0xD800) shl 10) + (low - 0xDC00)
    result.add($Rune(unit))

suite "the end-to-end PowerShell driver":

  test "it runs no script file, so no execution policy refuses it":
    # Windows' default client policy (Restricted) refuses every script
    # file, a -File driver and a dot-sourced .ps1 included; a command
    # (-EncodedCommand, Invoke-Expression) is not a script file.
    let lines = ["shx ", "shx build --note \u00FC", "shx build --note 'my",
      "x \u{1F600}"]
    let program = tabExpansionProgram("C:\\it's\\shx.exe", lines)
    let args = powerShellDriverArgs(program)
    check args.len == 4
    check args[0 .. 2] == @["-NoProfile", "-NonInteractive",
      "-EncodedCommand"]
    for a in args:
      check a.toLowerAscii notin ["-file", "-f", "-executionpolicy"]
    check fromUtf16le(decode(args[3])) == program
    check "& 'C:\\it''s\\shx.exe' completion powershell | Out-String | " &
      "Invoke-Expression\n" in program
    check ".ps1" notin program
    check "\n. " notin program
    check "TabExpansion2 -inputScript 'shx build --note ''my' " &
      "-cursorColumn 20\n" in program
    check "-inputScript 'shx build --note \u00FC' -cursorColumn 18\n" in
      program
    # A character outside the BMP is two UTF-16 code units.
    check "-inputScript 'x \u{1F600}' -cursorColumn 4\n" in program
    check program.endsWith("'DONE'\n")

  test "a program too long for a Windows command line is refused":
    expect ValueError:
      discard powerShellDriverArgs(repeat('x', maxCommandLine))
    check powerShellDriverArgs(repeat('x', 10_000))[3].len < maxCommandLine
