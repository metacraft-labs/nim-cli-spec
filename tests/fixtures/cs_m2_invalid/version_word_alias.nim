## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'show': the word 'version' asks for the version under parsing versionWord, so no subcommand can answer to it

import clispec

const model {.used.} = plainCliModel:
  parsing versionWord
  subcmd "list":
    pos target is string
  subcmd "show", aliases = ["version"]: pos what is string  # clispec-invalid
