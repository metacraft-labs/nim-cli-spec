## Help, rendered from the grammar: human-readable text and a
## machine-readable JSON document.
##
## What help lists
## ===============
##
## The help of a command lists its subcommands, its positionals and the flags
## it accepts (inherited ones included), each with its help text. A
## ``call:`` has no help of its own: its parameters are listed in the help of
## the command that holds it. Visibility decides the rest:
##
## * ``shown`` items are listed wherever they apply;
## * ``hidden`` items are never listed (they are still accepted), in either
##   form;
## * an ``internal`` parameter, wherever it is declared, is listed in no
##   human-readable help. It is still accepted and fills its field of the
##   configuration object. The machine-readable form lists it wherever it
##   applies, marked ``"visibility": "internal"``, so tools that know about
##   it can find it;
## * an ``internal`` subcommand is listed only in the help of the command
##   that holds it, and never in the help of the root command, which is the
##   program's primary help. So ``tool internal --help`` documents the
##   namespace that ``tool --help`` leaves out (its internal parameters
##   excepted).
##
## A subcommand's ``tier`` decides which page lists it, among the ones the
## rules above let through: ``-h`` and ``--help`` list the ``primary``
## subcommands, ``--help-all`` (``help --all`` under ``parsing helpWord``)
## lists ``secondary`` ones too. The machine-readable form and completion
## list both tiers.
##
## The standard page
## =================
##
## The default (``cliDefaultHelpLayout``). ``-h`` asks for the short page,
## ``--help`` (and the word ``help``) for the long one:
##
## .. code-block::
##   Build packages
##
##   Usage: tool build [options] [<packages>...]
##
##   Aliases: b
##
##   Arguments:
##     [<packages>...]  Packages to build
##
##   Options:
##     -j, --jobs <N>         Parallel jobs [default: 4] [env: TOOL_JOBS]
##         --report[=<PATH>]  Write a report
##     -h, --help             Print help (see more with '--help')
##
##   Global Options:
##     -v, --verbose...  Print more output
##
##   Examples:
##     Build two packages
##       tool build -j 8 app lib
##
## Sections, each only when it has entries, one blank line apart: the
## command's ``help`` line (on the long page followed by the command's
## ``longHelp``, one paragraph per non-blank line), ``Usage:``,
## ``Aliases:``, ``Commands:`` (the listed subcommands in no group), one
## section per command group (``group`` around ``subcmd`` statements) in
## the order the groups were first declared with its help under the
## heading, ``Arguments:``, ``Options:`` (the command's
## own flags in no group, then the help row and the ``--version`` row),
## one section per ``group`` in declaration order with its help under the
## heading, ``Global Options:`` (inherited flags in no group),
## ``Examples:`` and, on a command with subcommands, ``Run '<path>
## <command> --help' for more on a command.`` On a page that leaves out
## ``secondary`` subcommands (``-h``, ``--help``) that last line is instead
## ``Run '<path> --help-all' to list all <N> commands, or '<path> <command>
## --help' for details.``, ``N`` being the number of subcommands
## ``--help-all`` lists (``1 command`` for one), wrapped at the page width
## with each quoted command line kept whole. A program that declares no
## ``secondary`` subcommand and no command group gets the page above
## unchanged.
##
## Rows: long spellings aligned (four spaces stand for a missing short
## spelling when another row of the section has one); a counted flag's
## spelling ends with ``...``; an ``afterSeparator`` positional is written
## after the ``--`` that introduces its words, ``[-- <command>...]``
## (``-- <command>...`` when required), here and on the usage line, in
## both layouts; the description is ``help`` followed by the
## notes ``[required]``, ``[default: x]`` (not for switches and counted
## flags; a text default quoted when empty or holding white space),
## ``[possible values: a, b]`` (when the placeholder does not list the set)
## and ``[env: NAME]``; the long page adds each parameter's ``longHelp``
## paragraphs under its row. The page is ``width`` columns wide, at most
## 100; when ``width`` is 0 (as in ``cliDefaultHelpLayout``) the printer
## decides it (``cliPrintHelp``: ``COLUMNS``, else the terminal's width,
## else 80; ``clispec/styles``) and a page rendered without a printer is 80
## columns wide. Descriptions wrap under the description column, two
## spaces after the section's widest left entry of at most ``maxLeft``
## characters (a wider one puts its description on the next line); when
## fewer than 40 columns would remain, every description of the section
## goes under its row, 10 columns past the indent. A note is broken only
## when it is wider than the line; the usage line, example command lines
## and words longer than the line are never broken.
##
## Styled (with the ``CliStyle`` ``cliPrintHelp`` decides for its stream, or
## ``styled = true``, the ``portable16`` palette), the headings, the
## literals (flag spellings, command names and aliases, the words of the
## usage line and example command lines) and the placeholders get their
## element's colour (``clispec/styles``); the text is otherwise the same,
## character for character. Each renderer that takes a style has an
## overload for ``CliStyle`` and one for ``CliPlainStyle``: rendered with
## ``CliPlainStyle`` (what a program built with ``colors = never`` renders
## with), a page compiles none of the styling code and is the same as with
## ``CliStyle()``.
##
## The classic layout
## ==================
##
## ``cliClassicHelpLayout``, the default of the ``CliHelpLayout`` type
## (so a layout built field by field renders it unless it sets ``style``):
##
## .. code-block::
##   Usage: tool build [options] <target>
##
##   Build a project
##
##   Aliases: b
##
##   Commands:
##     target  Build one target
##
##   Arguments:
##     <target>  What to build [default: all]
##
##   Options:
##     -j, --jobs <int>  Parallel jobs [default: 4]
##
##   Output:
##     Where results go
##     --report[=<string>]  Write a report
##
## Sections appear only when they have entries. Flags without a ``group``
## come under ``Options:``, then each ``group`` section in the order the
## groups were first declared. The classic page knows no command groups and
## no tiers: it lists every listed subcommand under ``Commands:``, as it
## always did, whichever page was asked for. A value's placeholder is the
## declared ``valueName``, else the closed value set, else the type's name; a
## parameter's ``longHelp`` paragraphs follow its description, one per line.
##
## ``CliHelpLayout`` sets the indent, the description column, the width
## descriptions are wrapped to, a row for the help flag (and one for
## ``--version``), the list marker, the order of a long alias and the
## notes; its defaults are the layout
## above, in which nothing is wrapped. The classic page is printed as it
## is: ``cliPrintHelp`` never changes its width, and styles it (headings,
## the usage line and the left column, as on the standard page) only when
## the program sets ``CliOptions.color`` to ``ccmAlways``. ``cliOptionsTable`` renders just the
## rows of a command's options table, for a program that writes the rest of
## its help screen itself.
##
## Machine-readable form (schema ``clispec-help/1``)
## =================================================
##
## ``cliHelpJson`` describes a command and every command listed below it as
## one JSON object, with keys in a fixed order:
##
## .. code-block:: json
##   {"schema": "clispec-help/1", "program": "tool", "command": COMMAND,
##    "conventions": {"cli": "kebabCase", "file": "snakeCase", ...}}
##
## ``COMMAND`` is ``{"name", "path", "aliases", "help", "longHelp",
## "visibility", "usage", "examples": [{"command", "help"}...],
## "parameters": [PARAMETER...], "commands": [COMMAND...]}`` and
## ``PARAMETER`` is ``{"name", "kind" ("flag" | "positional"), "spellings",
## "negation" (string or null), "value" ("none" | "required" | "optional"),
## "format" ("separate" | "equals" | "concat"), "valueName", "choices",
## "list", "separator" (string or null), "counted", "required", "default"
## (string or null), "env", "help", "group" (string or null), "visibility",
## "position" (positional only), "declaredIn", "dynamicCompletion",
## "completer" (string or null), "configKeys", "longHelp", "placeholder",
## "acceptsNextWord", "refuseFalse", "alsoSets" ([{"param", "value"}])}``,
## and after ``conventions`` the document ends with ``"parsing":
## {"flagMatching", "rules"}`` (the description's ``flagMatching`` mode and
## ``parsing`` rules; ``"commandMatching"`` follows when the description
## sets a mode other than ``exact``). A positional declared ``rest = true``
## has ``"rest": true`` after its ``position`` (the key is absent
## otherwise), one declared ``afterSeparator = true`` has
## ``"afterSeparator": true`` there (likewise absent otherwise), and a
## command declared ``shadowedByWord = true`` has ``"shadowedByWord": true``
## after its ``visibility`` (likewise absent otherwise). In a program that
## declares a command group or a ``secondary`` subcommand, every command
## then has ``"group"`` (its group's title, or null) and ``"tier"``
## (``"primary"`` or ``"secondary"``); both are absent from the document of
## a program that declares neither, so it stays as it was. Subcommands of
## both tiers are listed. ``placeholder`` is what help shows between ``<`` and
## ``>`` (``valueName`` stays the type's name). ``conventions`` names the
## naming convention of the command line (``cli``), of every configuration
## file (``file``) and of each named file source; ``configKeys`` is a
## parameter's key in each of those file sources (``{}`` when no file may
## supply it), and its ``spellings`` and ``negation`` are spelt in the
## command line's convention. ``value`` says whether a flag takes a
## value and ``format`` how: ``separate`` flags take ``--flag=value`` or the
## next word, ``equals`` ones only ``--flag=value`` (an ``equals`` or
## ``concat`` alias is followed directly by the value, ``-DX``).
## ``choices`` is the closed value set (empty when open); ``completer`` is
## the ``complete`` expression as written, for a completion engine that
## calls it. The listing rules above decide which items appear; unlike the
## human-readable help, the machine-readable form includes ``internal``
## parameters. A command at which a retired spelling applies
## (``cliRetiredAt``) has, after its ``parameters``, ``"retired":
## [{"spelling", "kind" ("flag" | "subcommand"), "replacement",
## "declaredIn"}]``, nearest declaration first; the key is absent where none
## applies. A retired spelling is never among a command's ``parameters``,
## ``spellings`` or ``commands``: the list tells a tool what the program
## refuses and names, not what it accepts. Within ``clispec-help/1`` keys
## are only ever added, never renamed
## or removed, and their meaning does not change; anything else is a new
## schema name.

