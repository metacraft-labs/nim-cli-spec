## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'jobs': perConvention cannot override `declared`: that is the name as written

import clispec

const model {.used.} = plainCliModel:
  flag jobs is int, perConvention = [declared = "j"]  # clispec-invalid
  flag level is int
