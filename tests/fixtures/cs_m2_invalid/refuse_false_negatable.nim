## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'split': refuseFalse and negatable contradict each other

import clispec

const model {.used.} = plainCliModel:
  boolFlag split is bool, negatable = true, refuseFalse = true  # clispec-invalid
  boolFlag pager is bool, refuseFalse = true