import std/[json, strutils]

import ./[model, grammar, styles]

type
  CliHelpStyle* = enum
    ## Which help page a ``CliHelpLayout`` renders.
    chsClassic = "classic"
      ## The layout clispec printed before the standard one (``Usage:``
      ## first, every flag under ``Options:``, nothing wrapped unless
      ## ``width`` says so). Every field of ``CliHelpLayout`` applies.
    chsStandard = "standard"
      ## The standard page (see "The standard page" above): summary first,
      ## own and inherited flags apart, aligned long spellings, wrapping at
      ## ``width``, examples, and a short (``-h``) and a long (``--help``)
      ## form. ``column`` does not apply.

  CliHelpLayout* = object
    ## How the human-readable help lays its tables out. Every field's
    ## default is the classic layout, so ``CliHelpLayout()`` (or any layout
    ## built field by field without ``style``) renders exactly what
    ## ``cliHelpText`` printed before the standard page existed. The help
    ## procedures' default argument is ``cliDefaultHelpLayout``.
    style*: CliHelpStyle = chsClassic
      ## The page: ``chsClassic`` (the default of the type) or
      ## ``chsStandard`` (``cliDefaultHelpLayout``).
    indent*: int = 2
      ## Spaces before the left column (the flag spellings).
    column*: int = 0
      ## The column the description starts at, counted from the start of
      ## the line. 0 (the default) sizes it to the table: two spaces after
      ## the widest left entry of at most ``maxLeft`` characters. With a
      ## fixed column, a left entry that leaves fewer than two spaces before
      ## it puts the description on the next line, at the column.
    maxLeft*: int = 32
      ## With ``column = 0``: the widest left entry the column is sized to;
      ## a wider one puts its description on the next line.
    width*: int = 0
      ## The line width descriptions are word-wrapped to (0, the default:
      ## not wrapped). Words are separated by white space and joined by one
      ## space; a word longer than the line is kept whole. In the standard
      ## style it is the width of the page, at most 100; 0 leaves it to the
      ## printer (``cliPrintHelp``), and a page rendered without one is 80
      ## columns wide.
    helpFlag*: string = ""
      ## When not empty, the options table ends with a row for the help
      ## flag (``-h, --help``, the spellings that request help) with this
      ## description. In the standard style the short page (``-h``) adds
      ## `` (see more with '--help')`` to it when the long page shows more.
    versionFlag*: string = ""
      ## When not empty, the options table ends with a row for
      ## ``--version`` with this description (after the help flag's row),
      ## unless a flag of the command is spelt ``--version``. Help does not
      ## know whether the program has a version text
      ## (``CliOptions.versionText``), so it lists the row only when asked;
      ## by default ``--version`` is not listed.
    listMarker*: bool = true
      ## A list flag's placeholder is followed by ``...``
      ## (``--tag <string>...``).
    canonicalFirst*: bool = false
      ## The canonical ``--<name>`` is listed before a long ``alias``
      ## (``--cooperative, --coop``); by default the alias comes first.
    notes*: bool = true
      ## A description ends with ``[required]``, ``[default: x]`` and
      ## ``[env: X]`` where they apply.

