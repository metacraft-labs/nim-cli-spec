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
- **Layered sources and origins**: the same object filled from
  configuration files (in layers the program declares, some of which may
  enforce their values), the environment and the command line, merged per
  parameter, together with an origin object recording where every value
  came from and what it overrode (`clispec/sources`, `clispec/origins`).
  Configuration files are read through a small format interface; TOML is
  provided by the optional `clispec/toml_source`, the only module that needs
  a serialization library.

The layer planned next is shell completion. Clispec is meant to replace
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

| Argument                                                         | Meaning                                                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `help = "<text>"`                                                | the description shown by help and completion                                                                                                                                                                                                                                     |
| `default = <expr>`                                               | the value when no source supplies one; not together with `required = true`. A positional with a default is optional                                                                                                                                                              |
| `env = ["NAME", ...]`                                            | the environment variables that supply the value, first match wins (one name may be written without brackets)                                                                                                                                                                     |
| `values = [a, b, c]`                                             | the closed set of accepted values (elements, for a list); an enum type is a closed set by itself                                                                                                                                                                                 |
| `complete = <completer>`                                         | a proc that completes the value dynamically                                                                                                                                                                                                                                      |
| `key = "section.name"`                                           | the configuration-file key, replacing the derived one                                                                                                                                                                                                                            |
| `sources = {cli, env, file}`                                     | which sources may supply the value (default: all three)                                                                                                                                                                                                                          |
| `merge = replace \| append \| errorOnConflict \| <combine proc>` | how values from several sources combine: the highest source wins (a list repeated within one source collects); lists are concatenated lowest source first; two different values are an error; or a proc of yours receives every source's value (see [Merge rules](#merge-rules)) |
| `separator = ","`                                                | a list may be given as one delimited value                                                                                                                                                                                                                                       |
| `implies = [<param> = <value>, ...]`                             | setting this parameter sets the others unless they are given explicitly                                                                                                                                                                                                          |
| `visibility = shown \| internal \| hidden`                       | `internal`: left out of the primary help and completion, listed by the help of the command that holds it; `hidden`: accepted and listed nowhere                                                                                                                                  |

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
the command that declares it followed by its name, joined with `.`: `jobs`
above is `build.jobs`, `color` is `color`. Both are spelt in their source's
naming convention, below, which by default is the name as declared. A parameter
inherited by nested commands keeps the key of the command that declared it.
`key` replaces the derived key, and a parameter whose `sources` exclude
`file` has none. Environment variables are never derived: a parameter reads
exactly the variables its `env` lists.

