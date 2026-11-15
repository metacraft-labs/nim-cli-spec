## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'show': shadowedByWord applies to a subcommand that answers to the word help under parsing helpWord or version under parsing versionWord, and this one answers to neither

import clispec

const model {.used.} = plainCliModel:
  parsing helpWord, versionWord
  subcmd "help", shadowedByWord = true:
    pos topic is string, required = false
  subcmd "show", aliases = ["display"], shadowedByWord = true: discard  # clispec-invalid