const
  cliClassicHelpLayout* = CliHelpLayout()
    ## The classic layout: what ``cliHelpText`` printed before the standard
    ## page. A program that must keep it for its users names it
    ## (``Tool.helpText(layout = cliClassicHelpLayout)``,
    ## ``CliOptions(helpLayout: cliClassicHelpLayout)``).
  cliDefaultHelpLayout* = CliHelpLayout(style: chsStandard, width: 0,
    canonicalFirst: true, helpFlag: "Print help")
    ## The standard page, its width left to the printer (80 columns when
    ## rendered without one): the default of ``cliHelpText``,
    ## ``cliOptionsTable``, the generated ``helpText`` / ``optionsTable``
    ## and the help ``load`` raises.

func helpHolder(g: CliGrammar; command: int): int =
  ## The command whose help documents ``command``: a call:'s holder.
  if g.commands[command].isCall: g.commands[command].parent else: command

func cliListsCommand*(g: CliGrammar; holder, child: int): bool =
  ## Whether the help of ``holder`` lists its subcommand ``child``.
  case g.commands[child].visibility
  of cvShown: true
  of cvHidden: false
  of cvInternal: holder != 0

func cliListsParam*(g: CliGrammar; holder, id: int;
                    machineReadable = false): bool =
  ## Whether the help of ``holder`` lists parameter ``id``: a ``shown`` one
  ## always, an ``internal`` one only in the machine-readable form, a
  ## ``hidden`` one never. A parameter whose ``sources`` exclude the command
  ## line is not part of it and is never listed.
  let p = g.params[id]
  if csCli notin p.sources:
    return false
  case p.visibility
  of cvShown: true
  of cvHidden: false
  of cvInternal: machineReadable

func cliHelpParams*(g: CliGrammar; command: int;
                    machineReadable = false): seq[int] =
  ## The parameters the help of ``command`` lists, in declaration order: its
  ## own (inherited ones included), then its call:'s. ``machineReadable``
  ## selects the JSON form's listing, which includes ``internal`` ones.
  let holder = helpHolder(g, command)
  var all = g.commands[holder].params
  let call = g.commands[holder].callChild
  if call >= 0:
    for id in g.commands[call].ownParams:
      all.add(id)
  for id in all:
    if cliListsParam(g, holder, id, machineReadable):
      result.add(id)

func cliHelpCommands*(g: CliGrammar; command: int): seq[int] =
  ## The subcommands the help of ``command`` lists, of either tier: what
  ## ``--help-all`` and the machine-readable form list. ``-h`` and
  ## ``--help`` leave out the ``secondary`` ones (``cliHelpCommandsOfPage``).
  let holder = helpHolder(g, command)
  for child in g.commands[holder].children:
    if cliListsCommand(g, holder, child):
      result.add(child)

func cliHelpCommandsOfPage*(g: CliGrammar; command: int; all: bool):
    seq[int] =
  ## The subcommands one human-readable page of ``command`` lists:
  ## ``cliHelpCommands`` with ``all`` (``--help-all``), only the
  ## ``primary`` ones without it (``-h``, ``--help``).
  for child in cliHelpCommands(g, command):
    if all or g.commands[child].tier == ctPrimary:
      result.add(child)

func elementTypeName(nimType: string): string =
  result = nimType.strip()
  for prefix in ["seq[", "Option["]:
    if result.startsWith(prefix) and result.endsWith("]"):
      result = result[prefix.len .. ^2].strip()

func cliPlaceholder*(p: CliGrammarParam): string =
  ## What help shows between ``<`` and ``>`` for a value: the declared
  ## ``valueName``, else the closed value set joined with ``|``, else the
  ## element type's name.
  if p.placeholder.len > 0: p.placeholder
  elif p.choices.len > 0: p.choices.join("|")
  else: elementTypeName(p.valueName)

func takesValue(p: CliGrammarParam): string =
  if p.kind == cpkPositional: "required"
  elif p.isSwitch or p.counted: "none"
  elif p.hasOptionalValue: "optional"
  else: "required"

func flagLeft(p: CliGrammarParam; layout: CliHelpLayout): string =
  ## ``-j, --jobs <int>``, ``--[no-]verbose``, ``-l<string>, --libs=<string>``.
  let v = "<" & cliPlaceholder(p) & ">" &
    (if p.separator.len > 0: "[" & p.separator & "...]"
     elif p.isList and layout.listMarker: "..."
     else: "")
  let kind = takesValue(p)
  var parts: seq[string] = @[]
  if p.short != '\0':
    parts.add("-" & p.short)
  var aliasPart = ""
  if p.alias.len > 0 and p.alias != "--" & cliLongName(p):
    if p.format == cafConcat and kind == "required":
      aliasPart = p.alias & v
    else:
      aliasPart = p.alias
  let aliasAfter = layout.canonicalFirst and aliasPart.startsWith("--") and
    p.format != cafConcat
  if aliasPart.len > 0 and not aliasAfter:
    parts.add(aliasPart)
  let long = if p.negatable: "--[no-]" & cliLongName(p)
             else: "--" & cliLongName(p)
  if aliasAfter:
    # ``--cooperative, --coop``: the placeholder closes the column.
    parts.add(long)
    parts.add(aliasPart)
    case kind
    of "none": discard
    of "optional": parts[^1].add("[=" & v & "]")
    else:
      if p.format == cafSeparate: parts[^1].add(" " & v)
      else: parts[^1].add("=" & v)
    return parts.join(", ")
  case kind
  of "none":
    parts.add(long)
  of "optional":
    parts.add(long & "[=" & v & "]")
  else:
    if p.format == cafSeparate: parts.add(long & " " & v)
    else: parts.add(long & "=" & v)
  parts.join(", ")

