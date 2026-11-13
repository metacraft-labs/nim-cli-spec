## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'remove': the word 'rm' is already used by command 'rm'

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  subcmd "rm":
    pos path is string
  subcmd "remove", aliases = ["rm"]: pos target is string  # clispec-invalid
  subcmd "delete", aliases = ["del"]:
    pos victim is string
