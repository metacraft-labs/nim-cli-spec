## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'HELP': the word 'HELP' asks for the help under parsing helpWord, so no subcommand can answer to it

import clispec

const model {.used.} = plainCliModel:
  commandMatching ignoreCase
  parsing helpWord
  subcmd "list":
    pos target is string
  subcmd "HELP": pos topic is string  # clispec-invalid
