# nim-cli-spec

Clispec is a Nim library for describing a command line once, declaratively,
and deriving everything else from that description. This release provides the
first two layers:

- **`clispec/model`**: a typed model of a command tree: commands and
  subcommands with their aliases, help and visibility; positional parameters
  and flags with their types, spellings, formats, placement, defaults,
  environment variables, configuration keys, permitted sources, merge rules,
  value sets, completers and implications.
- **`clispec/dsl`**: the `cli:` description language, parsed at compile time
  into that model.

The layers planned on top of the model generate code from it: a typed
configuration object, an argv parser, help text, shell completion and layered
loading of configuration files, with a record of where every value came from.
Clispec is meant to replace [confutils](https://github.com/status-im/nim-confutils)
for programs that describe their own command line. It also describes the
command lines of external tools that a program runs.

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