func positionalLeft(p: CliGrammarParam): string =
  ## ``<target>``, ``[<files>...]``; an ``afterSeparator`` positional is
  ## written after the ``--`` that introduces its words: ``[-- <cmd>...]``.
  let core = (if p.afterSeparator: "-- " else: "") & "<" & p.name & ">" &
    (if p.repeated or p.isList: "..." else: "")
  if p.required: core else: "[" & core & "]"

func notes(p: CliGrammarParam; layout: CliHelpLayout): string =
  var parts: seq[string] = @[]
  if p.help.len > 0:
    parts.add(p.help)
  if layout.notes:
    if p.required and p.kind == cpkFlag:
      parts.add("[required]")
    if p.hasDefault:
      parts.add("[default: " & p.defaultText & "]")
    if p.env.len > 0:
      parts.add("[env: " & p.env.join(", ") & "]")
  parts.join(" ")

func paragraphs(p: CliGrammarParam; layout: CliHelpLayout): seq[string] =
  ## A parameter's description: ``help`` with its notes, then each
  ## non-blank line of ``longHelp``.
  let first = notes(p, layout)
  if first.len > 0:
    result.add(first)
  for line in p.longHelp.splitLines():
    if line.strip().len > 0:
      result.add(line)

func cliUsageLine*(g: CliGrammar; command: int; program: string): string =
  ## ``tool build [options] <target>``.
  let holder = helpHolder(g, command)
  var words = @[program]
  for word in g.commands[holder].path:
    words.add(word)
  let params = cliHelpParams(g, holder)
  var hasFlags = false
  for id in params:
    if g.params[id].kind == cpkFlag:
      hasFlags = true
  if hasFlags:
    words.add("[options]")
  if g.commands[holder].children.len > 0:
    words.add(if g.commands[holder].callChild >= 0: "[<command>]"
              else: "<command>")
  let target = if g.commands[holder].callChild >= 0:
                 g.commands[holder].callChild
               else: holder
  for id in cliPositionals(g, target):
    if cliListsParam(g, holder, id):
      words.add(positionalLeft(g.params[id]))
  words.join(" ")

func wrapInto(dest: var seq[string]; text: string; indent, width: int) =
  ## ``text`` word-wrapped to ``width`` columns, each line indented by
  ## ``indent`` spaces; a word longer than the line is kept whole.
  var line = ""
  for word in text.splitWhitespace():
    if line.len > 0 and indent + line.len + 1 + word.len > width:
      dest.add(repeat(' ', indent) & line)
      line = ""
    if line.len > 0:
      line.add(' ')
    line.add(word)
  if line.len > 0:
    dest.add(repeat(' ', indent) & line)

type HelpRow = tuple[left: string, right: seq[string]]
  ## One row of a table: the left column and the description's paragraphs.

func helpFlagLeft(g: CliGrammar; command: int): string =
  ## The spellings that request help in ``command`` (``-h, --help``), for
  ## ``CliHelpLayout.helpFlag``; a spelling a flag of the command declares
  ## does not.
  var spellings: seq[string] = @[]
  let asked = if cprLongHelpOnly in g.parseRules: @["--help"]
              else: @["-h", "--help"]
  for s in asked:
    var claimed = false
    for id in g.commands[command].params:
      if g.params[id].kind == cpkFlag and s in cliFlagSpellings(g.params[id]):
        claimed = true
    if not claimed:
      spellings.add(s)
  spellings.join(", ")

func optionRows(g: CliGrammar; holder: int; params: seq[int];
                section: string; layout: CliHelpLayout): seq[HelpRow] =
  for id in params:
    let p = g.params[id]
    if p.kind == cpkFlag and p.group == section:
      result.add((flagLeft(p, layout), paragraphs(p, layout)))
  if section.len == 0 and layout.helpFlag.len > 0:
    let left = helpFlagLeft(g, holder)
    if left.len > 0:
      result.add((left, @[layout.helpFlag]))
  if section.len == 0 and layout.versionFlag.len > 0:
    var claimed = false
    for id in g.commands[holder].params:
      if g.params[id].kind == cpkFlag and
          "--version" in cliFlagSpellings(g.params[id]):
        claimed = true
    if not claimed:
      result.add(("--version", @[layout.versionFlag]))

# The standard page.
# ---------------------------------------------------------------------------

const
  StandardWidth = 80
    ## The page width when the layout gives none.
  StandardWidthCap = 100
    ## The widest a standard page is, whatever the width asked for.
  MinDescription = 40
    ## A section whose description column leaves fewer columns than this
    ## uses the next-line layout.
  NextLineIndent = 10
    ## Where the next-line layout puts descriptions, after the indent.

type StandardRow = tuple[left: string, paragraphs: seq[seq[string]]]
  ## One row of a standard table: the left column and the description's
  ## paragraphs, each a list of units (a word, or a note kept whole).

func pageWidth(layout: CliHelpLayout): int =
  min(if layout.width > 0: layout.width else: StandardWidth,
    StandardWidthCap)

