## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'target': a positional has no long flag, so perSource cannot give its cli spelling

import clispec

const model {.used.} = plainCliModel:
  pos target is string, perSource = [cli = "t"]  # clispec-invalid
  flag level is int
