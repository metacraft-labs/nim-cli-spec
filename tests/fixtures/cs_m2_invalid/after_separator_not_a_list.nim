## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'command': afterSeparator takes the words after --, so its type is a list (a seq), not string

import clispec

const model {.used.} = plainCliModel:
  pos selector is string, required = false
  pos command is string, afterSeparator = true  # clispec-invalid
