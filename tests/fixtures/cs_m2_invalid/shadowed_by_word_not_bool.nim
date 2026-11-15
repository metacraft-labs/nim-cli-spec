## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'help': shadowedByWord must be true or false, got: yes

import clispec

const model {.used.} = plainCliModel:
  parsing helpWord
  subcmd "list":
    discard
  subcmd "help", shadowedByWord = yes: discard  # clispec-invalid
