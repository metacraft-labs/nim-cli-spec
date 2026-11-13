## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'fast': implies jobs = `"many"`, which is not a valid int

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    flag jobs is int
    boolFlag fast is bool, implies = [jobs = "many"]  # clispec-invalid
    boolFlag slow is bool, implies = [jobs = 1]
