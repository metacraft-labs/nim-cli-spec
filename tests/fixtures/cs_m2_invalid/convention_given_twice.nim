## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: the convention of source 'cli' is given twice

import clispec

const model {.used.} = plainCliModel:
  convention cli = kebabCase
  convention cli = snakeCase  # clispec-invalid
  flag jobs is int
