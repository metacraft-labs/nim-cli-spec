## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'token': perSource gives a cli spelling, but `sources` exclude cli

import clispec

const model {.used.} = plainCliModel:
  flag token is string, sources = {env, file}, env = ["T"], perSource = [cli = "tok"]  # clispec-invalid
  flag level is int
