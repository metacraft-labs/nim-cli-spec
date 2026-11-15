# nim-cli-spec — Agent Instructions

Clispec: a typed model of a command line (`src/clispec/model.nim`), the
`cli:` description language that builds it at compile time
(`src/clispec/dsl.nim`), and `cliProgram` (`src/clispec/program.nim`), which
generates a program's typed configuration object, argv parser, help and
shell completion from it. `README.md` describes all of it and the extension mechanism; read it
first. Configuration files, the environment, merge rules and the origin
object are not here: confutils (`metacraft-labs/nim-confutils`) is
instantiated over a clispec description and provides them, delegating the
command line to this library. Clispec depends on nothing but the standard
library.

## Commands

- Dev shell: `nix develop` (nim, just and the pre-commit tools).
- Test: `just test` (also `nimble test`).
- End-to-end: `just e2e` (also `nimble e2e`): real bash, zsh, fish and
  pwsh, which the dev shell provides, driven in a pseudo-terminal. Kept out
  of `just test`; run it whenever completion, the scripts or help change.
  On Windows, where there is no Nix and no pseudo-terminal, it runs the
  PowerShell legs only (`TabExpansion2` in pwsh 7 and in Windows PowerShell
  5.1) and needs nothing but `nim` on `PATH`. From the checkout root in
  PowerShell, set `$env:CLISPEC_E2E_REQUIRE = 'pwsh,powershell'` and run
  `nimble e2e`, or without nimble
  `nim c -r --hints:off tests/e2e_cs_m5_real_shell_completion.nim`.
- Lint: `just lint` (`nim check` over the umbrella and every test).
- Build without running: `just build`.

## Layout

- `src/clispec.nim`: the umbrella; re-exports every module below.
- `src/clispec/model.nim`: the model types. Plain values, usable at compile
  time and at run time. Also the naming conventions: `cliWords` /
  `cliConvert` (the one word-splitting rule every source's spelling goes
  through) and the override precedence (`cliOverride`, `cliSpelling`,
  `cliSourceKey`).
- `src/clispec/dsl.nim`: the compile-time parser, the extension hooks'
  contract, and the `cli`-prefixed AST helpers extension hooks use.
- `src/clispec/grammar.nim`: the run-time tables (`CliGrammar`) derived
  from a model: one entry per parameter, an explicit command tree.
- `src/clispec/parser.nim`: the argv parser, in phases (`cliTokenize`,
  `cliMerge`, `cliDecide`) plus the conversion helpers generated code calls.
  A library that adds sources replaces `cliMerge` with its own and fills the
  same `CliResolution`.
