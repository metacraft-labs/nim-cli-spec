## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'quiet': short '-v' is already used by 'verbose'

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    boolFlag verbose is bool, short = 'v'
    boolFlag quiet is bool, short = 'v'  # clispec-invalid
    boolFlag quieter is bool, short = 'q'
