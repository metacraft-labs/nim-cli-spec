## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'pager': negatable must be true or false, got: yes

import clispec

const model {.used.} = plainCliModel:
  call:
    boolFlag pager is bool, negatable = yes  # clispec-invalid
    boolFlag color is bool, negatable = true
