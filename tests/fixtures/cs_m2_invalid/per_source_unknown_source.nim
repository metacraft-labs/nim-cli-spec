## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'jobs': perSource names the file source 'project', which the description does not declare

import clispec

const model {.used.} = plainCliModel:
  convention "user" = kebabCase
  flag jobs is int, perSource = ["project" = "build.jobs"]  # clispec-invalid
  flag level is int
