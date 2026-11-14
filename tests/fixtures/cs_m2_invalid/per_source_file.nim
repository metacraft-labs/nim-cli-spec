## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'jobs': the override for every file source is written key = "<dotted.key>", not perSource = [file = ...]

import clispec

const model {.used.} = plainCliModel:
  flag jobs is int, perSource = [file = "build.jobs"]  # clispec-invalid
  flag level is int