func wrapUnits(units: openArray[string]; indent, width: int): seq[string] =
  ## ``units`` joined by single spaces and wrapped to ``width`` columns, as
  ## if each line started at column ``indent`` (the indent is not added). A
  ## unit is not broken unless it is wider than the line, where a note is
  ## broken at its spaces; a word longer than the line is kept whole.
  var line = ""
  for unit in units:
    if line.len > 0 and indent + line.len + 1 + unit.len > width:
      result.add(line)
      line = ""
    if line.len == 0 and indent + unit.len > width and ' ' in unit:
      for word in unit.split(' '):
        if line.len > 0 and indent + line.len + 1 + word.len > width:
          result.add(line)
          line = ""
        line = if line.len > 0: line & " " & word else: word
      continue
    line = if line.len > 0: line & " " & unit else: unit
  if line.len > 0:
    result.add(line)

func wrapText(text: string; indent, width: int): seq[string] =
  ## Prose wrapped at ``width``, each line indented ``indent`` spaces.
  for line in wrapUnits(text.splitWhitespace(), indent, width):
    result.add(repeat(' ', indent) & line)

func quotedDefault(p: CliGrammarParam): string =
  ## A text default is quoted only when it is empty or holds white space.
  var blank = p.defaultText.len == 0
  for c in p.defaultText:
    if c in Whitespace:
      blank = true
  if p.defaultIsText and blank: "\"" & p.defaultText & "\""
  else: p.defaultText

func standardNotes(p: CliGrammarParam; layout: CliHelpLayout): seq[string] =
  ## ``[required]``, ``[default: x]``, ``[possible values: a, b]`` and
  ## ``[env: NAME, ...]``, in that order, where they apply.
  if not layout.notes:
    return
  if p.required and p.kind == cpkFlag:
    result.add("[required]")
  if p.hasDefault and not p.isSwitch and not p.counted:
    result.add("[default: " & quotedDefault(p) & "]")
  if p.choices.len > 0 and takesValue(p) != "none" and
      (p.kind == cpkPositional or cliPlaceholder(p) != p.choices.join("|")):
    result.add("[possible values: " & p.choices.join(", ") & "]")
  if p.env.len > 0:
    result.add("[env: " & p.env.join(", ") & "]")

func standardParagraphs(p: CliGrammarParam; layout: CliHelpLayout;
                        long: bool): seq[seq[string]] =
  ## The description: ``help`` and the notes, then (long page only) each
  ## non-blank line of ``longHelp``.
  result.add(p.help.splitWhitespace() & standardNotes(p, layout))
  if long:
    for line in p.longHelp.splitLines():
      if line.strip().len > 0:
        result.add(line.splitWhitespace())

func standardFlagLeft(p: CliGrammarParam; layout: CliHelpLayout): string =
  ## ``flagLeft``, and a counted flag's ``...`` (``-v, --verbose...``).
  result = flagLeft(p, layout)
  if p.counted:
    result.add("...")

func alignLongs(rows: var seq[StandardRow]) =
  ## Long spellings aligned: four spaces stand for a missing short
  ## spelling when another row of the section starts with one.
  var anyShort = false
  for row in rows:
    if row.left.startsWith("-") and not row.left.startsWith("--"):
      anyShort = true
  if anyShort:
    for row in rows.mitems:
      if row.left.startsWith("--"):
        row.left = "    " & row.left

func ownedBy(g: CliGrammar; holder, id: int): bool =
  ## Whether ``holder`` (or its ``call:``) declares parameter ``id``.
  let by = g.params[id].declaredBy
  by == holder or (g.commands[holder].callChild >= 0 and
    by == g.commands[holder].callChild)

func showsMore(g: CliGrammar; holder: int; params: seq[int]): bool =
  ## Whether the long page shows more than the short one.
  let cmd = g.commands[holder]
  if cmd.longHelp.strip().len > 0:
    return true
  if cmd.callChild >= 0 and g.commands[cmd.callChild].longHelp.strip().len > 0:
    return true
  for id in params:
    if g.params[id].longHelp.strip().len > 0:
      return true

type StandardSection = enum
  ssOwn, ssGroup, ssGlobal

func standardOptionRows(g: CliGrammar; holder: int; params: seq[int];
                        section: StandardSection; group: string;
                        layout: CliHelpLayout; long: bool): seq[StandardRow] =
  ## The rows of one section: ``Options:`` (the command's own flags in no
  ## group, then the help and version rows), a group's (own and inherited
  ## flags in it) or ``Global Options:`` (inherited flags in no group).
  for id in params:
    let p = g.params[id]
    if p.kind != cpkFlag:
      continue
    let belongs = case section
      of ssOwn: p.group.len == 0 and ownedBy(g, holder, id)
      of ssGroup: p.group == group
      of ssGlobal: p.group.len == 0 and not ownedBy(g, holder, id)
    if belongs:
      result.add((standardFlagLeft(p, layout),
        standardParagraphs(p, layout, long)))
  if section == ssOwn and layout.helpFlag.len > 0:
    let left = helpFlagLeft(g, holder)
    if left.len > 0:
      let text = if not long and showsMore(g, holder, params):
                   layout.helpFlag & " (see more with '--help')"
                 else: layout.helpFlag
      result.add((left, @[text.splitWhitespace()]))
  if section == ssOwn and layout.versionFlag.len > 0:
    var claimed = false
    for id in g.commands[holder].params:
      if g.params[id].kind == cpkFlag and
          "--version" in cliFlagSpellings(g.params[id]):
        claimed = true
    if not claimed:
      result.add(("--version", @[layout.versionFlag.splitWhitespace()]))
  alignLongs(result)

func commandPathText(g: CliGrammar; holder: int; program: string): string =
  (@[program] & g.commands[holder].path).join(" ")

