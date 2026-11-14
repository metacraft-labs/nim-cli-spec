## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'repo': complete = `repoNames` is not a completer; it must be a CliCompleter: proc (ctx: CliCompletionContext): seq[CliCompletion]

import clispec

proc repoNames(prefix: string): seq[string] =
  ## Takes the typed prefix and returns bare strings, not the context and
  ## candidates a completer receives and returns.
  @[prefix]

proc branchNames(ctx: CliCompletionContext): seq[CliCompletion] =
  cliCompletions(["main", "dev"])

const model {.used.} = plainCliModel:
  call:
    flag repo is string, complete = repoNames  # clispec-invalid
    flag branch is string, complete = branchNames
