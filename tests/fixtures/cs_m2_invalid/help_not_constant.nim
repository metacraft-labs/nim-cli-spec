## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'output': help = `runtimeText` is not a constant string expression

import clispec

var runtimeText {.used.} = "known only when the program runs"

const model {.used.} = plainCliModel:
  flag output is string, help = runtimeText  # clispec-invalid
  flag other is string, help = "x" & "y"
