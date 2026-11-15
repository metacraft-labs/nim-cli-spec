## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: commandMatching must be exact, ignoreCase or ignoreStyle, not fuzzy

import clispec

const model {.used.} = plainCliModel:
  commandMatching fuzzy  # clispec-invalid
  subcmd "list":
    pos target is string
