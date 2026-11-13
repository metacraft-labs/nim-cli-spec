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
## * ``hidden`` items are never listed (they are still accepted);
## * ``internal`` items are listed only in the help of the command that holds
##   them — a subcommand in its parent's, a parameter in its declaring
##   command's, not in the commands that inherit it — and never in the help
##   of the root command, which is the program's primary help. An internal
##   command's own help is complete, so ``tool internal --help`` documents
##   the namespace that ``tool --help`` leaves out.
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
## groups were first declared. The text is not wrapped.
##
## Machine-readable form (schema ``clispec-help/1``)
## =================================================
##
## ``cliHelpJson`` describes a command and every command listed below it as
## one JSON object, with keys in a fixed order:
##
## .. code-block:: json
##   {"schema": "clispec-help/1", "program": "tool", "command": COMMAND}
##
## ``COMMAND`` is ``{"name", "path", "aliases", "help", "visibility",
## "usage", "parameters": [PARAMETER...], "commands": [COMMAND...]}`` and
## ``PARAMETER`` is ``{"name", "kind" ("flag" | "positional"), "spellings",
## "negation" (string or null), "value" ("none" | "required" | "optional"),
## "format" ("separate" | "equals" | "concat"), "valueName", "choices",
## "list", "separator" (string or null), "counted", "required", "default"
## (string or null), "env", "help", "group" (string or null), "visibility",
## "position" (positional only), "declaredIn", "dynamicCompletion",
## "completer" (string or null)}``. ``value`` says whether a flag takes a
## value and ``format`` how: ``separate`` flags take ``--flag=value`` or the
## next word, ``equals`` ones only ``--flag=value`` (an ``equals`` or
## ``concat`` alias is followed directly by the value, ``-DX``).
## ``choices`` is the closed value set (empty when open); ``completer`` is
## the ``complete`` expression as written, for a completion engine that
## calls it. The listing rules above decide which items appear. Within ``clispec-help/1`` keys are only ever added, never renamed
## or removed, and their meaning does not change; anything else is a new
## schema name.

import std/[json, strutils]

import ./[model, grammar]

func helpHolder(g: CliGrammar; command: int): int =
  ## The command whose help documents ``command``: a call:'s holder.
  if g.commands[command].isCall: g.commands[command].parent else: command

func cliListsCommand*(g: CliGrammar; holder, child: int): bool =
  ## Whether the help of ``holder`` lists its subcommand ``child``.
  case g.commands[child].visibility
  of cvShown: true
  of cvHidden: false
  of cvInternal: holder != 0

func cliListsParam*(g: CliGrammar; holder, id: int): bool =
  ## Whether the help of ``holder`` lists parameter ``id``.
  let p = g.params[id]
  case p.visibility
  of cvShown: true
  of cvHidden: false
  of cvInternal:
    holder != 0 and (p.declaredBy == holder or
      p.declaredBy == g.commands[holder].callChild)

func cliHelpParams*(g: CliGrammar; command: int): seq[int] =
  ## The parameters the help of ``command`` lists, in declaration order: its
  ## own (inherited ones included), then its call:'s.
  let holder = helpHolder(g, command)
  var all = g.commands[holder].params
  let call = g.commands[holder].callChild
  if call >= 0:
    for id in g.commands[call].ownParams:
      all.add(id)
  for id in all:
    if cliListsParam(g, holder, id):
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

func valuePlaceholder(p: CliGrammarParam): string =
  if p.choices.len > 0: p.choices.join("|")
  else: elementTypeName(p.valueName)

func takesValue(p: CliGrammarParam): string =
  if p.kind == cpkPositional: "required"
  elif p.isSwitch or p.counted: "none"
  elif p.hasOptionalValue: "optional"
  else: "required"