template styleRenderers(S: typedesc) {.dirty.} =
  ## The renderers that take a style, for one style type: expanded here
  ## for ``CliStyle`` and for ``CliPlainStyle`` (``clispec/styles``), so
  ## each is an ordinary overload whose symbols are bound in this module,
  ## and a program that renders only with ``CliPlainStyle`` compiles none
  ## of the styling helpers.

  func styleLeft(left: string; names: bool; style: S): string =
    ## A row's left column, styled: a list of command names, or flag
    ## spellings and placeholders.
    if names: cliStyleNames(left, style) else: cliStyleSpellings(left, style)

  func table(rows: seq[HelpRow]; layout: CliHelpLayout; style: S;
             names = false): seq[string] =
    ## Two columns (see ``CliHelpLayout``): by default the left one padded to
    ## its widest entry (at most 32 characters; a longer entry puts its text
    ## on the next line), each paragraph of the description on a line of its
    ## own. Widths are those of the plain text; ``style`` styles the left
    ## column (``names``: a list of command names).
    let pad = repeat(' ', layout.indent)
    var column = layout.column
    if column <= 0:
      var width = 0
      for row in rows:
        if row.left.len <= layout.maxLeft:
          width = max(width, row.left.len)
      column = layout.indent + width + 2
    for row in rows:
      var body: seq[string] = @[]
      for paragraph in row.right:
        if layout.width > 0:
          body.wrapInto(paragraph, column, layout.width)
        else:
          body.add(repeat(' ', column) & paragraph)
      let left = pad & row.left
      let shown = pad & styleLeft(row.left, names, style)
      let beside = if layout.column <= 0: row.left.len <= layout.maxLeft
                   else: left.len + 1 < column
      if body.len == 0:
        result.add(shown)
      elif beside:
        result.add(shown & repeat(' ', column - left.len) &
          body[0][column .. ^1])
        for line in body[1 .. ^1]:
          result.add(line)
      else:
        result.add(shown)
        for line in body:
          result.add(line)

  func standardTable(rows: seq[StandardRow]; layout: CliHelpLayout;
                     width: int; style: S; names = false):
      seq[string] =
    ## Two columns: the description column two spaces after the widest left
    ## entry of at most ``maxLeft`` characters (a wider entry puts its
    ## description on the next line); when that leaves fewer than
    ## ``MinDescription`` columns, every description goes under its row.
    ## Widths are those of the plain text; ``style`` styles the left column
    ## (``names``: a list of command names).
    let indent = layout.indent
    var widest = 0
    for row in rows:
      if row.left.len <= layout.maxLeft:
        widest = max(widest, row.left.len)
    var column = indent + widest + 2
    let nextLine = width - column < MinDescription
    if nextLine:
      column = indent + NextLineIndent
    for row in rows:
      var body: seq[string] = @[]
      for paragraph in row.paragraphs:
        if paragraph.len > 0:
          body.add(wrapUnits(paragraph, column, width))
      let head = repeat(' ', indent) & row.left
      let shown = repeat(' ', indent) & styleLeft(row.left, names, style)
      var first = 0
      if body.len > 0 and not nextLine and row.left.len <= layout.maxLeft:
        result.add(shown & repeat(' ', column - head.len) & body[0])
        first = 1
      else:
        result.add(shown)
      for k in first ..< body.len:
        result.add(repeat(' ', column) & body[k])

  func heading(text: string; style: S): string =
    cliStyled(text, ctsHeading, style)

  func standardCommandSections(g: CliGrammar; children: seq[int];
                               layout: CliHelpLayout; width: int;
                               style: S): seq[seq[string]] =
    ## The command sections of a page: ``Commands:`` (the subcommands in no
    ## group), then one section per command group in the order the groups
    ## were first declared, its help under the heading. Each section is a
    ## table of its own, as each parameter group's is.
    proc rowsOf(group: string): seq[StandardRow] =
      for child in children:
        let c = g.commands[child]
        if c.group == group:
          result.add(((@[c.name] & c.aliases).join(", "),
            @[c.help.splitWhitespace()]))
    let ungrouped = rowsOf("")
    if ungrouped.len > 0:
      result.add(@[heading("Commands:", style)] &
        standardTable(ungrouped, layout, width, style, names = true))
    for group in g.groups:
      let rows = rowsOf(group.name)
      if rows.len == 0:
        continue
      var section = @[heading(group.name & ":", style)]
      if group.help.strip().len > 0:
        section.add(wrapText(group.help, layout.indent, width))
      result.add(section & standardTable(rows, layout, width, style,
        names = true))

  proc standardHelpText(g: CliGrammar; command: int; program: string;
                        layout: CliHelpLayout; long: bool; style: S;
                        all = false): string =
    let width = pageWidth(layout)
    let holder = helpHolder(g, command)
    let cmd = g.commands[holder]
    let call = cmd.callChild
    var blocks: seq[seq[string]] = @[]
    var help = cmd.help
    if help.len == 0 and call >= 0:
      help = g.commands[call].help
    if help.strip().len > 0:
      blocks.add(wrapText(help, 0, width))
    if long:
      var longHelp = cmd.longHelp
      if longHelp.strip().len == 0 and call >= 0:
        longHelp = g.commands[call].longHelp
      for line in longHelp.splitLines():
        if line.strip().len > 0:
          blocks.add(wrapText(line, 0, width))
    blocks.add(@[heading("Usage:", style) & " " &
      cliStyleUsage(cliUsageLine(g, holder, program), style)])
    if cmd.aliases.len > 0:
      blocks.add(@[heading("Aliases:", style) & " " &
        cliStyleNames(cmd.aliases.join(", "), style)])
    let children = cliHelpCommands(g, holder)
    let shown = cliHelpCommandsOfPage(g, holder, all)
    blocks.add(standardCommandSections(g, shown, layout, width, style))
    let params = cliHelpParams(g, holder)
    var positional: seq[StandardRow] = @[]
    let target = if call >= 0: call else: holder
    for id in cliPositionals(g, target):
      if id in params:
        positional.add((positionalLeft(g.params[id]),
          standardParagraphs(g.params[id], layout, long)))
    if positional.len > 0:
      blocks.add(@[heading("Arguments:", style)] &
        standardTable(positional, layout, width, style))
    let own = standardOptionRows(g, holder, params, ssOwn, "", layout, long)
    if own.len > 0:
      blocks.add(@[heading("Options:", style)] &
        standardTable(own, layout, width, style))
    for group in g.groups:
      let rows = standardOptionRows(g, holder, params, ssGroup, group.name,
        layout, long)
      if rows.len == 0:
        continue
      var section = @[heading(group.name & ":", style)]
      if group.help.strip().len > 0:
        section.add(wrapText(group.help, layout.indent, width))
      blocks.add(section & standardTable(rows, layout, width, style))
    let global = standardOptionRows(g, holder, params, ssGlobal, "", layout,
      long)
    if global.len > 0:
      blocks.add(@[heading("Global Options:", style)] &
        standardTable(global, layout, width, style))
    var examples = cmd.examples
    if call >= 0:
      examples.add(g.commands[call].examples)
    if examples.len > 0:
      var section = @[heading("Examples:", style)]
      for k, example in examples:
        if k > 0:
          section.add("")
        section.add(wrapText(example.help, layout.indent, width))
        section.add(repeat(' ', layout.indent + 2) &
          cliStyled(example.command, ctsLiteral, style))
      blocks.add(section)
    let path = commandPathText(g, holder, program)
    if shown.len < children.len:
      # Some subcommands are ``secondary`` and this page leaves them out: say
      # how many ``--help-all`` lists, which is every listed one. The line is
      # wrapped at the page width like prose, but each quoted command line is
      # one unit, never broken, and is styled once wrapped.
      let allLine = path & " --help-all"
      let oneLine = path & " <command> --help"
      var units = @["Run", "'" & allLine & "'"]
      units.add(("to list all " & $children.len &
        (if children.len == 1: " command," else: " commands,") &
        " or").splitWhitespace())
      units.add("'" & oneLine & "'")
      units.add(@["for", "details."])
      var footer: seq[string] = @[]
      for line in wrapUnits(units, 0, width):
        footer.add(line.multiReplace(
          ("'" & allLine & "'", "'" & cliStyleUsage(allLine, style) & "'"),
          ("'" & oneLine & "'", "'" & cliStyleUsage(oneLine, style) & "'")))
      blocks.add(footer)
    elif children.len > 0:
      blocks.add(@["Run '" & cliStyleUsage(path & " <command> --help",
        style) & "' for more on a command."])
    var lines: seq[string] = @[]
    for k, b in blocks:
      if k > 0:
        lines.add("")
      lines.add(b)
    lines.join("\n") & "\n"

  proc cliOptionsTable*(g: CliGrammar; command: int; style: S;
                        layout = cliDefaultHelpLayout; group = "";
                        long = false): string =
    ## Just the rows of the options table of ``command``'s help, laid out by
    ## ``layout``: the flags of the section ``group`` (empty: the flags in no
    ## group, under ``Options:``, followed by the help flag's row when
    ## ``layout.helpFlag`` is set), one line per output line, each ending
    ## with a newline. Empty when the section has no rows. In the standard
    ## style the ungrouped section is the command's own flags (inherited ones
    ## are its ``Global Options:``), and ``long`` selects the long page's
    ## rows (parameters' ``longHelp``, the help row's wording); the classic
    ## style always shows ``longHelp`` and ignores ``long``. ``style`` styles
    ## the left column (``CliStyle()`` or ``CliPlainStyle()``: plain).
    let holder = helpHolder(g, command)
    if layout.style == chsStandard:
      let params = cliHelpParams(g, holder)
      let rows = if group.len == 0:
                   standardOptionRows(g, holder, params, ssOwn, "", layout,
                     long)
                 else:
                   standardOptionRows(g, holder, params, ssGroup, group,
                     layout, long)
      for line in standardTable(rows, layout, pageWidth(layout), style):
        result.add(line & "\n")
      return
    let rows = optionRows(g, holder, cliHelpParams(g, holder), group, layout)
    for line in table(rows, layout, style):
      result.add(line & "\n")

  proc cliHelpText*(g: CliGrammar; command: int; program: string;
                    style: S; layout = cliDefaultHelpLayout;
                    long = false; all = false): string =
    ## The human-readable help of ``command`` (see the module documentation),
    ## laid out by ``layout``: by default the standard page, its short form
    ## (``-h``) or with ``long`` its long one (``--help``); ``all`` lists the
    ## ``secondary`` subcommands too (``--help-all``, with ``long``). The
    ## classic style has one form, lists every subcommand under
    ## ``Commands:`` and ignores ``long`` and ``all``. ``style`` adds the
    ## escape sequences of its palette (``clispec/styles``) and changes
    ## nothing else; ``CliStyle()`` and ``CliPlainStyle()`` give the plain
    ## page (the latter without compiling any styling code).
    if layout.style == chsStandard:
      return standardHelpText(g, command, program, layout, long, style, all)
    let holder = helpHolder(g, command)
    let cmd = g.commands[holder]
    var lines = @[heading("Usage:", style) & " " &
      cliStyleUsage(cliUsageLine(g, holder, program), style)]
    var help = cmd.help
    if help.len == 0 and cmd.callChild >= 0:
      help = g.commands[cmd.callChild].help
    if help.len > 0:
      lines.add("")
      lines.add(help)
    if cmd.aliases.len > 0:
      lines.add("")
      lines.add(heading("Aliases:", style) & " " &
        cliStyleNames(cmd.aliases.join(", "), style))
    let children = cliHelpCommands(g, holder)
    if children.len > 0:
      var rows: seq[HelpRow] = @[]
      for child in children:
        let c = g.commands[child]
        rows.add(((@[c.name] & c.aliases).join(", "),
          (if c.help.len > 0: @[c.help] else: @[])))
      lines.add("")
      lines.add(heading("Commands:", style))
      lines.add(table(rows, layout, style, names = true))
    let params = cliHelpParams(g, holder)
    var positional: seq[HelpRow] = @[]
    let target = if cmd.callChild >= 0: cmd.callChild else: holder
    for id in cliPositionals(g, target):
      if id in params:
        positional.add((positionalLeft(g.params[id]),
          paragraphs(g.params[id], layout)))
    if positional.len > 0:
      lines.add("")
      lines.add(heading("Arguments:", style))
      lines.add(table(positional, layout, style))
    # Ungrouped flags, then each group in declaration order.
    var sections = @[""]
    for group in g.groups:
      sections.add(group.name)
    for section in sections:
      let rows = optionRows(g, holder, params, section, layout)
      if rows.len == 0:
        continue
      lines.add("")
      if section.len == 0:
        lines.add(heading("Options:", style))
      else:
        lines.add(heading(section & ":", style))
        for group in g.groups:
          if group.name == section and group.help.len > 0:
            lines.add(repeat(' ', layout.indent) & group.help)
      lines.add(table(rows, layout, style))
    lines.join("\n") & "\n"

