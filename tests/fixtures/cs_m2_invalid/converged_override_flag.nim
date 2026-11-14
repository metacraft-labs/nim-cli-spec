## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'b': spelling '--b' is already used by 'a'

import clispec

const model {.used.} = plainCliModel:
  flag a is int, perSource = [cli = "b"]
  flag b is int  # clispec-invalid
