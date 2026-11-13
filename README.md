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

The layers planned next are shell completion and layered loading of
configuration files and the environment, with a record of where every value
came from. Clispec is meant to replace
[confutils](https://github.com/status-im/nim-confutils) for programs that
describe their own command line. It also describes the command lines of
external tools that a program runs.

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
proc repoNames(prefix: string): seq[string] = @[]

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

| Argument                                                         | Meaning                                                                                                                                                                                                                                   |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `help = "<text>"`                                                | the description shown by help and completion                                                                                                                                                                                              |
| `default = <expr>`                                               | the value when no source supplies one; not together with `required = true`. A positional with a default is optional                                                                                                                       |
| `env = ["NAME", ...]`                                            | the environment variables that supply the value, first match wins (one name may be written without brackets)                                                                                                                              |
| `values = [a, b, c]`                                             | the closed set of accepted values (elements, for a list); an enum type is a closed set by itself                                                                                                                                          |
| `complete = <completer>`                                         | a proc that completes the value dynamically                                                                                                                                                                                               |
| `key = "section.name"`                                           | the configuration-file key, replacing the derived one                                                                                                                                                                                     |
| `sources = {cli, env, file}`                                     | which sources may supply the value (default: all three)                                                                                                                                                                                   |
| `merge = replace \| append \| errorOnConflict \| <combine proc>` | how values from several sources combine: the highest source wins (a list repeated within one source collects); lists are concatenated lowest source first; two different values are an error; or a proc of yours receives every candidate |
| `separator = ","`                                                | a list may be given as one delimited value                                                                                                                                                                                                |
| `implies = [<param> = <value>, ...]`                             | setting this parameter sets the others unless they are given explicitly                                                                                                                                                                   |
| `visibility = shown \| internal \| hidden`                       | `internal`: left out of the primary help and completion, listed by the help of the command that holds it; `hidden`: accepted and listed nowhere                                                                                           |

A flag also accepts `short = 'x'` (a one-letter spelling, `-x`, beside
`--<name>`), `optionalValue = <expr>` (the flag may appear bare, taking this
value, or as `--flag=value`; it never takes the next word), `negatable = true`
(`--no-<name>` sets a `bool` to false) and `counted = true` (`-v`, `-vv`: an
integer counting the occurrences).

A command takes `help`, `aliases` and `visibility` in its head
(`subcmd "build", help = "...", aliases = ["b"]:`, `call(help = "..."):`), or
its help as a `help "<text>"` statement in its body, which is also how the
root command gets one. `group "<title>"[, help = "<text>"]:` lists the
parameters declared inside it under one heading in help; it opens no command
and changes no scoping, and may be reopened (in another command, say) to add
more parameters to the same heading.

**Names.** A parameter's name is its canonical long flag (`output` is
`--output`); `alias` adds a spelling. Its configuration-file key is the path of
the command that declares it followed by its name, joined with `.` and spelt as
declared: `jobs` above is `build.jobs`, `color` is `color`. A parameter
inherited by nested commands keeps the key of the command that declared it.
`key` replaces the derived key, and a parameter whose `sources` exclude
`file` has none. Environment variables are never derived: a parameter reads
exactly the variables its `env` lists.

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
`implies` naming no parameter of the command, an argument given twice, two
subcommands of one command answering to the same word, `aliases` on `call:`,
and a `help` statement inside a `group` section (the section's help goes in
its head).

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
  except CliHelpRequest as e:
    stdout.write e.text
  except CliUsageError as e:
    stderr.writeLine "tool: ", e.msg
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

Generated for `Tool` (exported when written `cliProgram(Tool*, ...)`):

| Procedure                                               | Does                                                           |
| ------------------------------------------------------- | -------------------------------------------------------------- |
| `Tool.load(argv, options = CliOptions())`               | parses `argv` (without the program name)                       |
| `Tool.load(options = CliOptions())`                     | parses the process's own arguments                             |
| `Tool.helpText(path = [])` / `Tool.helpJson(path = [])` | the help of the command reached by the subcommand words `path` |
| `Tool.cliGrammar` / `Tool.cliModel`                     | the parser's tables and the model, both constants              |

`CliOptions` sets the program name used in messages, the exit code of usage
errors (`usageExitCode`, 2 when not set) and `disableHelpFlag`. A consumer
whose model carries an extension generates the same code from its own macro
with `cliProgramCode(model, typeName, program, exported)`.

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
  followed by its value as a separate word.
- A `seq` collects every occurrence, each split on its `separator` if it has
  one. Any other parameter given twice keeps its last value.
