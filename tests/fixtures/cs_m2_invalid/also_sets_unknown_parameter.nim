## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'coop': alsoSets names 'atach', which is not a parameter of the root command

import clispec

const model {.used.} = plainCliModel:
  flag attach is string
  boolFlag coop is bool, alsoSets = [atach = "late"]  # clispec-invalid
  boolFlag early is bool, alsoSets = [attach = "early"]
