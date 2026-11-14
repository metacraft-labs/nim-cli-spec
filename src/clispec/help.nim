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
## Human-readable layout
## =====================
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
## groups were first declared. A value's placeholder is the declared
## ``valueName``, else the closed value set, else the type's name; a
## parameter's ``longHelp`` paragraphs follow its description, one per line.
##
## ``CliHelpLayout`` sets the indent, the description column, the width
## descriptions are wrapped to, a row for the help flag, the list marker,
## the order of a long alias and the notes; its defaults are the layout
## above, in which nothing is wrapped. ``cliOptionsTable`` renders just the
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
## ``COMMAND`` is ``{"name", "path", "aliases", "help", "visibility",
## "usage", "parameters": [PARAMETER...], "commands": [COMMAND...]}`` and
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
## ``parsing`` rules). ``placeholder`` is what help shows between ``<`` and
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
## parameters. Within ``clispec-help/1`` keys are only ever added, never renamed
## or removed, and their meaning does not change; anything else is a new
## schema name.

import std/[json, strutils]

import ./[model, grammar]

type
  CliHelpLayout* = object
    ## How the human-readable help lays its tables out. Every field's
    ## default is today's layout, so ``CliHelpLayout()`` renders exactly
    ## what ``cliHelpText`` always has.
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
      ## space; a word longer than the line is kept whole.
    helpFlag*: string = ""
      ## When not empty, the options table ends with a row for the help
      ## flag (``-h, --help``, the spellings that request help) with this
      ## description.
    listMarker*: bool = true
      ## A list flag's placeholder is followed by ``...``
      ## (``--tag <string>...``).
    canonicalFirst*: bool = false
      ## The canonical ``--<name>`` is listed before a long ``alias``
      ## (``--cooperative, --coop``); by default the alias comes first.
    notes*: bool = true
      ## A description ends with ``[required]``, ``[default: x]`` and
      ## ``[env: X]`` where they apply.

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
  ## The subcommands the help of ``command`` lists.
  let holder = helpHolder(g, command)
  for child in g.commands[holder].children:
    if cliListsCommand(g, holder, child):
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
  let core = "<" & p.name & ">" & (if p.repeated or p.isList: "..." else: "")
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

func table(rows: seq[HelpRow]; layout: CliHelpLayout): seq[string] =
  ## Two columns (see ``CliHelpLayout``): by default the left one padded to
  ## its widest entry (at most 32 characters; a longer entry puts its text
  ## on the next line), each paragraph of the description on a line of its
  ## own.
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
    let beside = if layout.column <= 0: row.left.len <= layout.maxLeft
                 else: left.len + 1 < column
    if body.len == 0:
      result.add(left)
    elif beside:
      result.add(left & repeat(' ', column - left.len) &
        body[0][column .. ^1])
      for line in body[1 .. ^1]:
        result.add(line)
    else:
      result.add(left)
      for line in body:
        result.add(line)

func helpFlagLeft(g: CliGrammar; command: int): string =
  ## The spellings that request help in ``command`` (``-h, --help``), for
  ## ``CliHelpLayout.helpFlag``; a spelling a flag of the command declares
  ## does not.
  var spellings: seq[string] = @[]
  for s in ["-h", "--help"]:
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

proc cliOptionsTable*(g: CliGrammar; command: int;
                      layout = CliHelpLayout(); group = ""): string =
  ## Just the rows of the options table of ``command``'s help, laid out by
  ## ``layout``: the flags of the section ``group`` (empty: the flags in no
  ## group, under ``Options:``, followed by the help flag's row when
  ## ``layout.helpFlag`` is set), one line per output line, each ending
  ## with a newline. Empty when the section has no rows.
  let holder = helpHolder(g, command)
  let rows = optionRows(g, holder, cliHelpParams(g, holder), group, layout)
  for line in table(rows, layout):
    result.add(line & "\n")

proc cliHelpText*(g: CliGrammar; command: int; program: string;
                  layout = CliHelpLayout()): string =
  ## The human-readable help of ``command`` (see the module documentation),
  ## its tables laid out by ``layout``.
  let holder = helpHolder(g, command)
  let cmd = g.commands[holder]
  var lines = @["Usage: " & cliUsageLine(g, holder, program)]
  var help = cmd.help
  if help.len == 0 and cmd.callChild >= 0:
    help = g.commands[cmd.callChild].help
  if help.len > 0:
    lines.add("")
    lines.add(help)
  if cmd.aliases.len > 0:
    lines.add("")
    lines.add("Aliases: " & cmd.aliases.join(", "))
  let children = cliHelpCommands(g, holder)
  if children.len > 0:
    var rows: seq[HelpRow] = @[]
    for child in children:
      let c = g.commands[child]
      rows.add(((@[c.name] & c.aliases).join(", "),
        (if c.help.len > 0: @[c.help] else: @[])))
    lines.add("")
    lines.add("Commands:")
    lines.add(table(rows, layout))
  let params = cliHelpParams(g, holder)
  var positional: seq[HelpRow] = @[]
  let target = if cmd.callChild >= 0: cmd.callChild else: holder
  for id in cliPositionals(g, target):
    if id in params:
      positional.add((positionalLeft(g.params[id]),
        paragraphs(g.params[id], layout)))
  if positional.len > 0:
    lines.add("")
    lines.add("Arguments:")
    lines.add(table(positional, layout))
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
      lines.add("Options:")
    else:
      lines.add(section & ":")
      for group in g.groups:
        if group.name == section and group.help.len > 0:
          lines.add(repeat(' ', layout.indent) & group.help)
    lines.add(table(rows, layout))
  lines.join("\n") & "\n"

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
  result["visibility"] = %($cmd.visibility)
  result["usage"] = %cliUsageLine(g, holder, program)
  var params = newJArray()
  for id in cliHelpParams(g, holder, machineReadable = true):
    params.add(paramJson(g, g.params[id]))
  result["parameters"] = params
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
  result["parsing"] = %*{"flagMatching": $g.flagMatching, "rules": rules}

proc cliHelpJson*(g: CliGrammar; command: int; program: string): string =
  ## The machine-readable help of ``command``, pretty-printed (see the module
  ## documentation for the schema).
  pretty(cliHelpJsonNode(g, command, program)) & "\n"
