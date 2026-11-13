## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'verbosity': counted requires an integer type, not string

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    flag verbosity is string, counted = true  # clispec-invalid
    flag level is int, counted = true
