## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: keyStyle must be declared, camelCase, snakeCase or kebabCase, not titleCase

import clispec

const model {.used.} = plainCliModel:
  keyStyle titleCase  # clispec-invalid
  flag jobs is int