func flagLeft(p: CliGrammarParam): string =
  ## ``-j, --jobs <int>``, ``--[no-]verbose``, ``-l<string>, --libs=<string>``.
  let v = "<" & valuePlaceholder(p) & ">" &
    (if p.separator.len > 0: "[" & p.separator & "...]"
     elif p.isList: "..."
     else: "")
  let kind = takesValue(p)
  var parts: seq[string] = @[]
  if p.short != '\0':
    parts.add("-" & p.short)
  if p.alias.len > 0 and p.alias != "--" & p.name:
    if p.format == cafConcat and kind == "required":
      parts.add(p.alias & v)
    else:
      parts.add(p.alias)
  let long = if p.negatable: "--[no-]" & p.name else: "--" & p.name
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

func notes(p: CliGrammarParam): string =
  var parts: seq[string] = @[]
  if p.help.len > 0:
    parts.add(p.help)
  if p.required and p.kind == cpkFlag:
    parts.add("[required]")
  if p.hasDefault:
    parts.add("[default: " & p.defaultText & "]")
  if p.env.len > 0:
    parts.add("[env: " & p.env.join(", ") & "]")
  parts.join(" ")

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

func table(rows: seq[tuple[left, right: string]]): seq[string] =
  ## Two columns: the left one padded to its widest entry (at most 32
  ## characters; a longer entry puts its text on the next line).
  const maxLeft = 32
  var width = 0
  for row in rows:
    if row.left.len <= maxLeft:
      width = max(width, row.left.len)
  for row in rows:
    if row.right.len == 0:
      result.add("  " & row.left)
    elif row.left.len > maxLeft:
      result.add("  " & row.left)
      result.add("  " & repeat(' ', width + 2) & row.right)
    else:
      result.add("  " & row.left & repeat(' ', width - row.left.len + 2) &
        row.right)

proc cliHelpText*(g: CliGrammar; command: int; program: string): string =
  ## The human-readable help of ``command`` (see the module documentation).
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
    var rows: seq[tuple[left, right: string]] = @[]
    for child in children:
      let c = g.commands[child]
      rows.add(((@[c.name] & c.aliases).join(", "), c.help))
    lines.add("")
    lines.add("Commands:")
    lines.add(table(rows))
  let params = cliHelpParams(g, holder)
  var positional: seq[tuple[left, right: string]] = @[]
  let target = if cmd.callChild >= 0: cmd.callChild else: holder
  for id in cliPositionals(g, target):
    if id in params:
      positional.add((positionalLeft(g.params[id]), notes(g.params[id])))
  if positional.len > 0:
    lines.add("")
    lines.add("Arguments:")
    lines.add(table(positional))
  # Ungrouped flags, then each group in declaration order.
  var sections = @[""]
  for group in g.groups:
    sections.add(group.name)
  for section in sections:
    var rows: seq[tuple[left, right: string]] = @[]
    for id in params:
      let p = g.params[id]
      if p.kind == cpkFlag and p.group == section:
        rows.add((flagLeft(p), notes(p)))
    if rows.len == 0:
      continue
    lines.add("")
    if section.len == 0:
      lines.add("Options:")
    else:
      lines.add(section & ":")
      for group in g.groups:
        if group.name == section and group.help.len > 0:
          lines.add("  " & group.help)
    lines.add(table(rows))
  lines.join("\n") & "\n"

func paramJson(p: CliGrammarParam): JsonNode =
  result = newJObject()
  result["name"] = %p.name
  result["kind"] = %(if p.kind == cpkFlag: "flag" else: "positional")
  result["spellings"] = %cliFlagSpellings(p)
  result["negation"] = if p.negatable: %("--no-" & p.name) else: newJNull()
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
  for id in cliHelpParams(g, holder):
    params.add(paramJson(g.params[id]))
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

proc cliHelpJson*(g: CliGrammar; command: int; program: string): string =
  ## The machine-readable help of ``command``, pretty-printed (see the module
  ## documentation for the schema).
  pretty(cliHelpJsonNode(g, command, program)) & "\n"
