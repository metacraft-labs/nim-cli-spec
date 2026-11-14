## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'level': configuration key 'jobs' in file source 'project' is already used by 'count'

import clispec

const model {.used.} = plainCliModel:
  convention "project" = kebabCase
  flag count is int, perSource = ["project" = "jobs"]
  flag level is int, perSource = ["project" = "jobs"]  # clispec-invalid
