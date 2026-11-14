## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: flagMatching must be exact, ignoreCase or ignoreStyle, not caseless

import clispec

const model {.used.} = plainCliModel:
  flagMatching caseless  # clispec-invalid
  flag output is string
