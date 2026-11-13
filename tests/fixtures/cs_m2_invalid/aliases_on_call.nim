## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: the anonymous `call:` command has no command word, so it cannot have aliases

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call(aliases = ["x"]): pos path is string  # clispec-invalid
  subcmd "x":
    pos other is string