- `--` ends the flags. The first bare word after a command with subcommands
  names one (or one of its `aliases`); when the command also has a `call:`,
  any other word, or a flag (or a cluster of short flags) that only the
  `call:` declares, runs the `call:`.
- Positionals fill in `position` order; a list positional takes every word
  that the positionals after it do not need. A command with subcommands
  declares its positionals in its `call:` (the word after it is a
  subcommand word), which `cliProgram` enforces at compile time, along with
  at most one list positional per command and no subcommands inside a
  `call:`.
- `hidden` and `internal` items are accepted like any other.

### Errors

`load` never ends the process. A command line it rejects raises a
`CliUsageError` whose `kind` is one of `CliErrorKind`; each kind has one
wording, and every wording names the command (`'tool build'`):

| Kind                      | Wording                                                                                                                  |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `cekUnknownFlag`          | `unknown flag '--nope' for 'tool build'`                                                                                 |
| `cekUnknownSubcommand`    | `unknown subcommand 'frob' for 'tool'; expected one of: build, run`                                                      |
| `cekMissingSubcommand`    | `'tool' needs a subcommand; expected one of: build, run`                                                                 |
| `cekMissingValue`         | `flag '--jobs' of 'tool build' needs a value`                                                                            |
| `cekInvalidValue`         | `invalid value 'many' for '--jobs' of 'tool build'; expected an integer`                                                 |
| `cekUnexpectedPositional` | `unexpected argument 'extra' for 'tool build'`                                                                           |
| `cekMissingRequired`      | `missing required parameter '<target>' of 'tool build'`                                                                  |
| `cekConflictingSources`   | `conflicting values for '--jobs' of 'tool build': ...` (raised once configuration files and the environment are sources) |

The error also carries the offending argv index, the spelling, the value,
what was expected and `exitCode`, the program's declared usage exit code.

### Help

`--help` and `-h` raise `CliHelpRequest` with the help of the command they
were given to in `text`; `--help=json` gives the machine-readable form. A
program turns this off with `CliOptions(disableHelpFlag: true)`, and a flag
the program itself spells `--help` or `-h` takes precedence. The help of a
command lists its subcommands, its positionals and every flag it accepts,
ungrouped flags under `Options:` and then each `group` section. For a
smaller program than the one above, it looks like this:

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

`hidden` items are never listed. `internal` items are listed only in the help
of the command that holds them (a subcommand in its parent's, a parameter in
its declaring command's) and never in the root command's help, which is the
program's primary help; an internal command's own help is complete, so
`tool internal --help` documents what `tool --help` leaves out.

The machine-readable form, `helpJson`, is a JSON document with the schema
name `clispec-help/1`, meant for completion and editor hints:

```text
{"schema": "clispec-help/1", "program": "tool", "command": COMMAND}
COMMAND   = {"name", "path", "aliases", "help", "visibility", "usage",
             "parameters": [PARAMETER, ...], "commands": [COMMAND, ...]}
PARAMETER = {"name", "kind": "flag" | "positional", "spellings",
             "negation": string | null, "value": "none" | "required" | "optional",
             "format": "separate" | "equals" | "concat",
             "valueName", "choices", "list", "separator": string | null,
             "counted", "required", "default": string | null, "env", "help",
             "group": string | null, "visibility", "position" (positionals),
             "declaredIn", "dynamicCompletion", "completer": string | null}
```

`value` says whether a flag takes a value and `format` how (see
[Accepted forms](#accepted-forms)); `choices` is the closed value set, empty
when the set is open; `completer` is the `complete` expression as written.

`commands` nests the listed subcommands recursively, and the listing rules
above decide what appears. Keys are always emitted in this order. Within
`clispec-help/1` keys are only ever added, never renamed or removed, and
their meaning does not change; anything else gets a new schema name.

### How parsing is layered

Parsing runs in phases, each a procedure of `clispec/parser`, so later layers
can reuse them: `cliTokenize` reads argv against the grammar and collects the
_candidates_ each parameter receives, each with its argv index and the
spelling used; `cliMerge` picks the winners; `cliDecide` settles each
parameter (from a source, implied, default, or unset) and reports a missing
required one; the generated code then converts the decisions into the typed
object. `cliResolve` runs the first three.

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
nix develop          # nim, just and the hook tools
just test            # the test suite
just lint            # nim check over the library and the tests
```

Without Nix, any Nim 2.x will do: `nimble test`.

## License

Apache-2.0. See [LICENSE](LICENSE).
