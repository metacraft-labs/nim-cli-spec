## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'HTTPPort': configuration key 'http_port' is already used by 'httpPort'

import clispec

const model {.used.} = plainCliModel:
  convention file = snakeCase
  flag httpPort is int, alias = "--a"
  flag HTTPPort is int, alias = "--b"  # clispec-invalid
