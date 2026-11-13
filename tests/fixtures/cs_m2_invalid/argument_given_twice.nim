## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'output': `help` is given twice

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    flag output is string, help = "where", help = "to"  # clispec-invalid
    flag input is string, help = "from"
