## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'report': `optionalValue` and `required = true` are mutually exclusive

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    flag report is string, optionalValue = "r.json", required = true  # clispec-invalid
    flag trace is string, optionalValue = "t.json"
