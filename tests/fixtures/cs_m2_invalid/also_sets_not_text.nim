## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'coop': alsoSets entries are written <parameter> = "<value as written on the command line>", got: attach = late

import clispec

const model {.used.} = plainCliModel:
  flag attach is string
  boolFlag coop is bool, alsoSets = [attach = late]  # clispec-invalid
  boolFlag early is bool, alsoSets = [attach = "early"]
