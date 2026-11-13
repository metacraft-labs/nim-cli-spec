# nim-cli-spec — Agent Instructions

Clispec: a typed model of a command line (`src/clispec/model.nim`) and the
`cli:` description language that builds it at compile time
(`src/clispec/dsl.nim`). `README.md` describes both and the extension
mechanism; read it first.

## Commands

- Dev shell: `nix develop` (nim, just and the pre-commit tools).
- Test: `just test` (also `nimble test`).
- Lint: `just lint` (`nim check` over the umbrella and every test).
- Build without running: `just build`.

## Layout

- `src/clispec.nim`: the umbrella; re-exports `model` and `dsl`.
- `src/clispec/model.nim`: the model types. Plain values, usable at compile
  time and at run time.
- `src/clispec/dsl.nim`: the compile-time parser, the extension hooks'
  contract, and the `cli`-prefixed AST helpers extension hooks use.
- `tests/`: `test_dsl_model.nim` (every construct of the language parses into
  the model) and `test_extension.nim` (a consumer extension, driven through
  the real parser).

## Rules

- **This repository is public.** Code, comments, docs and commit messages
  explain clispec on its own terms. Do not cite or link private
  specifications or private repositories, and do not name machines.
- **The library knows no consumer's vocabulary.** A word that only one
  consumer needs (for example, which parameters name a build's outputs)
  belongs in that consumer's extension, declared through the `ext` slots and
  the two hooks, not in the model or the parser.
- **Grammar changes change consumers.** Consumers build their command lines
  and the external tools they run on this parser, and keep golden captures of
  what it produces. A change to what an existing declaration means is a
  breaking change: say so in the commit message, and prefer adding a new
  named argument to reinterpreting an old one.
- **Tests run the real parser.** Each test feeds a real `cli:` body through
  the compile-time parser and checks the model. A test that expects a
  compile error pairs it with the same body made valid, so the check cannot
  pass because the body was malformed in some other way.
- Every Nim compile keeps its nimcache inside the checkout (`config.nims`).
  The Justfile passes `--skipParentCfg`, so each recipe names its own
  `--nimcache:` under `.nimcache/`.
- Commit messages follow Conventional Commits (`type(scope): summary`, under
  72 characters) with a body that says why.
