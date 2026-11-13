## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'token': `env` names environment variables, but `sources` exclude env

import clispec

type
  Color = enum
    red, green
  Name = string
  Count = int

const model {.used.} = plainCliModel:
  call:
    flag token is string, sources = {cli}, env = ["TOKEN"]  # clispec-invalid
    flag user is string, env = ["USER_NAME"]
