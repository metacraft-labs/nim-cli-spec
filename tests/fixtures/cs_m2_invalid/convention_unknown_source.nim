## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: convention names the source cli, file or a file source's name as a string ("project"), not env

import clispec

const model {.used.} = plainCliModel:
  convention env = kebabCase  # clispec-invalid
  flag jobs is int