`configSchema "<id>"` directly under `cli:` names the schema identifier
every configuration file must declare (see
[Configuration files](#configuration-files)).

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
convention, then the conversion. Help, the machine-readable help, the
configuration schema and the origin object all show the spelling each source
uses.

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
assert Srv.configSchema.keys[0].key == "write_report"
assert Srv.configSchema("project").keys[1].key == "web.port"
assert Srv.configSchema("project").keys[2].key == "base-url"
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
`implies` naming no parameter of the command, an argument given twice, two
subcommands of one command answering to the same word, `aliases` on `call:`,
a `help` statement inside a `group` section (the section's help goes in
its head), `keyStyle`, `convention` or `configSchema` anywhere but directly
under `cli:`, an unknown convention or one source's convention given twice,
a `perConvention` entry for `declared` or for one convention twice, a
`perSource` entry for a file source the description does not declare, for
`file` (that is `key`), for one source twice, for `cli` on a positional or
when `sources` exclude `cli`, or for a file source when they exclude `file`,
and two parameters of one command whose long flags or keys in one source
come out the same once converted and overridden. The generated checks also reject
`merge = append` on a parameter that is neither a `seq` nor counted, and a
combine proc that does not have the signature below. In a `cliProgram` that
declares a `configSchema`, a configuration key that is `schema` or lies
under `extensions` is an error too: both belong to the file itself.

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

Generated for `Tool` (exported when written
`cliProgram(Tool, "tool", exported = true):`):

| Procedure                                                       | Does                                                                         |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `Tool.load(argv, options = CliOptions())`                       | parses `argv` (without the program name)                                     |
| `Tool.load(options = CliOptions())`                             | parses the process's own arguments                                           |
| `Tool.load(argv, sources, options)` / `Tool.load(sources, ...)` | fills the object from configuration files, the environment and `argv`        |
| `Tool.loadWithOrigins(argv, sources = CliSources(), options)`   | the same, and the origin object: `tuple[config: Tool, origins: ToolOrigins]` |
| `Tool.configSchema`                                             | the configuration-file schema: its identifier and every key with its type    |
| `Tool.helpText(path = [])` / `Tool.helpJson(path = [])`         | the help of the command reached by the subcommand words `path`               |
| `Tool.cliGrammar` / `Tool.cliModel`                             | the parser's tables and the model, both constants                            |

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

| Kind                      | Wording                                                                                                                                   |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `cekUnknownFlag`          | `unknown flag '--nope' for 'tool build'`                                                                                                  |
| `cekUnknownSubcommand`    | `unknown subcommand 'frob' for 'tool'; expected one of: build, run`                                                                       |
| `cekMissingSubcommand`    | `'tool' needs a subcommand; expected one of: build, run`                                                                                  |
| `cekMissingValue`         | `flag '--jobs' of 'tool build' needs a value`                                                                                             |
| `cekInvalidValue`         | `invalid value 'many' for '--jobs' of 'tool build'; expected an integer`                                                                  |
| `cekUnexpectedPositional` | `unexpected argument 'extra' for 'tool build'`                                                                                            |
| `cekMissingRequired`      | `missing required parameter '<target>' of 'tool build'`                                                                                   |
| `cekConflictingSources`   | `conflicting values for '--jobs' of 'tool build': '4' from /etc/tool.toml:3 (layer 'system') and '8' from environment variable TOOL_JOBS` |

The error also carries the offending argv index, the spelling, the value,
what was expected and `exitCode`, the program's declared usage exit code. An
invalid value that came from a configuration file or the environment says
where (`invalid value 'many' for '--jobs' of 'tool' (from environment
variable TOOL_JOBS); expected an integer`), in `source` as well; its argv
index is -1.

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
{"schema": "clispec-help/1", "program": "tool", "command": COMMAND,
 "conventions": {"cli": CONVENTION, "file": CONVENTION, SOURCE: CONVENTION, ...}}
COMMAND   = {"name", "path", "aliases", "help", "visibility", "usage",
             "parameters": [PARAMETER, ...], "commands": [COMMAND, ...]}
PARAMETER = {"name", "kind": "flag" | "positional", "spellings",
             "negation": string | null, "value": "none" | "required" | "optional",
             "format": "separate" | "equals" | "concat",
             "valueName", "choices", "list", "separator": string | null,
             "counted", "required", "default": string | null, "env", "help",
             "group": string | null, "visibility", "position" (positionals),
             "declaredIn", "dynamicCompletion", "completer": string | null,
             "configKeys": {"file": KEY, SOURCE: KEY, ...}}
```

`value` says whether a flag takes a value and `format` how (see
[Accepted forms](#accepted-forms)); `choices` is the closed value set, empty
when the set is open; `completer` is the `complete` expression as written.
`spellings` and `negation` are spelt in the command line's convention;
`configKeys` gives the parameter's key in every file source (`{}` when no file
may supply it), and `conventions` the convention of every source.

`commands` nests the listed subcommands recursively, and the listing rules
above decide what appears. Keys are always emitted in this order. Within
`clispec-help/1` keys are only ever added, never renamed or removed, and
their meaning does not change; anything else gets a new schema name.

### How parsing is layered

Parsing runs in phases, each a procedure of `clispec/parser`, so later layers
can reuse them: `cliTokenize` reads argv against the grammar and collects the
_candidates_ each parameter receives, each with its argv index and the
spelling used; `cliSourceCandidates` (`clispec/sources`) collects those of the
configuration layers and the environment; `cliMerge` picks the winners and
records each parameter's origin; `cliDecide` settles each parameter (from a
source, implied, default, or unset) and reports a missing required one; the
generated code then converts the decisions into the typed object.
`cliResolve` runs the first three (four, given `CliSources`).

## Configuration files, the environment and origins

A parameter can be supplied by three kinds of source. From the lowest
precedence to the highest: configuration files, in the layers the program
declares (lowest first); the environment variables its `env` lists; and the
command line. `sources = {...}` restricts a parameter to some of them (one
that excludes `cli` is not accepted on the command line and not listed in
help).

```nim
import std/[os, tables, tempfiles]
import clispec, clispec/toml_source

proc strictest(candidates: openArray[CliSourcedValue[int]]): int =
  for c in candidates:
    result = max(result, c.value)

cliProgram(Tool, "tool"):
  configSchema "tool.config.v1"
  convention file = snakeCase
  flag jobs is int, default = 4, env = ["TOOL_JOBS"]
  flag searchPaths is seq[string], merge = append, separator = ":",
    env = ["TOOL_PATH"]
  flag level is int, merge = strictest
  flag token is string, sources = {env, file}, env = ["TOOL_TOKEN"]

let dir = createTempDir("tool_", "")
writeFile(dir / "system.toml", """
schema = "tool.config.v1"
jobs = 2
""")
writeFile(dir / "user.toml", """
schema = "tool.config.v1"
jobs = 6
level = 3
search_paths = ["/usr/share/tool"]

[extensions]
my_editor_settings = { theme = "dark" }
""")

let sources = CliSources(format: tomlCliFormat(),
  layers: @[
    CliLayer(name: "system", path: dir / "system.toml", binding: true),
    CliLayer(name: "user", path: dir / "user.toml"),
    CliLayer(name: "project", path: dir / "absent.toml")], # skipped
  env: {"TOOL_PATH": "/opt/tool", "TOOL_TOKEN": "t0k"}.toTable)

let (conf, origins) = Tool.loadWithOrigins(@["--jobs", "8"], sources)
assert conf.jobs == 2                     # the system layer enforces it
assert origins.jobs.kind == cokEnforced
assert origins.jobs.winner.layer == "system" and origins.jobs.winner.line == 2
assert origins.jobs.losers[1].fate == cfIgnoredByEnforcement # --jobs 8
assert conf.searchPaths == @["/usr/share/tool", "/opt/tool"]
assert conf.level == 3 and conf.token == "t0k"
echo cliDescribe(origins.jobs)
removeDir(dir)
```

### Layers belong to the program

A `CliSources` lists the program's layers, lowest precedence first, each a
`CliLayer` with a `name` (what origins and errors call it), a `path`,
`binding` and `required` (a missing file is an error rather than a skipped
layer). Every value a **binding** layer sets is _enforced_: no other source,
the environment and the command line included, can override it, and each
attempt is recorded in the origin as ignored. When two binding layers set the
same key, the lower one enforces it. An enforced value ignores the merge
rule: it is not combined, appended or reported as a conflict.

The environment is a table the program passes in (`cliProcessEnv()` returns
the process's own); nothing reads the process environment behind its back.
An environment value is text, converted exactly like a command-line value; a
list parameter's variable is one element, or a delimited list when the
parameter declares a `separator`.

### Merge rules

Each source (a layer, the environment, the command line) gives a parameter
one value: within one source a list collects every occurrence, a counted
flag adds them up and anything else keeps its last. Across sources:

| `merge`           | Value                                                                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `replace`         | the highest source's (a higher source's list, even an empty one, replaces a lower one's)                                      |
| `append`          | every source's list concatenated, lowest first (a `seq` or counted parameter only)                                            |
| `errorOnConflict` | as `replace`, but two sources with different values are a `cekConflictingSources` error naming both (values compared as text) |
| a combine proc    | what the proc returns from every source's value                                                                               |

A combine proc has the signature
`proc (candidates: openArray[CliSourcedValue[T]]): T`, where `T` is the
parameter's type: it receives one `CliSourcedValue` per source that supplied
the parameter, lowest first, each with the converted `value` and its
`origin` (a `CliSite`). A proc that does not fit is a compile error naming
the parameter. If it raises, loading fails with `cekConflictingSources`
carrying its message.

Defaults and `implies` apply only after every source has been merged, so a
default never stands in for a value a file supplied.

### Configuration files

A file is read by a format adapter, a `CliConfigFormat` whose `parse` proc
(`CliConfigParser`) turns the file's text into a flat list of entries, each
with its key's segments, its value (string, integer, float, bool, date-time
or array) and its line. `tomlCliFormat()` from `clispec/toml_source` reads
TOML with
[nim-toml-serialization](https://github.com/status-im/nim-toml-serialization);
that module is not imported by `clispec`, so a program without configuration
files does not depend on any serialization library. An adapter for another
format implements the same proc.

The program's schema is then applied to the entries, for every format alike:

- The file must have a top-level `schema` string equal to the description's
  `configSchema`. A program without one loads no file.
- Every other key must be a parameter's configuration key, as the layer's
  source spells it, except keys under a top-level `extensions` table, which
  is the escape hatch for data the program does not define and is never
  read. A layer whose name is a file source the description declares
  (`convention "project" = ...`) uses that source's spelling; failing that,
  a layer whose format's name is one (`convention "toml" = ...`) uses that;
  any other layer uses the `file` source's. A key spelt in another source's
  convention is an unknown key.
- A value must have its parameter's type: a string (also for enums, paths
  and every type written as text), an integer, a float (an integer is
  accepted too) or a bool, and an array of those for a list parameter. A
  counted flag takes an integer.

Values are read verbatim: nothing is interpolated or expanded, and a list's
elements are never split on its `separator`. `Tool.configSchema` is the
schema as a value, with its keys spelt as the `file` source spells them, and
`Tool.configSchema("project")` the same for a named source; each key also
lists its spelling in every file source (`sourceKeys`). `cliConfigSchemaJson`
renders it as JSON under the schema name `clispec-config-schema/1` (keys are
only added within that name).

A file that breaks these rules raises a `CliConfigError`, whose `kind` is a
`CliConfigErrorKind`, each with one wording naming the file, the line and the
key where there is one:

| Kind                  | Wording                                                                        |
| --------------------- | ------------------------------------------------------------------------------ |
| `cfeUnknownKey`       | `/home/u/.config/tool.toml:4: unknown key 'jbos' (layer 'user')`               |
| `cfeMissingSchema`    | the file has no top-level `schema` string (the wording shows the expected one) |
| `cfeWrongSchema`      | `...:1: declares schema "tool.config.v2"; expected "tool.config.v1"`           |
| `cfeWrongType`        | `...:2: key 'jobs' has the string "four"; expected an integer`                 |
| `cfeSyntax`           | `...:3: is not valid:` followed by the format's own message                    |
| `cfeUnreadable`       | a required layer's file is missing, or a file cannot be read                   |
| `cfeNoSchemaDeclared` | the description declares no `configSchema`                                     |
| `cfeNoFormat`         | layers were given without a format                                             |

### The origin object

`loadWithOrigins` also returns an object of the same shape as the
configuration object (`ToolOrigins`, `ToolBuildOrigins`, ..., with the same
`command` discriminator) holding a `CliOrigin` per field:

- `winner`, a `CliSite`: its `kind` (`cokDefault`, `cokFile` with `path`,
  `line`, `key` (as the file spelt it), the `layer` name and the
  `fileSource` whose convention that spelling is, `cokEnv` with the
  `variable`, `cokCli` with the `argvIndex` and `spelling`, `cokImplied` with `impliedBy`,
  `cokEnforced` like a file, or `cokUnset`), also readable as `origin.kind`;
- `values`, the value as written;
- `losers`, every other value that was considered, in the order the merge
  considered them (layers lowest first, then the environment, then the
  command line), each with its `value`, its `site` and its `fate`:
  `cfOverridden`, `cfCombined` (part of an `append` or combined value) or
  `cfIgnoredByEnforcement`.

`cliDescribe(origin)` puts it in one line, for a debug report or an
`--explain` option.

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
