## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'level': refuseFalse applies to a switch (a bool), not int

import clispec

const model {.used.} = plainCliModel:
  flag level is int, refuseFalse = true  # clispec-invalid
  boolFlag split is bool, refuseFalse = true