styleRenderers(CliStyle)
styleRenderers(CliPlainStyle)

proc cliOptionsTable*(g: CliGrammar; command: int;
                      layout = cliDefaultHelpLayout; group = "";
                      long = false; styled = false): string =
  ## ``cliOptionsTable`` plain, or in the ``portable16`` palette when
  ## ``styled`` (no detection).
  cliOptionsTable(g, command, cliStyleOf(styled), layout, group, long)

proc cliHelpText*(g: CliGrammar; command: int; program: string;
                  layout = cliDefaultHelpLayout; long = false;
                  styled = false; all = false): string =
  ## ``cliHelpText`` plain, or in the ``portable16`` palette when
  ## ``styled`` (no detection: ``cliPrintHelp`` decides the style for its
  ## stream).
  cliHelpText(g, command, program, cliStyleOf(styled), layout, long, all)

func paramJson(g: CliGrammar; p: CliGrammarParam): JsonNode =
  result = newJObject()
  result["name"] = %p.name
  result["kind"] = %(if p.kind == cpkFlag: "flag" else: "positional")
  result["spellings"] = %cliFlagSpellings(p)
  result["negation"] = if p.negatable: %("--no-" & cliLongName(p))
                       else: newJNull()
  result["value"] = %takesValue(p)
  result["format"] = %(case p.format
    of cafSeparate: "separate"
    of cafEquals: "equals"
    of cafConcat: "concat")
  result["valueName"] = %elementTypeName(p.valueName)
  result["choices"] = %p.choices
  result["list"] = %(p.isList or p.repeated)
  result["separator"] = if p.separator.len > 0: %p.separator else: newJNull()
  result["counted"] = %p.counted
  result["required"] = %p.required
  result["default"] = if p.hasDefault: %p.defaultText else: newJNull()
  result["env"] = %p.env
  result["help"] = %p.help
  result["group"] = if p.group.len > 0: %p.group else: newJNull()
  result["visibility"] = %($p.visibility)
  if p.kind == cpkPositional:
    result["position"] = %p.position
    if p.rest:
      result["rest"] = %true
    if p.afterSeparator:
      result["afterSeparator"] = %true
  result["declaredIn"] = %p.declaredIn
  result["dynamicCompletion"] = %p.hasCompleter
  result["completer"] = if p.hasCompleter: %p.completer else: newJNull()
  result["configKeys"] = cliConfigKeysJson(p)
  result["longHelp"] = %p.longHelp
  result["placeholder"] = %cliPlaceholder(p)
  result["acceptsNextWord"] = %p.acceptsNextWord
  result["refuseFalse"] = %cliRefusesFalse(g, p)
  var also = newJArray()
  for a in p.alsoSets:
    also.add(%*{"param": g.params[a.id].name, "value": a.text})
  result["alsoSets"] = also