- `src/clispec/candidates.nim`: candidates, the values a source supplies for
  a parameter (the command line's with their argv index and spelling).
- `src/clispec/values.nim`: text to typed values (`parseCliValue`).
- `src/clispec/errors.nim`: the usage-error taxonomy (`CliErrorKind`, one
  wording per kind in `cliErrorMessage`) and `CliHelpRequest`.
- `src/clispec/help.nim`: human-readable help and the `clispec-help/1` JSON.
- `src/clispec/completers.nim`: the completer type (`CliCompleter`,
  `CliCompletionContext`, `CliCompletion`), the check `cliModelTypeChecks`
  generates for `complete =`, and the path completers. Depends on nothing
  else in the library, so `dsl.nim` can import it.
- `src/clispec/completion.nim`: the completion engine (`cliComplete`, which
  walks the words with the parser's flag matching, `cliMatchFlagWord`), the
  `__complete` protocol (`cliCompletionReply`, `CliCompletionRequest`), the
  bash command-line reader and per-shell quoting.
- `src/clispec/completion_scripts.nim`: the Bash, Zsh, Fish and PowerShell
  scripts (`cliCompletionScript`). They stay thin: no knowledge of any
  command line, and nothing the program prints is evaluated.
- `src/clispec/program.nim`: `cliProgram` / `cliProgramCode`, the generator,
  and the names and shapes it generates (`cliGeneratedNames`,
  `cliShapedTypeDecls`, `cliShapedBuilderProc`, `cliShapedVisitorProc`,
  `cliFieldBare`, `cliFieldAllowed`, `cliProgramArgs`) for a library that
  generates code beside it (confutils does).
- `tests/`: `test_dsl_model.nim` (every construct of the language parses into
  the model), `test_extension.nim` (a consumer extension, driven through
  the real parser), `test_cs_m2_model_round_trip.nim` (every named argument a
  program declares about itself, field by field) and
  `test_cs_m2_invalid_declarations_fail_to_compile.nim`, which runs
  `nim check` on each fixture in `tests/fixtures/cs_m2_invalid/` (one invalid
  line each, marked `# clispec-invalid`, with the expected message in an
  `## expect:` header) and again with that line removed.
  The `test_cs_m3_*` tests drive generated programs: every accepted argv
  form, the error taxonomy (a golden table indexed by `CliErrorKind`, so a
  new kind without a case does not compile) and help against the model.
  `test_readme_examples.nim` compiles and runs every fenced `nim` block of the
  README. The `test_cs_m4b_*` tests cover naming conventions: the
  conversion table, the command line in its own convention and every
  source's spelling in the model and help, and the precedence of the
  overrides. (Loading configuration files and the environment, merging and
  origins are tested in confutils.) The `test_cs_m5_*`
  tests cover completion: the engine's exact candidates at every word
  position and the protocol answer per shell, and `internal` parameters
  (accepted, in no help screen, never completed, marked in the JSON).
  `tests/e2e_cs_m5_real_shell_completion.nim` (`just e2e`) types into real
  shells on a pseudo-terminal it opens and reads what the fixture
  `tests/fixtures/cs_m5_shell/shx.nim` received.
- `tests/test_suite_lists_agree.nim` keeps the three lists of test modules
  equal: the Justfile's `tests`, the nimble `test` task and `repro.nim`'s
  `clispecTests` (and for `tests/e2e_*.nim`: the Justfile's `e2e-tests`,
  the nimble `e2e` task and the `realShells: true` entries). A new test
  module goes into all three lists.
- The `test_cs_m10_*` tests cover the opt-in features for command lines
  that come from confutils' type-based loader: the help layout, placeholders
  and long help (`test_cs_m10_help_layout`), each parsing rule and its
  absence (`test_cs_m10_parse_compat_rules`; the lone-dash and one-letter
  rules in `test_cs_m10_dash_and_letter_rules`, checked against what the
  nim-confutils fork's getopt-based parser gave), and a generic `record`-like
  command whose parse results and options table are checked against what
  confutils' loader and `renderOptionsTable` produced for the equivalent
  type (`test_cs_m10_confutils_compat_record`).
- `tests/test_cs_m9_clispec_has_no_serialization_dependency.nim` fails when
  `clispec.nimble`, `flake.nix` or `repro.nim` declares a serialization
  library or a module under `src/` imports one.

## Rules

- **This repository is public.** Code, comments, docs and commit messages
  explain clispec on its own terms. Do not cite or link private
  specifications or private repositories, and do not name machines.
- **The library knows no consumer's vocabulary.** A word that only one
  consumer needs (for example, which parameters name a build's outputs)
  belongs in that consumer's extension, declared through the `ext` slots and
  the two hooks, not in the model or the parser.
- **Spell names through `cliConvert`.** A long flag or a configuration key
  comes from the model's `longName`, `configKey` and `sourceKeys`, which the
  parser derives with the source's convention and the parameter's
  overrides. Never rebuild one from `name` (`"--" & p.name`); use
  `cliLongName` / `cliSourceKeyOf` on the grammar.
- **Grammar changes change consumers.** Consumers build their command lines
  and the external tools they run on this parser, and keep golden captures of
  what it produces. A change to what an existing declaration means is a
  breaking change: say so in the commit message, and prefer adding a new
  named argument to reinterpreting an old one.
- **Tests run the real parser.** Each test feeds a real `cli:` body through
  the compile-time parser and checks the model. A test that expects a
  compile error pairs it with the same body made valid, so the check cannot
  pass because the body was malformed in some other way. A new class of
  invalid declaration gets a fixture in `tests/fixtures/cs_m2_invalid/`.
- **One wording per usage error.** A new kind of command-line error is a
  new `CliErrorKind` with its wording in `cliErrorMessage` and a case in
  the golden table of `test_cs_m3_parser_error_taxonomy`. The parser and
  generated code raise or return; nothing ends the process.
- **Tests kill only what they started.** A test that runs processes (the
  e2e shells) stops them by the pid it got when it started them, never by
  name or pattern (`pkill`, `killall`), and every read it makes has a
  deadline.
- **The completion protocol is a contract too.** An installed script can be
  older than the program it calls, so within a shell name the arguments and
  the answer only change compatibly.
- **The help JSON is a contract.** Within `clispec-help/1` keys are only
  added, never renamed or removed; anything else is a new schema name.
- **No serialization library, anywhere.** Configuration files and their
  formats belong to confutils. What they need is declared in the
  description (`env`, `key`, `sources`, `merge`, `configSchema`,
  conventions) and kept in the model; reading them is not this library's
  job.
- **Every diagnostic names what it is about.** Errors about a parameter go
  through `cliParamError` (`clispec: parameter '<name>': ...`); errors about a
  command name it with `cliCommandLabel`.
- Every Nim compile keeps its nimcache inside the checkout (`config.nims`).
  The Justfile passes `--skipParentCfg`, so each recipe names its own
  `--nimcache:` under `.nimcache/`.
- Commit messages follow Conventional Commits (`type(scope): summary`, under
  72 characters) with a body that says why.
