# nim-cli-spec

Clispec is a Nim library for describing a command line once, declaratively,
and deriving everything else from that description. This release provides the
first two layers:

- **`clispec/model`**: a typed model of a command tree: commands and
  subcommands, positional parameters and flags, with their types, spellings,
  formats and placement.
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
subcommand word). After a positional: `position = <n>` and `repeated = true`.
Write a switch that takes named arguments as `boolFlag <name> is bool`: in the
bare form the parser skips the first named argument, which this release keeps
so that existing declarations keep their meaning.

A nested scope sees every parameter its enclosing scopes declared before it
opened. `plainCliModel` returns a `CliModel` whose `root` is the scope directly
under `cli:` and whose `commands` lists every `call:` and `subcmd` scope.

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
    help: string
  DocCommand = object
    summary: string

proc parseCliParamExtension(ext: var DocParam; kind: CliParamKind;
                            arg: NimNode): bool =
  # Receives every `name = value` argument clispec does not take itself.
  if cliIdentText(arg[0]).normalize == "help":
    ext.help = cliStrLit(arg[1], "help")
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
    flag output is string, help = "where to write"
```

The hooks are plain overloads, found through `mixin` where the consumer
instantiates the parser, so they run at compile time inside the consumer's
macro and can reject a declaration with `error`. A nested scope starts from a
copy of its parent's `ext`, so command-level declarations are inherited the
way parameters are. Input that no hook claims is ignored.

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