proc commandJson(g: CliGrammar; command: int; program: string): JsonNode =
  let holder = helpHolder(g, command)
  let cmd = g.commands[holder]
  result = newJObject()
  result["name"] = %cmd.name
  result["path"] = %cmd.path
  result["aliases"] = %cmd.aliases
  var help = cmd.help
  if help.len == 0 and cmd.callChild >= 0:
    help = g.commands[cmd.callChild].help
  result["help"] = %help
  var longHelp = cmd.longHelp
  if longHelp.len == 0 and cmd.callChild >= 0:
    longHelp = g.commands[cmd.callChild].longHelp
  result["longHelp"] = %longHelp
  result["visibility"] = %($cmd.visibility)
  if cmd.shadowedByWord:
    result["shadowedByWord"] = %true
  if cliHasCommandGroups(g) or cliHasSecondaryCommands(g):
    # Added keys: present on every command of a program that declares a
    # command group or a ``secondary`` subcommand, so a description that
    # declares neither keeps its document byte for byte.
    result["group"] = if cmd.group.len > 0: %cmd.group else: newJNull()
    result["tier"] = %($cmd.tier)
  result["usage"] = %cliUsageLine(g, holder, program)
  var examples = newJArray()
  var declared = cmd.examples
  if cmd.callChild >= 0:
    declared.add(g.commands[cmd.callChild].examples)
  for e in declared:
    examples.add(%*{"command": e.command, "help": e.help})
  result["examples"] = examples
  var params = newJArray()
  for id in cliHelpParams(g, holder, machineReadable = true):
    params.add(paramJson(g, g.params[id]))
  result["parameters"] = params
  let retired = cliRetiredAt(g, holder)
  if retired.len > 0:
    # An added key, present only where a retired spelling applies, so a
    # description without one keeps its document byte for byte.
    var entries = newJArray()
    for a in retired:
      entries.add(%*{"spelling": a.retired.spelling,
        "kind": (if cliRetiredIsFlag(a.retired): "flag" else: "subcommand"),
        "replacement": a.retired.replacement,
        "declaredIn": g.commands[a.declaredBy].path})
    result["retired"] = entries
  var children = newJArray()
  for child in cliHelpCommands(g, holder):
    children.add(commandJson(g, child, program))
  result["commands"] = children

proc cliHelpJsonNode*(g: CliGrammar; command: int; program: string): JsonNode =
  ## The machine-readable help of ``command`` as a JSON tree.
  result = newJObject()
  result["schema"] = %"clispec-help/1"
  result["program"] = %program
  result["command"] = commandJson(g, command, program)
  result["conventions"] = cliConventionsJson(g)
  var rules = newJArray()
  for r in g.parseRules:
    rules.add(%($r))
  var parsing = %*{"flagMatching": $g.flagMatching, "rules": rules}
  if g.commandMatching != cfmExact:
    parsing["commandMatching"] = %($g.commandMatching)
  result["parsing"] = parsing

proc cliHelpJson*(g: CliGrammar; command: int; program: string): string =
  ## The machine-readable help of ``command``, pretty-printed (see the module
  ## documentation for the schema).
  pretty(cliHelpJsonNode(g, command, program)) & "\n"
