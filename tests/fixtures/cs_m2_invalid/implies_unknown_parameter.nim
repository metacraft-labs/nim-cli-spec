## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'debug': implies 'verbos', which is not a parameter of the anonymous call: command

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    boolFlag verbose is bool
    boolFlag debug is bool, implies = [verbos = true]  # clispec-invalid
    boolFlag trace is bool, implies = [verbose = true]
