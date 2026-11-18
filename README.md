# nim-cli-spec

Clispec is a Nim library for describing a command line once, declaratively,
and deriving everything else from that description. This release provides:

- **`clispec/model`**: a typed model of a command tree: commands and
  subcommands with their aliases, help and visibility; positional parameters
  and flags with their types, spellings, formats, placement, defaults,
  environment variables, configuration keys, permitted sources, merge rules,
  value sets, completers and implications.
- **`clispec/dsl`**: the `cli:` description language, parsed at compile time
  into that model.
- **`clispec/program`**: `cliProgram`, which generates from a description a
  typed configuration object, the parser that fills it from argv, and help
  text in human-readable and machine-readable (JSON) form. The run-time
  pieces it generates code for are `clispec/grammar` (the parser's tables),
  `clispec/parser`, `clispec/help`, `clispec/values` (text to typed values)
  and `clispec/errors` (the usage-error taxonomy).
- **Shell completion** for Bash, Zsh, Fish and PowerShell: one completion
  engine generated from the description (`clispec/completion`), which the
  program runs itself, and a thin script per shell that asks it
  (`clispec/completion_scripts`). Completers (`clispec/completers`) supply
  values that are known only at run time.

Clispec depends on nothing but the Nim standard library. It also describes
the command lines of external tools that a program runs.

### Clispec and confutils

Clispec owns the command line: the description language, the model, and
from them the configuration object type, the argv parser, help and shell
completion. Everything beyond the command line is
[confutils](https://github.com/metacraft-labs/nim-confutils)' job (a fork of
[status-im/nim-confutils](https://github.com/status-im/nim-confutils)), which
can be instantiated over a clispec description:

```text
cli: description ──▶ clispec model ──▶ configuration type, argv parser,
                          │             help, completion           (clispec)
                          └──▶ configuration-file layers, the environment,
                               merge rules, binding layers, the origin
                               object, file formats (TOML)        (confutils)
```

A clispec description declares what those other sources need per parameter
(`env`, `key`, `sources`, `merge`, `configSchema`, the naming conventions),
because the description is the single source of truth; confutils reads the
declarations from the model and delegates parsing, help and completion to the
code clispec generates, so a program's command line behaves the same whether
or not it reads configuration files. A program that only parses its command
line uses clispec alone (`Tool.load(argv)`); one that also reads
configuration files and the environment uses confutils' `cliConfiguration`,
which takes the same description. See
[Configuration files, the environment and origins](#configuration-files-the-environment-and-origins).

## The `cli:` language

```nim
import clispec

const tool = plainCliModel:
  # Flags directly under `cli:` go before the subcommand word.
  flag config is string, alias = "--config", format = equals

  call:                      # the anonymous command: `tool [args]`
    boolFlag verbose is bool, alias = "-v"
    pos sources is seq[string], repeated = true

  subcmd "link":             # `tool link [args]`
    flag output is string, alias = "-o", required = true
    flag libs is seq[string], alias = "-l", format = concat, repeated = true
    pos objects is seq[string], position = 1
```

| Declaration                 | Meaning                                        |
| --------------------------- | ---------------------------------------------- |
| `pos <name> is <Type>`      | a positional parameter, required by default    |
| `flag <name> is <Type>`     | a flag that takes a value, optional by default |
| `boolFlag <name> [is bool]` | a switch                                       |
| `call:`                     | the command run without a subcommand word      |
| `subcmd "<name>":`          | a named subcommand; scopes nest                |

Named arguments after a flag: `alias = "<spelling>"` (the exact spelling, for
example `-o` or `--output=`), `required = true`, `repeated = true` (one
occurrence per list element), `format = separate | concat | equals` (`-o x`,
`-ox`, `--flag=x`) and `placement = after | before` (relative to the
subcommand word). After a positional: `position = <n>`, `repeated = true` and
`required = false` (a positional is required unless it says otherwise or has a
`default`).
A `boolFlag` takes named arguments in the bare form (`boolFlag verbose,
alias = "-v"`) as well as after `is bool`.

A nested scope sees every parameter its enclosing scopes declared before it
opened. `plainCliModel` returns a `CliModel` whose `root` is the scope directly
under `cli:`, whose `commands` lists every `call:` and `subcmd` scope, and
whose `groups` lists the `group` sections.

### What a program declares about its own command line

```nim
import clispec

type Color = enum red, green, blue
proc repoNames(ctx: CliCompletionContext): seq[CliCompletion] =
  cliCompletions(["app", "lib"])

const app = plainCliModel:
  help "Builds and checks projects"
  flag config is string, short = 'c', env = ["APP_CONFIG"], sources = {cli, env}
  boolFlag verbose is bool, negatable = true, help = "talk more"
  flag quiet is int, counted = true, short = 'q'
  group "Output", help = "Where results go":
    flag writeReport is string, optionalValue = "report.json",
      key = "reports.path"
    flag color is Color, default = green
  subcmd "build", help = "Build a project", aliases = ["b"]:
    flag jobs is int, default = 4, merge = errorOnConflict,
      implies = [verbose = true]
    flag tags is seq[string], separator = ",", merge = append,
      values = ["fast", "safe"]
    flag repo is string, complete = repoNames
    pos target is string, default = "all"
  subcmd "debug-dump", visibility = hidden:
    pos path is string
```

Every parameter accepts:

| Argument                                                         | Meaning                                                                                                                                                                                                                                                                                         |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `help = "<text>"`                                                | the description shown by help and completion; a constant string expression too (a `const`, `&` of literals and constants, a `when` expression), evaluated at compile time where the description is                                                                                              |
| `longHelp = "<text>"`                                            | further paragraphs of description, one per line, shown below `help` (a constant string expression too)                                                                                                                                                                                          |
| `valueName = "<text>"`                                           | the placeholder help shows for the value (`--output <path>`) instead of the closed value set or the type's name; a missing value's error carries it in `expected`                                                                                                                               |
| `default = <expr>`                                               | the value when no source supplies one; not together with `required = true`. A positional with a default is optional                                                                                                                                                                             |
| `env = ["NAME", ...]`                                            | the environment variables that supply the value, first match wins (one name may be written without brackets)                                                                                                                                                                                    |
| `values = [a, b, c]`                                             | the closed set of accepted values (elements, for a list); an enum type is a closed set by itself                                                                                                                                                                                                |
| `complete = <completer>`                                         | a `CliCompleter` that completes the value dynamically (see [Shell completion](#shell-completion))                                                                                                                                                                                               |
| `key = "section.name"`                                           | the configuration-file key, replacing the derived one                                                                                                                                                                                                                                           |
| `sources = {cli, env, file}`                                     | which sources may supply the value (default: all three). `sources = {}`: none does directly; the parameter has no spelling and no key, and gets its value from another flag's `alsoSets`, an `implies` or its `default`                                                                         |
| `merge = replace \| append \| errorOnConflict \| <combine proc>` | how values from several sources combine: the highest source wins (a list repeated within one source collects); lists are concatenated lowest source first; two different values are an error; or a proc of yours receives every source's value (applied by confutils, which merges the sources) |
| `separator = ","`                                                | a list may be given as one delimited value                                                                                                                                                                                                                                                      |
| `implies = [<param> = <value>, ...]`                             | setting this parameter sets the others unless they are given explicitly                                                                                                                                                                                                                         |
| `visibility = shown \| internal \| hidden`                       | `internal`: a parameter is accepted but shown in no help screen and never offered by completion; a command is left out of the primary help and completion and listed by the command that holds it. `hidden`: accepted and listed nowhere                                                        |

A flag also accepts `short = 'x'` (a one-letter spelling, `-x`, beside
`--<name>`), `optionalValue = <expr>` (the flag may appear bare, taking this
value, or as `--flag=value`; it never takes the next word), `negatable = true`
(`--no-<name>` sets a `bool` to false) and `counted = true` (`-v`, `-vv`: an
integer counting the occurrences). Three more are opt-in rules that
confutils' type-based loader followed (see
[Command lines from confutils' type-based loader](#command-lines-from-confutils-type-based-loader)):
`acceptsNextWord = true` (with `optionalValue`: written bare, the flag also
takes the next word as its value when that word is a valid value),
`refuseFalse = true` (a switch refuses `--flag=false`) and
`alsoSets = [<param> = "<text>", ...]` (each occurrence also gives another
parameter a value, in command-line order).

A positional also accepts `position = <int>`, `repeated = true`,
`afterSeparator = true` and `rest = true` (an opt-in rule of
[confutils' type-based loader](#command-lines-from-confutils-type-based-loader)).
`afterSeparator = true`, on a list positional (a `seq`) that is the last
positional of its command, makes it the words after `--`: the shape of
`env [<assignments>] -- <command>...` and `cargo run -- <args>...`. Only
the words after the first `--` fill it, exactly as written (a later `--`,
`--help` and words that look like flags included, never split on a
`separator`), and no word before that `--` does: those go to the other
positionals, and one that none of them takes is the usage error
`cekUnexpectedPositional`. A `--` that is a flag's value (`--root --`,
`--root=--`, `-r --`) is that value and ends nothing. In a command with
subcommands, the `--` that counts is the one read in the command that
runs, as for any other `--`.

```nim
import std/strutils
import clispec

cliProgram(Exec, "exec"):
  flag root is string, default = ""
  pos selector is string, required = false
  pos command is seq[string], required = false, afterSeparator = true

let e = Exec.load(@["proj", "--", "ls", "-la", "--"])
assert e.selector == "proj" and e.command == @["ls", "-la", "--"]
let f = Exec.load(@["--", "ls"])
assert f.selector == "" and f.command == @["ls"]
assert Exec.load(@["--root", "--", "--", "ls"]).root == "--"
assert "Usage: exec [options] [<selector>] [-- <command>...]" in
  Exec.helpText()
```

Help writes it after its `--`, `[-- <command>...]` (`-- <command>...` when
it is required), completion after `--` offers its values alone, and the
JSON marks it `"afterSeparator": true`. Declaring it on a flag, on a type
that is not a `seq`, together with `rest`, `repeated` or `separator`, with
`sources` that exclude `cli`, on a positional that is not the last of its
command (so on two positionals of one command), or under `parsing
loneDashesAreFlags` (where `--` ends nothing) is a compile error.

A command takes `help`, `longHelp`, `aliases` and `visibility` in its head
(`subcmd "build", help = "...", aliases = ["b"]:`, `call(help = "..."):`),
and a subcommand `shadowedByWord = true` (see `helpWord` below) and
`tier = primary | secondary` (see
[Command groups and tiers](#command-groups-and-tiers)), or
its help as a `help "<text>"` statement in its body, which is also how the
root command gets one; likewise `longHelp "<text>"`, and any number of
`example "<command line>", help = "<text>"` statements (see [Help](#help)), and
`retired "<spelling>", replacement = "<text>"` statements (see [Retired
spellings](#retired-spellings)). `group "<title>"[, help = "<text>"]:` lists the
parameters declared inside it under one heading in help; it opens no command
and changes no scoping, and may be reopened (in another command, say) to add
more parameters to the same heading. Around `subcmd` statements it is a
command group instead: help lists those subcommands under its heading
rather than `Commands:`. One title lists parameters or subcommands, not
both.

**Names.** A parameter's name is its canonical long flag (`output` is
`--output`); `alias` adds a spelling. Its configuration-file key is the path of
the command that declares it followed by its name, joined with `.`: `jobs`
above is `build.jobs`, `color` is `color`. Both are spelt in their source's
naming convention, below, which by default is the name as declared. A parameter
inherited by nested commands keeps the key of the command that declared it.
`key` replaces the derived key, and a parameter whose `sources` exclude
`file` has none. Environment variables are never derived: a parameter reads
exactly the variables its `env` lists.

`configSchema "<id>"` directly under `cli:` names the schema identifier
every configuration file must declare (configuration files are read by
confutils; see
[Configuration files, the environment and origins](#configuration-files-the-environment-and-origins)).

**Naming conventions.** Each source spells names in one convention:
`declared` (exactly as written, the default for every source), `camelCase`,
`snakeCase` or `kebabCase`. A description sets it once per source, directly
under `cli:`:

```text
convention cli = kebabCase         # the command line's long flags
convention file = snakeCase        # every configuration file
convention "project" = kebabCase   # the layer (or format) named "project"
```

`keyStyle <convention>` is the older spelling of `convention file = ...`.
Under these, `flag writeReport` is `--write-report` on the command line,
`write_report` in a configuration file and `write-report` in the layer named
`project`; a subcommand path segment of a key is converted the same way.
Subcommand words, `alias` and `short` are used as written, and environment
variables are never derived, so no convention applies to them. The default
keeps keys equal to the parameter names, as confutils does (its
configuration-file keys are the field names, or the `name` pragma's
spelling).

`cliConvert(name, convention)` is the one function every spelling goes
through. It splits a name into words (`cliWords`): letters, digits and
non-ASCII bytes are word characters and anything else (`-`, `_`, `.`) ends a
word; an upper-case letter after a lower-case letter or a digit starts a new
word (`writeReport`, `sha256Sum`), and so does the last capital of an acronym
when a lower-case letter follows it (`HTTPPort` is `HTTP` + `Port`); digits
stay with the word before them (`ipv6Address` is `ipv6` + `Address`).
`snakeCase` and `kebabCase` lower-case the words and join them with `_` and
`-`; `camelCase` lower-cases the first word and capitalises the first letter
of the others (`HTTPPort` is `httpPort`, `user_id` is `userId`). A conversion
can lose what the words do not record, which is what overrides are for.

Overrides are opt-in and refine the conversion for one parameter:

- `perConvention = [kebabCase = "base-url", ...]` gives the parameter's name
  in one convention, for every source that uses it (an acronym, or a word
  the splitter divides wrongly). In a key it replaces the last segment.
- `perSource = [cli = "port", "project" = "web.port"]` gives the long flag
  (without `--`) on the command line, or the whole key, used as written, in
  one named file source. `key = "<dotted.key>"` is this override for every
  file source.

The most specific one wins: the source's own override (a named source's
`perSource` entry, then `key`), then the override for the source's
convention, then the conversion. The model records every source's spelling
(`longName`, `configKey`, and `sourceKeys` per named file source), so help,
the machine-readable help and, in confutils, the configuration schema and
the origin object all show the spelling each source uses.

```nim
import clispec

cliProgram(Srv, "srv"):
  configSchema "srv.config.v1"
  convention cli = kebabCase
  convention file = snakeCase
  convention "project" = kebabCase
  flag writeReport is string
  flag httpPort is int, perSource = [cli = "port", "project" = "web.port"]
  flag urlBase is string, perConvention = [kebabCase = "base-url"]

let conf = Srv.load(@["--write-report", "r.txt", "--port", "80",
  "--base-url", "/"])
assert conf.writeReport == "r.txt" and conf.httpPort == 80
const model = Srv.cliModel
assert model.root.params[0].configKey == "write_report"
assert model.root.params[1].longName == "port"
assert model.root.params[1].sourceKeys[0].spelling == "web.port"
assert model.root.params[2].sourceKeys[0].spelling == "base-url"
```

**Expressions.** `default`, `optionalValue`, `values`, the values of `implies`,
`complete` and a combine proc are Nim expressions. The model keeps each as a
`CliExpr`: its source text and where it was written. Code generated from the
model turns the text back into an AST with `parseExpr`, in the scope that holds
the description, so the identifiers resolve as the author wrote them.

**Invalid declarations are compile errors** naming the parameter (or the
command): a name declared twice in one command (Nim's style-insensitive
comparison, inherited parameters included), a `short`, `alias` or `--<name>`
spelling used twice among the flags of one placement, a configuration key used
twice, a `default`, `optionalValue`, `values` entry or `implies` value that is
not a value of the parameter's type, `default` or `optionalValue` together with
`required = true`, `key` when `sources` exclude `file`, `env` when they exclude
`env`, `counted` on a non-integer, `negatable` on a non-`bool`, a counted flag
that is also negatable or has an `optionalValue`, `negatable` or `counted`
set to anything but `true` or `false`, a flag-only argument on a positional, an
`implies` naming no parameter of the command, an `alsoSets` naming no
parameter of the command, the parameter itself, one parameter twice, or
giving a value that is not a string literal, `acceptsNextWord` without
`optionalValue`, `refuseFalse` on a non-`bool` or together with
`negatable`, a `help` or `longHelp` that is not a constant string
expression, an unknown `parsing` rule, `flagMatching` or `commandMatching` mode, an argument given twice, two
subcommands of one command answering to the same word (compared under
`commandMatching`), a subcommand answering to `help` under `parsing
helpWord` or to `version` under `versionWord` without `shadowedByWord =
true`, `shadowedByWord` on a subcommand that answers to neither (or on
`call:`), `tier` on `call:` or set to anything but `primary` or
`secondary`, a `call:` inside a `group` section, a group title that lists
both subcommands and parameters, `rest` on a flag, on a type
that is not a `seq` or together with `repeated`, `afterSeparator` on a
flag, on a type that is not a `seq`, together with `rest`, `repeated` or
`separator`, or with `sources` that exclude `cli`, `aliases` on `call:`,
a `help` statement inside a `group` section (the section's help goes in
its head), a command's `longHelp` given twice, an `example` without its
`help`, with an empty command line, with a text that is not a string
literal (or `&` of literals) or with another argument, a `retired`
statement that breaks the rules of [Retired spellings](#retired-spellings), `keyStyle`, `convention`, `configSchema`, `flagMatching`,
`commandMatching` or `parsing` anywhere but directly under `cli:`, an unknown convention or one source's convention given twice,
a `perConvention` entry for `declared` or for one convention twice, a
`perSource` entry for a file source the description does not declare, for
`file` (that is `key`), for one source twice, for `cli` on a positional or
when `sources` exclude `cli`, or for a file source when they exclude `file`,
and two parameters of one command whose long flags or keys in one source
come out the same once converted and overridden. The generated checks also reject
`merge = append` on a parameter that is neither a `seq` nor counted, a
combine proc that does not have the signature below, and a `complete`
expression that is not a `CliCompleter`. In a `cliProgram` that
declares a `configSchema`, a configuration key that is `schema` or lies
under `extensions` is an error too: both belong to the file itself; so is,
in any `cliProgram`, a `rest` positional that is not the last positional of
its command or follows a `repeated` one, and an `afterSeparator` positional
that is not the last positional of its command (which also rules out two
in one command) or is declared under `parsing loneDashesAreFlags`.

The parser rejects what it can tell from spellings. Whether an expression is a
value of a type needs the compiler, so `cliModelTypeChecks(model)` generates
those checks as code; `plainCliModel` places them in its output, and a
consumer's own macro places them in its output the same way.

### Parameter groups

A parameterless template whose body is a list of declarations can be shared
between commands by naming it as a statement. A front end that accepts groups
reads them with `collectCliParamGroup` and expands them with
`expandCliParamGroups`:

```nim
template commonFlags() =
  boolFlag verbose is bool, alias = "-v"
  flag defines is seq[string], alias = "-D", format = concat, repeated = true
```

A group whose body starts with `help "<text>"` is also a help section: it
expands into a `group "<template name>", help = "<text>":` section, so the
parameters it declares carry the group in the model.

### Exporting a command line for another program to mount

A program whose command line another program also accepts (a monitor that a
build tool offers under one of its own commands, say) can export its
description as a compile-time proc returning a `cli:` body. The other program
splices the body under the `subcmd` that mounts it, so both generate their
parser, help and completion from the same declarations.

Such a proc usually builds the body with `quote`, which binds every name to
a symbol of the proc's own scope: `afterSeparator = true` then names the
symbol `system.true`, `seq[string]` becomes a call of the `[]` operator, and
a group of declarations spliced in is a statement list nested inside the
body. The `cli:` language reads a body as written, so the exporting proc
returns `cliUnbound` of what `quote` gave it (`clispec/splice`, which imports
only `std/macros`): symbols become the identifiers they were written as,
`[]` calls become bracket expressions, string literals joined with `&` are
folded into one literal, and nested statement lists are flattened, with the
line information kept.

```nim
import std/macros
import clispec

proc sharedFlags(): NimNode {.compileTime.} =
  quote do:
    boolFlag verbose is bool, alias = "-v"

proc toolBody(): NimNode {.compileTime.} =
  let shared = sharedFlags()
  cliUnbound(quote do:
    subcmd "run", help = "Run a command " & "under the tool":
      `shared`
      pos command is seq[string], required = false, afterSeparator = true)

macro mountTool(): untyped =
  let body = toolBody()
  result = quote do:
    cliProgram(Host, "host"):
      subcmd "tool", help = "The tool's commands":
        `body`

mountTool()

let conf = Host.load(@["tool", "run", "-v", "--", "make", "all"])
assert conf.tool.run.verbose
assert conf.tool.run.command == @["make", "all"]
```

## A program's own command line

`cliProgram` turns a description into a configuration object type and the
procedures that fill it, in the style of confutils: you declare the command
line once and get back a fully populated, typed value.

```nim
import std/options
import clispec

type Color = enum red, green, blue

cliProgram(Tool, "tool"):
  help "Builds things"
  boolFlag verbose is bool, short = 'v', negatable = true, help = "Talk more"
  flag quiet is int, counted = true, short = 'q', help = "Talk less"
  subcmd "build", help = "Build a project", aliases = ["b"]:
    flag jobs is int, short = 'j', default = 4, implies = [verbose = true],
      help = "Parallel jobs"
    flag color is Color, default = green
    flag tags is seq[string], separator = ",", values = ["fast", "safe"]
    flag report is string, optionalValue = "report.json"
    flag limit is Option[int]
    pos target is string, help = "What to build"
  subcmd "run", help = "Run a script":
    call:
      pos script is string
      pos args is seq[string], repeated = true, required = false

let conf = Tool.load(@["-v", "build", "-j8", "--tags=fast,safe", "--report",
  "app"])
assert conf.verbose and conf.command == ToolCommand.build
assert conf.build.jobs == 8 and conf.build.color == green
assert conf.build.tags == @["fast", "safe"]
assert conf.build.report == "report.json" and conf.build.target == "app"
assert conf.build.limit.isNone

let run = Tool.load(@["-qq", "run", "x.sh", "--", "-n"])
assert run.quiet == 2 and run.run.script == "x.sh" and run.run.args == @["-n"]

# In a real program: `Tool.load()` reads the process's arguments.
proc main(argv: seq[string]): int =
  try:
    let conf = Tool.load(argv)
    discard conf # ... run the program ...
  except CliHelpRequest as e:   # help, the version, completion requests
    Tool.printHelp(e)           # to stdout
  except CliUsageError as e:
    Tool.printError(e)          # to stderr
    return e.exitCode

assert main(@["build", "--jobs", "many", "app"]) == 2
assert main(@["--help"]) == 0
```

### The configuration object

Each command gets an object type with one field per parameter it declares,
named and typed as declared: the root's is the name given to `cliProgram`
(`Tool`), a subcommand's is its parent's name followed by its word in
CamelCase (`ToolBuild`; `debug-dump` would be `ToolDebugDump`). A command
with subcommands holds the chosen one in a case object: a discriminator
`command` of the pure enum `<Type>Command`, with one value per subcommand
word in camelCase, and a branch field of the same name holding that
subcommand's object. Subcommands are nested objects rather than fields of
one flat case object because Nim requires field names to be unique across
all branches, and two subcommands may well both declare `--output`; the case
branch keeps only the chosen subcommand's object in existence. A `call:`
adds its parameters to the object of the command holding it when that
command has no subcommands (`run` above); next to subcommands it is one more
branch, `call`, of type `<Type>Call`. A parameter is a field of the command
that declares it, even though nested commands accept it too.

A field holds the value from the command line, else the value that an
`implies` of a parameter given on the command line sets (the first such, in
declaration order; implications do not chain), else its `default`, else the
type's zero value (`none` for an `Option`). A `required` parameter that gets
no value is a usage error. Supported types are `string`, `bool`, `char`,
every integer and float type (range types included, bounds checked), enums,
distinct types over these (`std/paths.Path`), `Option[T]` and `seq[T]`.
Declare `proc parseCliValue(text: string; value: var YourType)` (raising
`CliValueError`) to support another. `values` entries must be constant
expressions; those of a `seq[T]` or `Option[T]` parameter are values of `T`.

Generated for `Tool` (exported when written
`cliProgram(Tool, "tool", exported = true):`):

| Procedure                                                                          | Does                                                                                                                                                  |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Tool.load(argv, options = CliOptions())`                                          | parses `argv` (without the program name)                                                                                                              |
| `Tool.load(options = CliOptions())`                                                | parses the process's own arguments                                                                                                                    |
| `Tool.helpText(path = [], layout, long, styled, all)` / `Tool.helpJson(path = [])` | the help of the command reached by the subcommand words `path` (`long`: the `--help` page; `styled`: in the `portable16` palette; `all`: `secondary` subcommands too; `Tool.helpText(path, style)` renders with a `CliStyle`, see [Colour and width](#colour-and-width)) |
| `Tool.optionsTable(path = [], layout, group = "", long, styled)`                   | just the rows of that command's options table (see [Help](#help))                                                                                     |
| `Tool.printHelp(e, stream = stdout)` / `Tool.printError(e, stream = stderr)`       | print a help request or a usage error as `cliPrintHelp` / `cliPrintError` do, under the program's own colour configuration (see [Colour and width](#colour-and-width)) |
| `Tool.complete(words, cursor = -1)`                                                | the completion candidates for `words[cursor]` (the last word by default)                                                                              |
| `Tool.completionScript(shell)` / `Tool.completionReply(args)`                      | a shell's completion script; the answer to a script's request                                                                                         |
| `Tool.cliGrammar` / `Tool.cliModel`                                                | the parser's tables and the model, both constants                                                                                                     |
| `Tool.canonicalArgv(argv, only = [], group = "", commandWords = true)`             | `argv` written back in canonical form, or just the parameters `only` names (see [Writing a command line back](#writing-a-command-line-back))          |

`CliOptions` sets the program name used in messages, the exit code of usage
errors (`usageExitCode`, 2 when not set), `disableHelpFlag`, the word
through which completion scripts ask for candidates (`completionEntry`,
`__complete` when not set; `disableCompletionEntry` turns it off), the
layout of the help a `CliHelpRequest` carries (`helpLayout`,
`cliDefaultHelpLayout` unless set; see [Help](#help)), and
`valueCheck`, which says whether a text is a valid value of a parameter and
which the generated `load` fills in (a library that calls the parser itself
passes `cliWithValueCheck(options, <the generated check>)`, as confutils
does). A consumer
whose model carries an extension generates the same code from its own macro
with `cliProgramCode(model, typeName, program, exported, colorConfig)`
(`cliProgramArgs` reads a `cliProgram`-style call, colour parameters
included, into `CliProgramArgs`).

### Accepted forms

- `--name` is every flag's canonical spelling; `alias` adds a spelling and
  `short = 'x'` adds `-x`.
- A flag that takes a value accepts `--flag=value` on any `--` spelling. With
  `format = separate` (the default) it also takes the next word, whatever it
  looks like; with `format = equals` it never does; with `format = concat`
  the value follows the spelling directly (`-DFOO`).
- Short spellings follow POSIX `getopt`: `-j 4`, `-j4`, and switches cluster
  (`-vqq`); a letter that takes a value takes the rest of the word, or the
  next word when it is last.
- A `bool` is a switch: bare it is `true`, `--flag=false` works, and
  `negatable = true` adds `--no-<name>`. `counted = true` counts
  occurrences. An `optionalValue` flag is bare or `--flag=value`, never
  followed by its value as a separate word (unless it declares
  `acceptsNextWord`, below).
- A `seq` collects every occurrence, each split on its `separator` if it has
  one. Any other parameter given twice keeps its last value.
- `--` ends the flags (unless `parsing loneDashesAreFlags`, below, makes
  it an unknown flag). In a command that declares an `afterSeparator`
  positional, every word after it is that positional's, exactly as
  written. The first bare word after a command with subcommands names one
  (or one of its `aliases`); when the command also has a `call:`, any
  other word, or a flag (or a cluster of short flags) that only the
  `call:` declares, runs the `call:`. A word runs the `call:` only when the
  `call:` declares a positional (or the word follows `--`); beside a `call:`
  that holds only flags, a word that names no subcommand is
  `cekUnknownSubcommand`.
- Positionals fill in `position` order; a list positional takes every word
  that the positionals after it do not need. A command with subcommands
  declares its positionals in its `call:` (the word after it is a
  subcommand word), which `cliProgram` enforces at compile time, along with
  at most one list positional per command and no subcommands inside a
  `call:`.
- `hidden` and `internal` items are accepted like any other.

### Writing a command line back

A program sometimes hands part of its command line to another one: a `test`
command that runs a `build` passes on the build flags it was given, and a
front end that re-executes itself elsewhere passes on what it parsed.
Copying the original words does not work once only some parameters travel
(a value may be the next word, short flags cluster, a value can look like a
flag), and writing them by hand repeats the grammar. `cliArgvOf`
(`clispec/render`) writes them from the grammar and the occurrences the
parser recorded, and the generated `Tool.canonicalArgv` does it for a
command line:

```nim
import clispec

cliProgram(Tool, "tool"):
  boolFlag verbose is bool, short = 'v', negatable = true
  flag log is string, default = "info"
  flag variant is seq[string]
  boolFlag release is bool, alsoSets = [variant = "buildType=release"]
  flag jobs is int, default = 1, implies = [verbose = true]
  subcmd "build", aliases = ["b"]:
    flag workers is int, short = 'j', default = 4
    pos targets is seq[string], required = false
    pos command is seq[string], required = false, afterSeparator = true

let argv = @["-v", "b", "-j8", "--log", "--x", "--release", "app", "--",
  "make", "-k"]
let words = Tool.canonicalArgv(argv)
assert words == @["build", "--verbose", "--workers=8", "--log=--x",
  "--release", "app", "--", "make", "-k"]
assert $Tool.load(words) == $Tool.load(argv)

# Some parameters only, without the subcommand words: what a command that
# shares these flags with another passes on.
assert Tool.canonicalArgv(argv, only = ["log", "release", "variant"],
  commandWords = false) == @["--log=--x", "--release"]

# A value an implication or a default gave is not the command line's.
assert Tool.canonicalArgv(@["--jobs=2", "build"]) == @["build", "--jobs=2"]
```

The words parse, with the same description, to the same values, and each
value they supply comes from the command line again; parsed together with
the same environment and configuration files (confutils), they give the
same configuration. A value that came from anywhere else (a default, an
`implies`, an environment variable, a file) is never written, because the
parser reading the words supplies it again. The spellings:

- every flag in its long spelling, `--<name>`, whatever spelling was used
  (`-j8`, an alias, a cluster); `hidden` and `internal` flags like any
  other; a `retired` spelling never, since the parser refuses it;
- a value attached, `--name=value`, so a value that starts with `-`, is
  `--` or is empty stays that flag's value (under `parsing
  equalsTakesNext`, an empty value of a `format = separate` flag is written
  as two words, `--name` and the empty word);
- a switch as `--name` or `--no-name` (`--name=false` when it is not
  negatable), a counted flag once per occurrence, an `optionalValue` flag
  bare or with `=value`, a list one word per occurrence in order;
- a value another flag's `alsoSets` gave as that flag, at its position,
  when that flag is selected, else as the parameter's own value;
- the subcommand words (canonical names; an alias where `parsing helpWord`
  or `versionWord` would read the name as a request), then the flags in the
  order they were given, then the positionals in position order, and the
  words of an `afterSeparator` positional last, after `--`, exactly as
  they were;
- `--` before the positionals when one would otherwise be read as
  something else (a word that starts with `-`; beside a `call:`, a
  subcommand word), and after a flag that would take the next word as its
  value (a bare `acceptsNextWord` flag); where `--` would start an
  `afterSeparator` positional instead, a flag that can move without
  changing a value is written after that flag, or else the flags follow
  the positionals.

`only` names parameters by their declared names (compared as Nim compares
identifiers) and `group` selects a parameter group; a name the parsed
command does not hold is skipped, so the flags of one command select the
same flags of another, while a name no parameter has, or a group with no
parameters, raises `ValueError`. Two things a selection cannot keep:
positionals are positional, so select a command's positionals together; and
a flag whose `alsoSets` gives another parameter a value brings that value
when the words are read back, selected or not. The words are written from
the occurrences the parser recorded, not from values, so a configuration
built or changed in code has no command line to write.
`cliArgvOf(g, selected, given, params)` is the same over candidates a caller holds (confutils'
origin object records them for every value; see
[Configuration files, the environment and origins](#configuration-files-the-environment-and-origins)),
with `cliRenderParams` for the selection.

### Command lines from confutils' type-based loader

A program whose command line was a confutils configuration type (an object
whose fields carry `{.name.}`, `{.abbr.}`, `{.desc.}`, `{.longDesc.}`,
`{.valueName.}`, `{.implicitValue.}` and `{.alsoSets.}` pragmas, loaded with
`negatableSwitches = false`) can move onto a clispec description without a
change its users can see. What that loader did differently from clispec's
defaults is available as opt-in declarations; none changes a description
that does not name it.

Directly under `cli:`:

- `flagMatching ignoreCase | ignoreStyle | exact`: how a word is compared
  with flag spellings when no spelling matches it exactly (`exact`, the
  default, accepts only exact ones). `ignoreCase` ignores ASCII case, in
  long spellings, short letters (`-O` for `-o`, unless `parsing
exactOneLetterFlags` keeps them exact) and `--help`. `ignoreStyle`
  compares as Nim's `cmpIgnoreStyle` does, which is what the loader did:
  ASCII case and every `_` are ignored and every other character must
  match, so `--CHECKPOINT-INTERVAL` and `--check_point-interval` are
  `--checkpoint-interval` while `--checkpoint_interval`,
  `--checkpointInterval` and `--checkpointinterval` are not.
- `commandMatching ignoreCase | ignoreStyle | exact`: the same modes for
  subcommand words (names and `aliases`), wherever one is resolved: the
  parser, `helpText`/`helpJson` paths and completion. Under `ignoreStyle`
  (`cmpIgnoreStyle` over the whole word, the loader's rule) `LIST`,
  `l_ist`, `START_BACKEND` and `StartBackend` are `list` and
  `start_backend`, while `start-backend` is not `start_backend` and
  `get_default_org` is not `get-default-org`. An exact match wins; two
  subcommands of one command that match each other in the mode are a
  declaration error.
- `parsing <rule>, ...`, any of:
  - `shortEquals`: `-o=value` gives a short option `value` (otherwise, as
    `getopt` reads it, the value is `=value`), and `-s=value` gives a short
    switch an explicit value;
  - `helpWithAnyValue`: `--help=<anything>` asks for help (`--help=json`
    still gives the JSON);
  - `helpInCluster`: `h` inside a cluster of short flags (`-help`, `-vh`)
    asks for help when no flag claims `-h`; the letters before it are read
    as usual;
  - `valueErrorsBeforeHelp`: a value written before the help request that
    its flag rejects (it does not convert, or is outside `values`) is
    reported instead of the help, the earliest first, as the conversion
    would report it, and so is a bare word before it that no positional
    accepts, or that its positional rejects, when the command has no list
    positional; the words after the help request are not read;
  - `switchesRefuseFalse`: every switch refuses a false value, as
    `refuseFalse = true` does for one;
  - `lenientSwitchValues`: a switch's explicit value is read as Nim's
    `parseBool` reads it (`y`, `yes`, `true`, `1`, `on`, and `n`, `no`,
    `false`, `0`, `off`, ignoring ASCII case and `_`), and `--flag=` is
    true;
  - `colonValues`: `:` attaches a value as `=` does, `--name:value` (the
    first `:` or `=` ends the spelling, so `--name:a=b` gives `a=b`) and
    `-o:value` (a letter of a cluster followed by `:` takes the rest of
    the word; a switch, an explicit value);
  - `equalsTakesNext`: a `--` word ending with the `=` that attaches its
    value (`--name=`, or `--name:` under `colonValues`) takes the next
    word as that value when it does not start with `-` (an empty word is
    a value), else the value is empty: `--output= x`, `--flag= yes`,
    `--help= json`. A short flag does not (`-o= x` gives `-o` an empty
    value under `shortEquals`);
  - `helpWord`: the bare word `help` where a subcommand word is expected
    (after a command that has subcommands, before `--`) asks for the help
    of that command, as `--help` there would, and the words after it are
    not read (`tool help build` is the top-level help; `tool remote help`
    is the help of `remote`). It is compared under `commandMatching`, and
    `CliOptions(disableHelpFlag: true)` turns it off with the flags. Where
    no subcommand word is expected it is an ordinary word. A subcommand
    answering to `help` is a declaration error, unless it is declared
    `shadowedByWord = true` (below);
  - `versionWord`: the same for the word `version`, which asks for the
    version (below) when the program gives a version text;
  - `longHelpOnly`: only `--help` asks for help; `-h`, alone or in a
    cluster (whatever `helpInCluster` says), is an unknown flag unless a
    flag declares it. The help row of `CliHelpLayout.helpFlag` and
    completion then show `--help` alone;
  - `loneDashesAreFlags`: a lone `-` or `--` where a flag may stand is
    read as a flag whose name is empty, as a `getopt` that reads every
    word starting with `-` as an option reads it: the usage error
    `cekUnknownFlag` with an empty `spelling` (and no value), at that
    word's argv index, reported where it stands in argv order (a help
    request before it wins, one after it is not read). So `--` never ends
    the flags and `-` is never a positional or a subcommand word. A word
    that is the value of the flag before it is that value (`-o -`,
    `--output --`, `-vo -`; also `--output=-` and `-o-`), and once a
    `rest = true` positional has started, `-` and `--` are its words like
    any other. `equalsTakesNext` and `acceptsNextWord` never take a word
    starting with `-`, so `--output= -` and `--mode -` leave the dash on
    its own, where it is refused. (`--=v` was already an unknown flag
    spelt `--`, carrying `v`.) Completion agrees: a `--` before the cursor
    ends nothing, and a lone `-` fills no positional;
  - `exactOneLetterFlags`: under `flagMatching ignoreCase` or
    `ignoreStyle`, a spelling whose name (what follows its `-` or `--`)
    is one character is compared exactly, on either side: `-T` is not
    `-t`, `--T` is not an alias `--t` nor `--t_` (a word of two characters
    against a one-letter name), and a letter in a cluster (`-vT`) is
    compared exactly too. Longer names are still compared in the mode, so
    `--Trace-Folder` is `--trace-folder` and `--HELP` asks for help. It
    is a declaration error under `flagMatching exact`, where it would
    change nothing.

  `subcmd "help", shadowedByWord = true:` keeps a subcommand that answers
  (by its name or an alias, under `commandMatching`) to `help` under
  `helpWord` or `version` under `versionWord`, as confutils' type-based
  loader has a command named `help` that its help lists but the word
  `help` never reaches. The rule wins: where it applies, the word asks
  for help (or the version) exactly as without the subcommand (`tool help
build` is the top-level help), and completion walks the words after it
  as if no subcommand answered to it. Where it does not apply
  (`disableHelpFlag`; no `versionText`), the word reaches the subcommand,
  and the subcommand's other aliases always do. Otherwise the subcommand
  is an ordinary one: it is in the model and the grammar, help lists it,
  completion offers its word, `helpText(["help"])` renders its own help
  (the path names it), and the JSON marks it `"shadowedByWord": true`. The
  mark on a subcommand that answers to no reserved word is a declaration
  error.

  Neither `colonValues` nor `equalsTakesNext` looks inside a word that is
  the value of the flag before it: `-o --x:y` gives `-o` the value
  `--x:y`, and `--output --a= b` gives `--output` the value `--a=` and
  leaves `b` a word of its own.

In `CliOptions`:

- `versionText = "<text>"`: when not empty, `--version` (compared under
  `flagMatching`; `--version=<anything>` too under `helpWithAnyValue`)
  raises `CliVersionRequest`, a `CliHelpRequest` whose `text` is the
  version text exactly as given, so a program that prints a help
  request's text and exits 0 handles it unchanged; so does the word
  `version` under `versionWord`. A flag the description spells
  `--version` keeps that spelling. Without a version text neither means
  anything. The help `load` raises in the standard layout lists a
  `--version` row (`Print version`) when there is a version text; a
  page rendered with `helpText`, or in the classic layout, lists it only
  when `CliHelpLayout(versionFlag: "<text>")` asks for its row.
  Completion does not offer it.

On a positional:

- `rest = true`, on the last positional of a command, of a `seq` type: the
  rest of the command line. Once every positional before it has its word,
  every remaining word is its, verbatim (never split on a `separator`):
  flags, `--help`, `--version`, `help` and `--` included, and no flag of
  any command is read after that. Before that, flags and `--` are read as
  usual, so `tool run --verbose prog -x --help` sets `--verbose` and gives
  `prog` to the first positional and `-x --help` to the rest; a command
  whose only positional is the rest one takes every word after its
  subcommand word (`tool remote --verbose a` gives it `--verbose a`). It is
  required unless declared otherwise (`required = false` lets it be empty).
  Completion offers only its own values from where it starts (none
  without `values` or a completer), and the JSON marks it `"rest": true`.

On a flag:

- `acceptsNextWord = true`, with `optionalValue`: written bare as a word of
  its own (or last in a cluster), the flag takes the next word as its value
  when that word does not start with `-` and is a valid value: it converts
  to the parameter's type (its `parseCliValue`) and is in its `values`.
  Anything else stays where it is and the flag takes its `optionalValue`.
  (The generated `load` supplies the check; the parser called without one
  accepts only words in the closed value set.)
- `refuseFalse = true`, on a switch: `--flag=false` (`off`, `no`, `0`) is
  the usage error `cekSwitchFalseValue`, carrying the spelling and the value
  so a program can word it itself; `--flag=true` and bare `--flag` set it.
  It applies to the command line; `negatable` contradicts it.
- A flag of type `Option[bool]` (`flag interactive is Option[bool]`) takes
  a value, the next word or `--flag=value`, as any value flag does
  (`-i true`; `-i prog` is an invalid value); a switch is a `boolFlag`.
- `alsoSets = [<param> = "<text>", ...]`: each occurrence of the flag (of a
  switch, one that sets it to true) also supplies `<text>`, as it would be
  written on the command line, to each named parameter of the same command,
  as a command-line candidate at the flag's own argv index (with `setBy`
  naming the flag). The ordinary merge then decides: the last occurrence of
  a scalar wins, so `--legacy --attach=late` and `--attach=late --legacy`
  differ; a list collects in command-line order. A parameter that only
  another flag sets is declared with `sources = {}`.

The help side is `valueName`, `longHelp`, `help` as a constant expression
and `CliHelpLayout` (see [Help](#help)).

What still differs from that loader: its `getopt` skips the word after a
short option with an empty attached value (`-o=` or `-o:` followed by
`x`), where clispec reads that word as usual; it skips blanks inside a
word around the `=` or `:` (`"--name= x"` and `"--name :x"`, each one
word, give `x`), where clispec keeps them; it matches a one-letter
abbreviation written as a long option (`--t` for `-t`) and a one-letter
name written as a short one (`-x` for `--x`), which a description
declares (`alias = "--t"`, `short = 'x'`); an unknown letter in a
cluster of short flags is reported as the whole word (`-coop`, also
`-vT` and `-T=x`), not the letter; its rest-of-line field starts after as many
words as the command has fields before it, counting flags and the words
before the subcommand word, so a flag between the subcommand word and the
first positional (`run --verbose prog a`) shifts the words, where a
`rest = true` positional starts after the positionals before it; it read
the rest from the process's own arguments, not the ones it was given; it
accepted the default subcommand's own name as a word, which clispec does
not; errors decided once the whole command line is
read (a value its type rejects, a bare word no positional accepts) come
after the ones the tokenizer finds (an unknown flag, a refused false
switch) rather than strictly in argv order, except before a help request
under `valueErrorsBeforeHelp`; and an enum value is matched ignoring case
and `_` in every letter, where the loader's `parseEnum` compares the first
letter exactly (a program that needs that declares its own
`parseCliValue`).

```nim
import std/options
import clispec

const Paragraph = "A second paragraph."

cliProgram(Rec, "rec"):
  flagMatching ignoreStyle
  parsing shortEquals, helpWithAnyValue, valueErrorsBeforeHelp,
    switchesRefuseFalse, colonValues, equalsTakesNext
  flag output is Option[string], short = 'o', valueName = "path",
    help = "Output file"
  flag attach is Option[string], values = ["early", "late"],
    valueName = "early|late", help = "Attach mode", longHelp = Paragraph
  boolFlag legacy is bool, alsoSets = [attach = "early"],
    help = "The same as --attach=early"
  flag trace is Option[string], values = ["fast", "full"],
    optionalValue = some("fast"), acceptsNextWord = true,
    help = "Trace depth (bare = fast)"
  boolFlag split is bool, help = "Split the output"

assert Rec.load(@["-O=t.out"]).output == some("t.out")
assert Rec.load(@["--output:t.out"]).output == some("t.out")
assert Rec.load(@["--output=", "t.out"]).output == some("t.out")
assert Rec.load(@["-o", "--x:y"]).output == some("--x:y")
assert Rec.load(@["--legacy", "--attach=late"]).attach == some("late")
assert Rec.load(@["--attach=late", "--legacy"]).attach == some("early")
assert Rec.load(@["--trace", "full"]).trace == some("full")
try:
  discard Rec.load(@["--split=off"])
  assert false
except CliUsageError as e:
  assert e.kind == cekSwitchFalseValue and e.value == "off"
assert Rec.optionsTable(layout = CliHelpLayout(column: 26, width: 60,
  helpFlag: "Show this help")) == """
  -o, --output <path>     Output file
  --attach <early|late>   Attach mode
                          A second paragraph.
  --legacy                The same as --attach=early
  --trace[=<fast|full>]   Trace depth (bare = fast)
  --split                 Split the output
  -h, --help              Show this help
"""
```

The subcommand-word rules, a rest positional and the version:

```nim
import std/strutils
import clispec

cliProgram(Dbg, "dbg"):
  flagMatching ignoreStyle
  commandMatching ignoreStyle
  parsing helpWord, versionWord, longHelpOnly
  boolFlag newTab is bool, perSource = [cli = "new-tab"], help = "New tab"
  subcmd "list":
    discard
  subcmd "start_backend":
    pos kind is string
  subcmd "run":
    pos program is string
    pos args is seq[string], rest = true, required = false
  subcmd "help", shadowedByWord = true, aliases = ["topics"],
      help = "Help topics":
    discard

assert Dbg.load(@["LIST"]).command == DbgCommand.list
assert Dbg.load(@["StartBackend", "db"]).startBackend.kind == "db"
let r = Dbg.load(@["run", "--new-tab", "prog", "-x", "--help", "--"])
assert r.newTab and r.run.program == "prog"
assert r.run.args == @["-x", "--help", "--"]
let opts = CliOptions(versionText: "dbg 1.0")
for argv in [@["--version"], @["version"], @["run", "--VERSION"]]:
  try:
    discard Dbg.load(argv, opts)
    assert false
  except CliVersionRequest as e:
    assert e.text == "dbg 1.0"
try:
  discard Dbg.load(@["help", "run"])
  assert false
except CliHelpRequest as e:
  assert e.commandPath.len == 0 and e.text == Dbg.helpText()
assert "Help topics" in Dbg.helpText()
assert Dbg.load(@["topics"]).command == DbgCommand.help
try:
  discard Dbg.load(@["-h"])
  assert false
except CliUsageError as e:
  assert e.kind == cekUnknownFlag and e.spelling == "-h"
```

A lone `-` or `--` as an unknown flag, and one-letter spellings compared
exactly:

```nim
import std/options
import clispec

cliProgram(Fetch, "fetch"):
  flagMatching ignoreStyle
  parsing loneDashesAreFlags, exactOneLetterFlags
  flag output is Option[string], short = 'o'
  flag tag is Option[string], short = 'T'
  subcmd "run":
    pos program is string
    pos args is seq[string], rest = true, required = false

assert Fetch.load(@["-o", "-", "run", "p"]).output == some("-")
assert Fetch.load(@["run", "prog", "--", "-"]).run.args == @["--", "-"]
for argv in [@["-"], @["--", "run", "p"], @["run", "--", "prog"]]:
  try:
    discard Fetch.load(argv)
    assert false
  except CliUsageError as e:
    assert e.kind == cekUnknownFlag and e.spelling == ""
assert Fetch.load(@["--OUTPUT", "a", "run", "p"]).output == some("a")
assert Fetch.load(@["-T", "v1", "run", "p"]).tag == some("v1")
try:
  discard Fetch.load(@["-O", "a", "run", "p"])
  assert false
except CliUsageError as e:
  assert e.kind == cekUnknownFlag and e.spelling == "-O"
```

### Errors

`load` never ends the process. A command line it rejects raises a
`CliUsageError` whose `kind` is one of `CliErrorKind`; each kind has one
wording, and every wording names the command (`'tool build'`):

| Kind                      | Wording                                                                                                                                   |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `cekUnknownFlag`          | `unknown flag '--nope' for 'tool build'`                                                                                                  |
| `cekUnknownSubcommand`    | `unknown subcommand 'frob' for 'tool'`                                                                                                    |
| `cekMissingSubcommand`    | `'tool' needs a subcommand; expected one of: build, run`                                                                                  |
| `cekMissingValue`         | `flag '--jobs' of 'tool build' needs a value`                                                                                             |
| `cekInvalidValue`         | `invalid value 'many' for '--jobs' of 'tool build'; expected an integer`                                                                  |
| `cekUnexpectedPositional` | `unexpected argument 'extra' for 'tool build'`                                                                                            |
| `cekMissingRequired`      | `missing required parameter '<target>' of 'tool build'`                                                                                   |
| `cekSwitchFalseValue`     | `switch '--split' of 'tool build' takes no false value (got '--split=off'); it is on when given and off when omitted`                     |
| `cekConflictingSources`   | `conflicting values for '--jobs' of 'tool build': '4' from /etc/tool.toml:3 (layer 'system') and '8' from environment variable TOOL_JOBS` |

An unknown subcommand's wording does not list the command's subcommands:
the tip offers the close ones and the block's last line points at the help
that lists them all (`expected` still holds the list). A missing
subcommand's wording lists them, since there is nothing to suggest from.
In both, "the subcommands" are the ones the command's help lists in
either tier: never a `hidden` one, and an `internal` one only below the
root. Where that leaves none, the missing-subcommand wording ends at `'tool ns' needs a
subcommand`, without an empty `expected one of:`.
The help procedures (`helpText(path)`) report a word below a command that
has no subcommands at all as `cekUnexpectedPositional` (`unexpected
argument 'x' for 'tool build'`) rather than as an unknown subcommand.

An unknown flag or subcommand word that the description declares retired
adds its replacement to the wording (`unknown flag '--old' for 'tool
build' (a retired spelling; use --new)`); see [Retired
spellings](#retired-spellings).

The error also carries the offending argv index, the spelling, the value,
what was expected and `exitCode`, the program's declared usage exit code.
For an unknown flag written with a value (`--nope=v`, `--nope:v` under
`colonValues`, `--nope= v` under `equalsTakesNext`), the spelling is the
flag name alone (`--nope`) and the value is `v`; the wording names only
the spelling.
`cekConflictingSources` and the `source` of an invalid value are what a
library that adds other sources (confutils) reports through the same
taxonomy: an invalid value that came from a configuration file or the
environment says where (`invalid value 'many' for '--jobs' of 'tool' (from
environment variable TOOL_JOBS); expected an integer`), in `source` as well;
its argv index is -1.

A program prints a usage error with `cliPrintError(e)` (to standard error;
`cliPrintError(e, stream)` elsewhere) and help with `cliPrintHelp(e)` (to
standard output), as in the example above, instead of writing `e.msg` and
`e.text` itself: they choose the colour and the width for the stream they
write to (see [Colour and width](#colour-and-width)). `cliPrintError`
writes the block `cliErrorText(e, styled = false)` renders:

```text
error: unknown subcommand 'biuld' for 'tool'

  tip: a similar subcommand exists: 'build'

Usage: tool [options] <command>

For more information, try 'tool --help'.
```

The first line is `e.msg`, the kind's wording, unchanged. The tip is there
when the error carries `suggestions`: `a similar subcommand exists:
'build'`, `a similar flag exists: '--jobs'` or `a similar value exists:
'release'`, and with several `some similar flags exist: '--jobs',
'--jolt'` (`subcommands`, `values`), closest first. `Usage:` is the usage
line of the command the error is about (`e.usage`), never broken, and the
last line names the command that prints its help (`e.helpCommand`, empty
when `disableHelpFlag` is set); each line is left out when the error does
not carry it. A library that raises usage errors of its own fills both
with `cliAddErrorContext(e, grammar, command, options)`.

Suggestions are offered for an unknown subcommand (the subcommands the
command lists in its help; an alias that matches offers its command's
name, once), an unknown flag (the spellings, as written, of the flags the
command accepts and lists, their `--no-` form, `--help` and `--version`
where they apply; compared without their leading dashes) and a value
outside a closed value set (`values`, an enum's values). A candidate is
offered when its Damerau–Levenshtein distance from the typed word
(`cliEditDistance`) is at most 2 and less than half the word's length
(`cliIsSimilar`: `--job` gives `--jobs`; a four-letter word two edits away
gives nothing), closest first, declaration order among equals, at most
three (`cliSuggest`). A `hidden` item and an `internal` parameter are never
offered, and an `internal` subcommand only inside the command that holds
it. A prefix is never accepted as a flag, and nothing prompts.

```nim
import clispec

type Profile = enum debug, release

cliProgram(Pkg, "pkg"):
  subcmd "build", help = "Build", aliases = ["b"]:
    flag jobs is int, short = 'j', help = "Parallel jobs"
    flag profile is Profile, default = debug
  subcmd "run", help = "Run":
    discard

proc errorOf(argv: seq[string]): ref CliUsageError =
  try:
    discard Pkg.load(argv)
  except CliUsageError as e:
    return e

assert errorOf(@["biuld"]).suggestions == @["build"]
assert errorOf(@["build", "--job", "3"]).suggestions == @["--jobs"]
assert errorOf(@["build", "--profile", "relase"]).suggestions == @["release"]
let e = errorOf(@["build", "--job", "3"])
assert cliErrorText(e) == """error: unknown flag '--job' for 'pkg build'

  tip: a similar flag exists: '--jobs'

Usage: pkg build [options]

For more information, try 'pkg build --help'.
"""
```

### Retired spellings

When a flag or a subcommand is renamed, the old spelling should stop
working: a script that still passes it is out of date, and accepting it
with a warning hides that. It should also not leave the user guessing what
to type instead. A command declares each spelling it no longer accepts and
what replaced it:

```text
retired "<spelling>", replacement = "<text>"
```

The spelling is a flag when it starts with `-` (`--old-name`, `-o`, or one
value of a flag, `--report=none`) and otherwise a subcommand word
(`checkout`). The parser still refuses it exactly as it refuses any
spelling it does not know: the same `cekUnknownFlag` or
`cekUnknownSubcommand`, the same exit code, and nothing of it is accepted.
What changes is the error: its message names the replacement after the
command, its `retired` field holds the declaration that matched and its
`replacement` field the replacement, and it carries no suggestions (the
replacement is what the user meant).

- **Where it applies.** A retired flag applies to the command that
  declares it and to every command nested in it, wherever in the body the
  statement is written; one declared in a `call:` applies where the
  `call:`'s holder reads flags too. A retired subcommand word applies only
  where its command expects a subcommand word.
- **Values.** `--report=none` matches only `--report=none` (or
  `--report:none` under `colonValues`), and is preferred to a `--report`
  retired alone, which matches the flag with any value or none. Only a
  flag that is itself gone is retired this way: one value of a live flag
  is an invalid value, not an unknown flag. A one-letter `-t` also
  matches a word it starts (`-t4`). When the declaration that matched is
  not the spelling itself, the message quotes it (`unknown flag
  '--report' for 'tool build' ('--report=none' is a retired spelling; use
  --measure=none)`).
- **Matching** follows `flagMatching` for flags and `commandMatching` for
  words, as for live spellings.
- **Never offered.** A retired spelling is not listed by help, not offered
  by completion and never suggested for a mistyped word. The
  machine-readable help lists the ones that apply at a command in a
  `retired` list of their own (see [The machine-readable
  form](#the-machine-readable-form)), never among its `parameters` or
  `commands`.
- **Declaration errors.** A retired flag that a command it applies to
  accepts (one of its flags' spellings, aliases, shorts or `--no-` forms,
  compared under `flagMatching`; for `--report=none`, the flag
  `--report`), a retired word that a subcommand answers to or that asks
  for help or the version there, a retired word on a command without
  subcommands or on one whose `call:` takes positional words (the word
  would be one of them), a spelling declared twice where it applies, a
  missing or empty `replacement`, a malformed spelling and a `retired`
  statement inside a `group` section are compile errors.

```nim
import std/strutils
import clispec

cliProgram(Vcs, "vcs"):
  convention cli = kebabCase
  flag jobs is int, default = 1
  retired "--threads", replacement = "--jobs"
  subcmd "switch", help = "Switch to a branch":
    pos branch is string
  subcmd "log", help = "Show history":
    flag format is string, default = "short"
    retired "--pretty=oneline", replacement = "--format=short"
    retired "--pretty", replacement = "--format"
  retired "checkout", replacement = "vcs switch <branch>"

proc errorOf(argv: seq[string]): ref CliUsageError =
  try:
    discard Vcs.load(argv)
  except CliUsageError as e:
    return e

let word = errorOf(@["checkout", "main"])
assert word.kind == cekUnknownSubcommand
assert word.exitCode == 2
assert word.retired == "checkout"
assert word.replacement == "vcs switch <branch>"
assert word.msg == "unknown subcommand 'checkout' for 'vcs' (a retired " &
  "spelling; use vcs switch <branch>)"

# A root flag is retired in every subcommand too.
let flag = errorOf(@["log", "--threads", "2"])
assert flag.kind == cekUnknownFlag
assert flag.msg == "unknown flag '--threads' for 'vcs log' (a retired " &
  "spelling; use --jobs)"

# One value of a retired flag is preferred to the flag alone.
let oneline = errorOf(@["log", "--pretty=oneline"])
assert oneline.retired == "--pretty=oneline"
assert oneline.msg == "unknown flag '--pretty' for 'vcs log' " &
  "('--pretty=oneline' is a retired spelling; use --format=short)"
assert errorOf(@["log", "--pretty=full"]).replacement == "--format"

# Never offered, never suggested.
assert "checkout" notin Vcs.helpText()
assert "--threads" notin Vcs.helpText(@["log"], long = true)
assert errorOf(@["chekout"]).suggestions.len == 0
```

### Help

`--help` and `-h` raise `CliHelpRequest` with the help of the command they
were given to in `text`; `--help=json` gives the machine-readable form. A
program turns this off with `CliOptions(disableHelpFlag: true)`, and a flag
the program itself spells `--help` or `-h` takes precedence. Under `parsing
longHelpOnly` `-h` is not help, and under `parsing helpWord` the word
`help` is (see
[Command lines from confutils' type-based loader](#command-lines-from-confutils-type-based-loader)).
`-h` gives the short page and `--help` (and the word `help`) the long one;
`CliHelpRequest.long` says which was asked for. The help of a command lists
its subcommands, its positionals and every flag it accepts (the example
below shows a whole page).

The page has, each only when it has entries and one blank line between
them: the command's `help` line (on the long page followed by its
`longHelp`, one paragraph per non-blank line); `Usage:`; `Aliases:`;
`Commands:` (`name, alias` and the help of each listed subcommand);
`Arguments:`; `Options:` (the command's own flags in no group, then
`-h, --help`, then `--version` when the program has a version text); one
section per `group`, in declaration order, with its help under the
heading; `Global Options:` (flags inherited from enclosing commands; an
inherited flag in a group stays in that group's section); `Examples:`;
and, on a command with subcommands, `Run '<path> <command> --help' for
more on a command.` Rows keep declaration order.

A row is indented two spaces. Long spellings are aligned: four spaces
stand for a missing short spelling when another row of the section has
one. The placeholder is the `valueName`, else the closed value set joined
with `|`, else the type's name; a list adds `...` (`<NAME>...`), a counted
flag `...` after its spelling (`-v, --verbose...`), an `afterSeparator`
positional is written after its `--` (`[-- <command>...]`, on the usage
line too), an optional value is
`--report[=<PATH>]`, a negatable switch `--[no-]name`, and a long alias
follows the canonical spelling. The description is the `help` and then
the notes, in this order: `[required]`, `[default: x]` (not for switches
and counted flags; a text default is quoted only when it is empty or
holds white space, `[default: ""]`), `[possible values: a, b]` when the
placeholder does not list the set, and `[env: NAME, ...]`. The long page
adds each parameter's `longHelp` paragraphs under its row, and the short
page's help row reads `Print help (see more with '--help')` when the long
page shows more (otherwise both say `Print help`).

Descriptions wrap at the page width with continuation lines under the
description column, which is two spaces after the section's widest left
entry of at most 32 characters; a wider entry puts its description on the
next line. When fewer than 40 columns would remain, the section uses the
next-line layout: every description under its row, indented 12. A note is
not broken unless it is wider than the line; the usage line, example
command lines and words longer than the line are never broken. The width
is the layout's `width`, at most 100; `cliDefaultHelpLayout` leaves it to
the printer (`width` 0, see [Colour and width](#colour-and-width)), and a
page rendered without one (`helpText`, `CliHelpRequest.text`) is 80
columns wide, the same wherever the program runs.

A command declares its long description and its examples in its body:

```nim
import std/strutils
import clispec

cliProgram(Pkg, "pkg"):
  help "Manage packages"
  boolFlag verbose is bool, short = 'v', help = "Talk more"
  subcmd "install", help = "Install packages", aliases = ["i"]:
    longHelp "Installs the named packages and what they depend on."
    flag prefix is string, default = "/usr/local", valueName = "DIR",
      help = "Where to install"
    pos names is seq[string], repeated = true, help = "Packages"
    example "pkg install --prefix ~/.local jq",
      help = "Install jq for the current user"

assert Pkg.helpText(["install"]) == """Install packages

Usage: pkg install [options] <names>...

Aliases: i

Arguments:
  <names>...  Packages

Options:
      --prefix <DIR>  Where to install [default: /usr/local]
  -h, --help          Print help (see more with '--help')

Global Options:
  -v, --verbose  Talk more

Examples:
  Install jq for the current user
    pkg install --prefix ~/.local jq
"""
let long = Pkg.helpText(["install"], long = true)
assert long.startsWith("Install packages\n\n" &
  "Installs the named packages and what they depend on.\n\nUsage:")
assert "  -h, --help          Print help\n" in long
try:
  discard Pkg.load(@["i", "--help"])
  assert false
except CliHelpRequest as e:
  assert e.long and e.text == long
```

`example "<command line>", help = "<text>"` may be written any number of
times in a command's body (the root's included); help lists the examples
in declaration order, on both pages, and they are not inherited.
`longHelp "<text>"` in the body, or `longHelp = "<text>"` in the head
(`subcmd "build", longHelp = "...":`), gives a command its long
description. Both take string literals or `&` of literals. A consumer
whose extension already claims statements named `example`, `longHelp` or
`retired` keeps them: those three statements are offered to the extension
first.

`CliHelpLayout` chooses and lays out the page. Its `style` is
`chsStandard`, the page above, or `chsClassic`, the layout clispec printed
before it, which is the type's default: `CliHelpLayout()`, and any layout
built field by field without `style`, renders exactly the classic text.
Two presets name them: `cliDefaultHelpLayout` (the standard page, its
width left to the printer, the default argument of `cliHelpText`, `cliOptionsTable`, the
generated `helpText` and `optionsTable`, and of `CliOptions.helpLayout`, so
it is also the help `load` raises) and `cliClassicHelpLayout`. A program
that must keep the classic layout for its users opts into it with
`CliOptions(helpLayout: cliClassicHelpLayout)` and
`Tool.helpText(layout = cliClassicHelpLayout)`. `cliHelpText(g, command,
program, layout, long)` and `Tool.helpText(path, layout = ..., long =
...)` render a page; `cliOptionsTable(g, command, layout, group, long)`
(`Tool.optionsTable`) renders just the rows of the options table (in the
standard style, the command's own flags and the help rows), for a program
that writes the rest of its help screen itself.

The fields: `indent` (2), the description `column` (classic only; 0: two
spaces after the widest left entry of at most `maxLeft`, 32, characters),
the `width` (classic: descriptions are word-wrapped to it, 0 not wrapped;
standard: the page width), `helpFlag` (when not empty, the options table
ends with a `-h, --help` row with this text, `--help` alone under
`longHelpOnly`; `Print help` in `cliDefaultHelpLayout`), `versionFlag`
(when not empty, a `--version` row with this text after it; in the
standard style the help `load` raises words it `Print version` when
`CliOptions.versionText` is set), `listMarker` (`...` after a list's
placeholder), `canonicalFirst` (`--name` before a long `alias`; set in
`cliDefaultHelpLayout`) and `notes`. The classic layout prints `Usage:`
first, every flag under `Options:` or its group, each `longHelp` line
below its row on every page, and nothing wrapped unless `width` is set:

```text
Usage: tool build [options] <target>

Build a project

Aliases: b

Arguments:
  <target>  What to build

Options:
  -v, --[no-]verbose  Talk more
  -j, --jobs <int>    Parallel jobs [default: 4]
```

With a fixed `column` a left entry that leaves less than two spaces before
it puts its description on the next line, which with
`CliHelpLayout(column: 30, width: 92, listMarker: false, canonicalFirst:
true, notes: false, helpFlag: "Show this help")` gives exactly the table
confutils' `renderOptionsTable(flags, 2, 30, 92)` renders.

`hidden` items are never listed. An `internal` parameter, wherever it is
declared, is listed in no help screen; it is still accepted and fills its
field. An `internal` subcommand is listed only in the help of the command that
holds it, never in the root command's help, which is the program's primary
help; so `tool internal --help` documents the namespace that `tool --help`
leaves out (its internal parameters excepted).

#### Command groups and tiers

A command with many subcommands can sort them under headings and keep the
everyday ones apart from the rest. `group "<title>"[, help = "<text>"]:`
around `subcmd` statements lists those subcommands under its heading
instead of `Commands:`; `tier = secondary` on a subcommand (the default is
`primary`) leaves it out of `-h` and `--help`, which then end with a line
pointing at `--help-all`, the long page that lists both tiers:

```nim
import std/strutils
import clispec

cliProgram(Kt, "kt"):
  help "Build and ship"
  subcmd "init", help = "Create a project":
    discard
  group "Build Commands", help = "Sources to artifacts":
    subcmd "build", help = "Build the project":
      discard
    subcmd "graph", help = "Print the build graph", tier = secondary:
      discard
  subcmd "doctor", help = "Diagnose the environment", tier = secondary:
    discard

assert Kt.helpText() == """Build and ship

Usage: kt <command>

Commands:
  init  Create a project

Build Commands:
  Sources to artifacts
  build  Build the project

Options:
  -h, --help  Print help

Run 'kt --help-all' to list all 4 commands, or 'kt <command> --help' for
details.
"""
try:
  discard Kt.load(@["--help-all"])
  assert false
except CliHelpRequest as e:
  assert e.all and e.long
  assert e.text == Kt.helpText(long = true, all = true)
  assert "  graph  Print the build graph\n" in e.text
  assert "  doctor  Diagnose the environment\n" in e.text
# Completion offers both tiers.
var offered: seq[string] = @[]
for c in Kt.complete(@[""]):
  offered.add(c.value)
assert offered == @["init", "build", "graph", "doctor"]
```

- **Sections.** `Commands:` holds the listed subcommands in no group; each
  command group follows it, in the order the groups were first declared,
  with its help under the heading, as a parameter group's section has.
  Each section aligns its own rows.
- **Tiers.** `-h` and `--help` list the `primary` subcommands. When the
  command has `secondary` ones they leave out, the page's last line is
  `Run '<path> --help-all' to list all <N> commands, or
'<path> <command> --help' for details.`, where `N` is the number of
  subcommands
  `--help-all` lists (an `internal` one counts only where it is listed, a
  `hidden` one never; `1 command` for one). It is wrapped at the page
  width like prose, with each quoted command line kept whole. `--help-all`
  is the long page with both tiers and the usual last line. `secondary` is
  not `internal`: the parser, completion and the machine-readable form
  treat both tiers alike.
- **Where `--help-all` is accepted.** In a program that declares at least
  one `secondary` subcommand, at every command (the page is `--help`'s
  where the command has no `secondary` subcommand). It takes the values
  `--help` takes (`--help-all=json` is the JSON) and gives way to a flag
  the program spells `--help-all`. Under `parsing helpWord`, `help --all`
  (`--all` the word right after `help`) asks for it too. In a program
  without `secondary` subcommands `--help-all` means nothing to clispec,
  an unknown flag as before. `CliHelpRequest.all` says the page lists
  both tiers; `cliHelpText(..., all = true)` and
  `Tool.helpText(all = true)` render it.
- **Unchanged pages.** A program that declares no command group and no
  `secondary` subcommand gets exactly the pages, the JSON and the
  completion it got before.
- **The classic layout** (`cliClassicHelpLayout`) has no command groups and
  no tiers: it lists every listed subcommand under `Commands:`, as it
  always did, whichever page was asked for.

#### Colour and width

`Tool.printHelp(e, stream = stdout)` and `Tool.printError(e, stream =
stderr)`, which `cliProgram` generates, and the library's
`cliPrintHelp(e, stream = stdout)` and `cliPrintError(e, stream = stderr)`
decide, for the stream they write to, whether to style the page, in which
palette, and how wide it is; the generated ones under the program's own
colour configuration, the library's under the build's (see *Compile-time
knobs* below). Styling never changes the text: the styled
page with its escape sequences removed (`cliStripStyles`) is the plain page,
byte for byte, so colour never says anything the words do not, and the
layout, measured on the visible text (`cliVisibleLen`), is the same.

**What is styled.** Six elements and nothing else: `heading` (section
headings and `Usage:`), `literal` (flag spellings, command names and
aliases, the program name, the words of a usage line, example command lines
and suggestions), `placeholder` (`<N>` with a list's `...`, and the
bracketed words of a usage line: `[options]`, `[<packages>...]`), `error`
(the word `error:`), `invalid` (the offending word in an error) and `tip`
(the word `tip:`). Descriptions, notes and prose are never styled. Only bold
is used, and underline in `portable16`'s `invalid`; each span is
`ESC[<parameters>m`, the text, `ESC[0m`.

**On or off.** The first rule that applies decides (`cliColorOn`,
`cliUseColor(stream, mode)`):

1. `CliOptions.color`: `ccmAlways` or `ccmNever` (the default, `ccmAuto`,
   goes on to the next rules);
2. `NO_COLOR` set and not empty: off;
3. `FORCE_COLOR` set: `0` or `false` off, anything else (`1`, `2`, `3`,
   `true`, empty) on;
4. `CLICOLOR_FORCE` set, not empty and not `0`: on;
5. `CLICOLOR=0`: off;
6. otherwise on exactly when the stream is a terminal and either `TERM` is
   set (not empty) and not `dumb`, or `CI` is set. On Windows the stream
   must be a console on which virtual terminal processing is or can be
   turned on (clispec turns it on), and an unset `TERM` counts as usable.

**Depth.** When styling is on: `CliOptions.colorDepth` when the program
sets it (`ccd16`, `ccd256`, `ccd24`); else 256 colours for `FORCE_COLOR=2`
and 24-bit for `FORCE_COLOR=3`; else 24-bit when `COLORTERM` is `truecolor`
or `24bit`; else 256 when `TERM` ends in `-256color` or `256`; else 16. The
depth is 16 whenever the background is unknown.

**Background.** The 256-colour and 24-bit palettes are tuned for a dark or
a light background, learned from the first source that answers: the users'
`bg=` (below); `CliOptions.background` (`cbDark`, `cbLight`, or `cbUnknown`
to keep `portable16`); `COLORFGBG`, whose last field is the background's
palette index (0 to 6 and 8 dark, 7 and 9 to 15 light); and last a query of
the terminal. The query is made at most once per process, only when the
depth would be 256 or 24-bit and the stream is a terminal, never under a
`TERM` of `dumb`, `screen*` or `tmux*`, never when the process is not in the
terminal's foreground process group, and not on Windows. It opens
`/dev/tty`, turns off canonical mode and echo, writes `ESC]11;?`,
`ESC]10;?` and `ESC[c` (every terminal answers the last, so its answer ends
the wait), reads for at most 100 ms and restores the terminal. The
background is dark when its relative luminance (WCAG) is below the
foreground's, or below 0.5 when no foreground is reported. With no answer,
the background is unknown and the page gets `portable16`.

**Palettes.** SGR parameters (`cliPortable16`, `cliDark24`, `cliDark256`,
`cliLight24`, `cliLight256`):

| Element | portable16 | dark, 24-bit | dark, 256 | light, 24-bit | light, 256 |
|---|---|---|---|---|---|
| `heading` | `1;34` | `1;38;2;82;198;137` | `1;38;5;42` | `1;38;2;18;129;81` | `1;38;5;22` |
| `literal` | `1` | `1;38;2;83;192;210` | `1;38;5;44` | `1;38;2;9;125;140` | `1;38;5;23` |
| `placeholder` | `35` | `38;2;150;183;189` | `38;5;152` | `38;2;87;118;124` | `38;5;242` |
| `error` | `1;31` | `1;38;2;255;147;139` | `1;38;5;217` | `1;38;2;214;47;53` | `1;38;5;160` |
| `invalid` | `4;35` | `38;2;227;168;1` | `38;5;178` | `38;2;145;107;2` | `38;5;94` |
| `tip` | `1;34` | `1;38;2;82;198;137` | `1;38;5;42` | `1;38;2;18;129;81` | `1;38;5;22` |

`portable16` (depth 16, or the background unknown) uses only 16-colour
codes that read on dark and light backgrounds alike. The tuned palettes
keep cargo's hues (green headings, cyan literals and placeholders, red
errors, amber offending words) at a lightness chosen for contrast: at least
7:1 on common dark terminal backgrounds and 4.5:1 on light ones.

**Users' overrides.** Only in a program built with
`-d:clispec_user_colors=on` (they are off by default): `CLISPEC_COLORS` and
`<PROGRAM>_COLORS` (the program's name upper-cased, every character other
than a letter or digit written `_`, so `DEPOT_COLORS`) hold `name=value`
entries separated by `:`. `name` is an element or `bg`; an element's value
is SGR parameters (digits and `;`), used at every depth, and an empty value
leaves the element unstyled; `bg` is `dark` or `light`. The program's
variable applies over `CLISPEC_COLORS`, which applies over the palette. A
malformed entry is ignored on its own, so a page always prints, and the
overrides never turn styling on or off:
`DEPOT_COLORS='heading=1;4:invalid=7:bg=light'`.

**Compile-time knobs.** Each policy can be fixed, and each input switched
off, for the whole build with a define, or for one program with a parameter
of its `cliProgram` call. A parameter applies over the define, which
applies over the default. A bad value is a compile-time error that names
the define or the parameter and lists its allowed values. A knob that is
off or fixed leaves no code behind: its variables are not read, the query
is not compiled, and a palette that can never be chosen is not in the
program.

| Define | `cliProgram` parameter | Values | Default | When fixed or off |
|---|---|---|---|---|
| `clispec_colors` | `colors` | `auto`, `always`, `never` | `auto` | `never`: nothing is styled, no styling or detection code is compiled, and `CliOptions.color` is ignored; `always`: no detection (rules 2 to 6), `CliOptions.color` still applies |
| `clispec_color_env` | `colorEnv` | on/off | on | rules 2 to 5 are gone, as is `FORCE_COLOR`'s depth |
| `clispec_color_depth` | `colorDepth` | `auto`, `16`, `256`, `24` | `auto` | that depth; nothing is read to detect it, and only its palettes are compiled |
| `clispec_background` | `background` | `auto`, `dark`, `light`, `unknown` | `auto` | that background; no source is read, only its palettes are compiled (`unknown`: `portable16` alone, and no depth is detected) |
| `clispec_colorfgbg` | `colorFgBg` | on/off | on | `COLORFGBG` is not read |
| `clispec_background_query` | `backgroundQuery` | on/off | on | no query: no terminal I/O beyond the page |
| `clispec_user_colors` | `userColors` | on/off | **off** | `CLISPEC_COLORS`, `<PROGRAM>_COLORS` and their `bg=` exist only when on |
| `clispec_palette` | `palette` | entries as in the users' variables | empty | the developer's restyling, over every palette and under the users' overrides; checked when the program is built (`bg` is refused: use `clispec_background` / `background`) |

On/off takes `on`, `yes`, `true`, `1` and `off`, `no`, `false`, `0`,
`none`; the enum values are matched in any case. A parameter's value is a
word, a number or a string literal:

```nim
import std/strutils
import clispec

cliProgram(Quiet, "quiet", colors = never):
  flag level is int, short = 'l', default = 1, help = "How quiet"

cliProgram(Painted, "painted", colorDepth = 24, background = dark,
           userColors = on, palette = "heading=1;35"):
  flag level is int, short = 'l', default = 1, help = "How painted"

proc helpOf(argv: seq[string]; options = CliOptions()): ref CliHelpRequest =
  try:
    discard Quiet.load(argv, options)
  except CliHelpRequest as e:
    return e

# colors = never: plain whatever the program asks for, and the binary holds
# none of the styling code.
let quiet = helpOf(@["-h"], CliOptions(color: ccmAlways))
assert quiet.renderStyled(80, cliPortable16Style) == quiet.text
assert "\e[" notin quiet.render(80, true)
```

The build's configuration is the constant `cliColorDefaults` (a
`CliColorConfig`); `cliPrintHelp`, `cliPrintError`, `cliUseColor`,
`cliColorStyle`, the parser's `cliTokenize` and `cliResolve` and the
decision procs take it as a `static` parameter (`config`) defaulting to it,
so a call can use another configuration and is compiled for it. A program's
own configuration (its parameters over the defines) is the constant whose
name `cliColorConfigName` gives; its `load`, `printHelp` and `printError`
pass it. `CliOptions.color`, `colorDepth` and `background` act only where
the configuration's policy is `auto`.

**What shrinks.** A configuration acts where it is compiled in, so a
program that prints only through its generated `printHelp` and `printError`
carries only the code its own configuration needs: the parser builds a help
request's renderers for the configuration `load` passes it, and the
renderers of help and errors have an overload for `CliStyle` and one for
`CliPlainStyle`. Under `colors = never` only the latter is called, and it
compiles none of the styling helpers, no palette and no detection: the
binary holds no `ESC[` sequence and no colour variable's name. `colorEnv = off` removes
`NO_COLOR`, `FORCE_COLOR`, `CLICOLOR_FORCE` and `CLICOLOR`; `colorFgBg =
off` `COLORFGBG`; `backgroundQuery = off` the query (`ESC]11;?`,
`/dev/tty`); `userColors = off` `CLISPEC_COLORS`, `<PROGRAM>_COLORS` and
their parser; a fixed depth `COLORTERM` and the `TERM` suffix test, and the
other depth's palettes; `background = unknown` every tuned palette and
every background source. `test_cs_m5c_compile_time_knobs_shrink` checks
each of these in a `-d:release --opt:size` build and prints the sizes. A
program that also calls the library's printers with the build's
configuration, `cliColorStyle`, or an entry point that takes `styled:
bool`, carries their code as well.

**Width.** `COLUMNS` when it is set to a positive integer, else the
terminal's width when the stream is a terminal, else 80; at most 100
(`cliOutputWidth(stream)`). A layout whose `width` is set keeps it.

`load` still fills `CliHelpRequest.text` with the plain page at the
layout's width (80 for the default), so a program that captures it gets the
same text everywhere. The request also carries `renderStyled(width,
style)`, which renders the page again (nil for JSON help, the version text
and completion answers, which are printed as they are), and the program's
`color`, `colorDepth`, `background` and name; `cliPrintHelp` calls it with
the style it decides (`cliHelpStyle`). A program that prints pages itself
asks `cliColorStyle(stream, options)` for the `CliStyle` (on or off, the
SGR parameters of each element) and renders with
`Tool.helpText(path, style)`, `cliHelpText(g, command, program, style)` or
`cliErrorText(e, style)`; `cliDecideStyle` is the same decision over inputs
the caller provides (an environment lookup, whether the stream is a
terminal, the terminal's answer). The older entry points that take
`styled: bool` (`render(width, styled)`, `cliHelpText(..., styled = true)`,
`Tool.helpText(styled = true)`, `cliErrorText(e, styled = true)`) still
work: `true` is the `portable16` palette, with no detection. The classic
layout is printed as it is: its width never changes, and it is styled only
under `ccmAlways`.

```nim
import std/[os, strutils]
import clispec

cliProgram(Hue, "hue"):
  help "Paint things"
  flag shade is string, short = 's', valueName = "NAME", help = "The shade"

proc helpOf(argv: seq[string]; options = CliOptions()): ref CliHelpRequest =
  try:
    discard Hue.load(argv, options)
  except CliHelpRequest as e:
    return e

let e = helpOf(@["-h"], CliOptions(color: ccmAlways))
assert e.text == Hue.helpText()                 # plain, 80 columns
let styled = e.render(80, true)                 # portable16
assert "\e[1;34mUsage:\e[0m" in styled
assert "\e[1m--shade\e[0m \e[35m<NAME>\e[0m" in styled
assert cliStripStyles(styled) == e.text
assert styled == Hue.helpText(styled = true)

# A dark terminal at 256 colours, chosen by the program.
let dark = CliStyle(on: true, depth: ccd256, background: cbDark,
                    sgr: cliDark256)
let page = e.renderStyled(80, dark)
assert "\e[1;38;5;42mUsage:\e[0m" in page
assert cliStripStyles(page) == e.text
assert page == Hue.helpText([], dark)

# A program that prints to a file itself, forcing colour, a depth and a
# background.
let path = getTempDir() / "hue-help.txt"
let log = open(path, fmWrite)
let forced = cliColorStyle(log, CliOptions(color: ccmAlways,
  colorDepth: ccd24, background: cbLight))
assert forced.sgr == cliLight24
log.close()
removeFile(path)
```

#### The machine-readable form

The machine-readable form, `helpJson`, is a JSON document with the schema
name `clispec-help/1`, meant for completion and editor hints:

```text
{"schema": "clispec-help/1", "program": "tool", "command": COMMAND,
 "conventions": {"cli": CONVENTION, "file": CONVENTION, SOURCE: CONVENTION, ...},
 "parsing": {"flagMatching": "exact" | "ignoreCase" | "ignoreStyle",
             "rules": [RULE, ...],
             "commandMatching": "ignoreCase" | "ignoreStyle" (when set)}}
COMMAND   = {"name", "path", "aliases", "help", "longHelp", "visibility",
             "shadowedByWord": true (a shadowedByWord subcommand only),
             "group": string | null, "tier": "primary" | "secondary"
               (both on every command, when the program declares a command
               group or a secondary subcommand), "usage",
             "examples": [{"command", "help"}, ...],
             "parameters": [PARAMETER, ...],
             "retired": [{"spelling", "kind": "flag" | "subcommand",
                          "replacement", "declaredIn"}, ...]
               (only where a retired spelling applies),
             "commands": [COMMAND, ...]}
PARAMETER = {"name", "kind": "flag" | "positional", "spellings",
             "negation": string | null, "value": "none" | "required" | "optional",
             "format": "separate" | "equals" | "concat",
             "valueName", "choices", "list", "separator": string | null,
             "counted", "required", "default": string | null, "env", "help",
             "group": string | null, "visibility", "position" (positionals),
             "rest": true (a rest positional only),
             "afterSeparator": true (an afterSeparator positional only),
             "declaredIn", "dynamicCompletion", "completer": string | null,
             "configKeys": {"file": KEY, SOURCE: KEY, ...}, "longHelp",
             "placeholder", "acceptsNextWord", "refuseFalse",
             "alsoSets": [{"param", "value"}, ...]}
```

`value` says whether a flag takes a value and `format` how (see
[Accepted forms](#accepted-forms)); `choices` is the closed value set, empty
when the set is open; `valueName` is the value's type name and
`placeholder` what help shows between `<` and `>` (the declared
`valueName`, else the choices joined with `|`, else the type name);
`refuseFalse` whether a switch refuses a false value (its own or under
`switchesRefuseFalse`); `parsing` names the opt-in rules below; `completer` is the `complete` expression as written.
`spellings` and `negation` are spelt in the command line's convention;
`configKeys` gives the parameter's key in every file source (`{}` when no file
may supply it), and `conventions` the convention of every source.

`retired` lists the retired spellings that apply at the command (its own,
the retired flags of the commands that enclose it, and its `call:`'s),
nearest declaration first, each with the path of the command that declares
it; a tool reads it to explain a refusal, never to offer a spelling.

`commands` nests the listed subcommands recursively, of both tiers, and
the listing rules above decide what appears, with one difference: the
machine-readable form also lists `internal` parameters, wherever they apply, with `"visibility":
"internal"`, so tools that know about them can still find them. `hidden`
items are left out of it too. Keys are always emitted in this order. Within
`clispec-help/1` keys are only ever added, never renamed or removed, and
their meaning does not change; anything else gets a new schema name.

### Shell completion

The completion engine is generated with the rest of the program, from the same
description, and runs inside the program; the shell scripts only pass it the
words being completed and print what it returns. So completion always matches
the installed binary, and a script never needs regenerating when the command
line changes.

```nim
import clispec

type Mode = enum debug, release

proc remotes(ctx: CliCompletionContext): seq[CliCompletion] =
  # A completer: values known only at run time. It may list everything;
  # only those that start with `ctx.prefix` are offered.
  @[CliCompletion(value: "origin", description: "the default remote"),
    CliCompletion(value: "upstream")]

cliProgram(Tool, "tool"):
  boolFlag verbose is bool, short = 'v', help = "Talk more"
  subcmd "build", help = "Build a project", aliases = ["b"]:
    flag mode is Mode, help = "Build mode"
    flag remote is string, complete = remotes
    flag log is string, complete = cliCompleteFiles
  subcmd "internal", visibility = internal:
    subcmd "dump":
      boolFlag deep is bool

proc values(cs: seq[CliCompletion]): seq[string] =
  for c in cs: result.add c.value

assert values(Tool.complete(@[""])) == @["build"]
assert values(Tool.complete(@["build", "--m"])) == @["--mode"]
assert values(Tool.complete(@["build", "--mode", ""])) == @["debug", "release"]
assert values(Tool.complete(@["b", "--remote=u"])) == @["--remote=upstream"]
assert values(Tool.complete(@["internal", ""])) == @["dump"]

# In `main`: a completion request is a CliHelpRequest whose text is printed.
proc main(argv: seq[string]): int =
  if argv.len == 2 and argv[0] == "completion":
    var shell: CliShell
    if not cliParseShell(argv[1], shell):
      return 2
    stdout.write Tool.completionScript(shell)
    return 0
  try:
    discard Tool.load(argv)
  except CliHelpRequest as e:   # --help, and completion requests
    stdout.write e.text
  except CliUsageError as e:
    return e.exitCode

assert main(@["__complete", "fish", "build", "--mode", "r"]) == 0
```

What is offered where:

- A word starting with `-` gets every spelling of the command's flags that
  starts with it (`--name`, `--no-name` for a negatable flag, the `alias`,
  `-x`), then `--help` and `-h` (`--help` alone under `longHelpOnly`;
  `--version` is not offered), then `--help-all` in a program that
  declares a `secondary` subcommand. A flag that only takes `--flag=value`
  (`format = equals`) is offered as `--flag=`.
- After a flag that takes the next word as its value, and in
  `--flag=<partial>`, the flag's values: its closed set (`values`, or an
  enum's values), else its completer's, else `true`/`false` for a switch
  written `--flag=`. In a list with a `separator`, the element after the last
  separator. Under `colonValues`, `--flag:<partial>` too; under
  `equalsTakesNext`, a word after `--flag=` that does not start with `-`.
- Any other word: the subcommands of both tiers (a name, or an alias when
  the name does not match what was typed), then the values of the
  positional the word fills.
  After `--`, positionals only, and in a command that declares an
  `afterSeparator` positional only that positional's values (a word before
  `--` never gets them). Under `commandMatching ignoreCase |
ignoreStyle` what was typed is compared in that mode and the declared
  word is offered (`LI` offers `list`; a shell that filters by what was
  typed may drop it).
- From where a `rest` positional starts, only its own values: no flag and
  no subcommand.
- `hidden` items and `internal` parameters are never offered; an `internal`
  subcommand only inside the command that holds it, never at the root.
  Nor is a [retired spelling](#retired-spellings).

A completer is a `CliCompleter`, `proc (ctx: CliCompletionContext):
seq[CliCompletion]` (a plain proc of that signature, or any expression of that
type, such as a call that returns a closure). The context names the program,
the command path, the parameter, the words before the one being completed and
the typed `prefix`. A completer that raises offers nothing; a `complete`
expression of another type is a compile error naming the parameter.
`cliCompleteFiles` and `cliCompleteDirectories` complete paths, listing a
directory's entries sorted by value (byte order), never in the order the
filesystem's readdir returns them.

**The scripts.** `Tool.completionScript(shell)` (or
`cliCompletionScript(shell, program)`) returns the script for `cshBash`,
`cshZsh`, `cshFish` or `cshPowerShell`, with the program name filled in. A
program typically prints it from a `completion <shell>` command of its own,
and the user installs it:

| Shell      | Install                                                                                                          |
| ---------- | ---------------------------------------------------------------------------------------------------------------- |
| Bash       | `source <(tool completion bash)` in `~/.bashrc`, or save it as `~/.local/share/bash-completion/completions/tool` |
| Zsh        | save it as `_tool` in a directory of `$fpath`, or `source <(tool completion zsh)` after `compinit`               |
| Fish       | save it as `~/.config/fish/completions/tool.fish`                                                                |
| PowerShell | `tool completion powershell \| Out-String \| Invoke-Expression` in `$PROFILE`                                    |

**Install locations.** `clispec/completion_install` is the table of where
each shell loads an installed script from, for a program's own installer
(a `completion install` command, a package build, an install script). It is
data and pure functions: it reads no environment variable and writes no
file, so an installer and its tests compute the same paths.

- `cliCompletionFileName(shell, program)`: `tool`, `_tool`, `tool.fish`,
  `tool.ps1`.
- `cliUserCompletionTargets(shell, program, env)`: what a per-user install
  writes, the script and the rc or profile blocks that load it, from a
  `CliInstallEnv` (`cliInstallEnv(lookup)` fills it from `HOME`,
  `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `ZDOTDIR`, `BASH_COMPLETION_USER_DIR`
  and `LOCALAPPDATA`; `windows = true` for Windows' PowerShell profiles).
- `cliSystemCompletionTargets(shell, program, family, prefix, psHome)` and
  `cliSystemCompletionDirs`: the system-wide directories for the local
  administrator (`cpfLinuxLocal` on Linux and `cpfLocal` on macOS and the
  BSDs, both `/usr/local`) and for each kind of package
  (Debian, rpm, Arch, FreeBSD, OpenBSD and NetBSD, Homebrew, a macOS
  installer package, Nix, Windows).
- `cliProfileBlockBody(shell, program, script)`: the text of the block that
  loads an installed script, every name and path quoted.
- `cliBashCompletionLoaders()`: where bash-completion's loader is looked
  for (without it, the per-user Bash file needs the `~/.bashrc` block).
- `cliIsGeneratedCompletionScript(content, shell, program)`: whether a file
  is a clispec script for that program, so an installer replaces only its
  own files.

| Shell      | Per user                                                                                                     | System-wide (`cpfLinuxLocal`; `cpfLocal` differs only for Fish) |
| ---------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Bash       | `${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-~/.local/share}/bash-completion}/completions/tool`; without bash-completion, also a `~/.bashrc` block that sources it | `/usr/local/share/bash-completion/completions/tool`       |
| Zsh        | `${XDG_DATA_HOME:-~/.local/share}/zsh/site-functions/_tool`, and a `${ZDOTDIR:-~}/.zshrc` block that puts it on `$fpath` | `/usr/local/share/zsh/site-functions/_tool`               |
| Fish       | `${XDG_CONFIG_HOME:-~/.config}/fish/completions/tool.fish`                                                   | `/etc/fish/completions/tool.fish` (fish searches `/usr/local/share` only when `XDG_DATA_DIRS` names it); `cpfLocal`: `/usr/local/share/fish/vendor_completions.d/tool.fish` |
| PowerShell | `${XDG_DATA_HOME:-~/.local/share}/tool/completions/tool.ps1` (`%LOCALAPPDATA%\tool\completions\tool.ps1` on Windows), loaded by a block in `$PROFILE.CurrentUserAllHosts` | the script under the prefix, loaded by a block in `$PSHOME/profile.ps1` |

The module's documentation cites each shell's own documentation for these.

**PowerShell and the execution policy.** On Windows, PowerShell's
[execution policy](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies)
decides which script files may run, and `$PROFILE` is a script file. The
clispec script itself is not: `Invoke-Expression` runs the text the program
printed (or the text of the file an installer saved it to) as commands, which
no policy blocks, so the script never needs signing. What the policy governs is whether
PowerShell loads `$PROFILE` at all:

- `Restricted` runs no script files, the profile included. It is Windows
  PowerShell 5.1's default on a Windows client (Windows 10 and 11), and the
  effective policy of any PowerShell on a Windows client when no scope sets
  one. Under it PowerShell refuses the profile at startup ("running scripts
  is disabled on this system") and the line above never runs.
- `RemoteSigned` (Windows PowerShell's default on Windows Server, and the
  default PowerShell 7 documents for Windows) loads a profile written on the
  machine; a profile downloaded from the internet must be signed or
  unblocked with `Unblock-File`.
- `AllSigned` loads the profile only when it is signed; the clispec text it
  evaluates needs no signature of its own.
- `Unrestricted` and `Bypass` load it. On Linux and macOS the policy is
  always `Unrestricted` and is not enforced.

`Get-ExecutionPolicy -List` shows the effective policy and which scope sets
it. To let your own profile load without administrator rights, set
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, unless Group Policy
fixes the policy, in which case it overrides that setting. Without a profile,
run `tool completion powershell | Out-String | Invoke-Expression` in the
session: completion then works until the session ends, under any policy.
Saving the script as a `.ps1` file and dot-sourcing it instead makes it a
script file subject to the policy, so prefer `Invoke-Expression`.

**The protocol.** A script runs `tool __complete <shell> <arguments...>`
and prints what the program writes. `load` answers it by raising
`CliCompletionRequest`, a `CliHelpRequest` whose `text` is the answer, so a
program that prints help requests and exits 0 answers completion too. Zsh and
Fish pass the words after the program name (the last is the one being
completed) and read `value<TAB>description` lines. Bash passes
`$COMP_WORDBREAKS` and the command line up to the cursor, which the program
reads with the shell's quoting rules, and reads back the quoted text that
replaces the word Bash completes. PowerShell passes each word as `:` plus the
base64 of its UTF-8 bytes (some versions drop empty arguments and mangle
quotes when they run a native program) and reads `completion text<TAB>list
text<TAB>tooltip` lines. Nothing the program prints is evaluated by the
scripts. A program that dispatches some words itself before parsing (a thin
front end that hands everything else to another executable, say) forwards
`__complete ...` unchanged to the executable that holds the description;
`CliOptions.completionEntry` changes the word, and `Tool.completionReply`
computes the answer without `load`.

### How parsing is layered

Parsing runs in phases, each a procedure of `clispec/parser`, so other
layers can reuse them: `cliTokenize` reads argv against the grammar and
collects the _candidates_ each parameter receives (`clispec/candidates`),
each with its argv index and the spelling used; `cliMerge` picks, per
parameter, the candidates its value is made of (every occurrence of a list or
a counted flag, the last of anything else); `cliDecide` settles each
parameter (from the command line, implied, default, or unset) and reports a
missing required one; the generated code then converts the decisions into the
typed object. `cliResolve` runs the first three.

A library that adds other sources replaces the merge: it supplies candidates
of the same type for its sources (`source`, `group` and `site` say which
source each came from) and fills the same `CliResolution`, and clispec
decides and builds the object as for the command line alone. For code it
generates beside the configuration object, `clispec/program` exports the
names and shapes it uses: `cliGeneratedNames`, `cliObjectHolds`,
`cliBranches`, `cliShapedTypeDecls` (a type of the configuration object's
shape with one field type throughout), `cliShapedBuilderProc`,
`cliShapedVisitorProc`, `cliFieldBare`, `cliFieldAllowed`, and
`cliProgramArgs` for a macro written like `cliProgram`.

## Configuration files, the environment and origins

A parameter can be supplied by three kinds of source. From the lowest
precedence to the highest: configuration files, in the layers a program
declares (lowest first); the environment variables its `env` lists; and the
command line. Clispec reads only the command line. The rest is
[confutils](https://github.com/metacraft-labs/nim-confutils)': its
`cliConfiguration` macro takes the same description as `cliProgram`,
generates everything `cliProgram` does, and adds

- `Tool.load(argv, sources)` and `Tool.loadWithOrigins(argv, sources)`,
  which read the configuration layers and the environment of a
  `CliSources` and merge them with the command line, per parameter, as its
  `merge` declares (`replace`, `append`, `errorOnConflict` or a combine
  proc); a binding layer's values are enforced over every other source;
- an origin object of the configuration object's shape, recording for every
  value where it came from (a file's path, line and key, a variable, or the
  argv index and spelling clispec's parser recorded) and every value it
  overrode;
- `argvOf(origins, only, group, commandWords)` over any command's origin
  object: the command-line part of the configuration, written back as
  `canonicalArgv` writes a command line (see
  [Writing a command line back](#writing-a-command-line-back)), with no
  value an environment variable, a file, a default or an implication gave;
- configuration files read through a small format interface, TOML first,
  validated against a schema generated from the description: the
  `configSchema` identifier, the keys as each source's naming convention
  spells them, and the parameters' types.

What the description declares for those sources is still checked here, at
compile time: `key` and `env` against `sources`, the naming conventions and
their overrides, reserved keys (`schema`, `extensions`) in a program that
declares a `configSchema`, and `merge = append` on a parameter that is not a
list. A combine proc's signature is checked by confutils, which calls it.

### Checking configuration a program writes for another

A program that writes a configuration file for another program (a build
system generating a tool's settings, an installer, a migration) can check
what it writes against the reader's description, without reading any file
format itself. `clispec/config_check` derives a `CliConfigTable` from a
grammar once: every key, spelt in the chosen file source's naming
convention, with its value type, whether it is a list and its closed value
set. It is a plain value, so a `const` holds it and both compile-time code
and run-time code read it. `cliCheckEntry` checks one key and value against
it, and `cliValidateDocument` walks a whole document, in a format-neutral
flattened form (`CliConfigDocument`, which a format adapter fills, with
lines), once:

```nim
import std/strutils
import clispec

type Mode = enum
  fast, safe

cliProgram(Svc, "svc"):
  configSchema "svc.config.v1"
  convention file = snakeCase
  flag poolSize is int, default = 4
  flag mode is Mode, default = safe

const table = cliConfigTableOf(Svc.cliGrammar)

proc entry(key: string; kind: CliConfigValueKind; text: string;
           line: int): CliConfigEntry =
  CliConfigEntry(key: key.split('.'), line: line,
    value: CliConfigValue(kind: kind, text: text))

let doc = CliConfigDocument(entries: @[
  entry("schema", ccvString, "svc.config.v1", 1),
  entry("pool-size", ccvInteger, "8", 2),
  entry("mode", ccvString, "slow", 3)])
let issues = cliValidateDocument(table, doc)
assert issues.len == 2
assert cliConfigIssueMessage(issues[0], "svc.toml") ==
  "svc.toml:2: unknown key 'pool-size' (did you mean 'pool_size'?)"
assert cliConfigIssueMessage(issues[1], "svc.toml") ==
  "svc.toml:3: key 'mode' has the string \"slow\"; expected one of: fast, safe"

# The same check at compile time, on a value described by its type:
const fits = cliCheckEntry(table, ["pool_size"], cliConfigShapeOf(int))
static: assert fits.kind == cikNone
```

A description that declares a `configSchema` is a program reading files in
clispec's own layout: every key its parameters derive or declare is valid,
the whole file must carry the `schema` string, and the `extensions` table is
never checked. A description without one, such as an external tool's, holds
only the keys it spells itself with `key` (or a `perSource` entry): a
derived key is clispec's convention, not something the tool reads. A
consumer whose `cli:` model carries an extension gets the table's constant
from `cliConfigTableCode(model, program, source)`, which fills in the value
types and closed sets where the description's types are visible.
`cliConfigTableDerivationCount()` counts the tables derived at compile time,
so a consumer can test that it derives each description's table once however
many snippets it checks. confutils runs the same checks when it loads a
configuration layer (a value outside a closed set is rejected there when it
is converted, naming the file and the line).

## Extending the model

A program that runs other tools often needs to say more about a command line
than how to spell it: which parameters name files the command reads or writes,
or what to do before running it. Clispec does not know those words; it lets a
consumer add them.

Both model types carry a typed `ext` field whose type is a generic parameter:
`CliParam[P]` carries a `P` and `CliCommand[C, P]` carries a `C`. A consumer
defines two object types and two hooks, and instantiates the parser with them:

```nim
import std/[macros, strutils]
import clispec

type
  DocParam = object
    owner: string
  DocCommand = object
    summary: string

proc parseCliParamExtension(ext: var DocParam; kind: CliParamKind;
                            arg: NimNode): bool =
  # Receives every `name = value` argument clispec does not take itself.
  if cliIdentText(arg[0]).normalize == "owner":
    ext.owner = cliStrLit(arg[1], "owner")
    return true

proc parseCliCommandExtension(cmd: var CliCommand[DocCommand, DocParam];
                              stmt: NimNode; scope: CliScope): bool =
  # Receives every statement that is not a parameter, `call:` or `subcmd`,
  # in source order, with the command as parsed so far.
  if cliCalleeName(stmt).normalize == "summary":
    cmd.ext.summary = cliStrLit(stmt[1], "summary")
    return true

macro docModel(body: untyped): untyped =
  newLit(parseCliModel[DocCommand, DocParam](body, DocCommand()))

const model = docModel:
  summary "builds things"
  subcmd "build":
    flag output is string, owner = "release team"
```

The hooks are plain overloads, found through `mixin` where the consumer
instantiates the parser, so they run at compile time inside the consumer's
macro and can reject a declaration with `error`. A nested scope starts from a
copy of its parent's `ext`, so command-level declarations are inherited the
way parameters are. Input that no hook claims is ignored. The library's own
named arguments and statements (above) are read by the library and never
reach a hook, so an extension's vocabulary must avoid those words.

`NoCliExtension` is the empty extension, and `PlainCliModel`,
`PlainCliCommand` and `PlainCliParam` are the model without one.

## Development

```sh
nix develop          # nim, just, the hook tools and the shells e2e drives
just test            # the test suite
just e2e             # real bash, zsh, fish and pwsh completing in a pseudo-terminal
just lint            # nim check over the library and the tests, also for Windows and macOS
```

Without Nix, any Nim 2.x will do: `nimble test` (and `nimble e2e`, which
skips, loudly, each shell that is not on `PATH`).

## License

Apache-2.0. See [LICENSE](LICENSE).
