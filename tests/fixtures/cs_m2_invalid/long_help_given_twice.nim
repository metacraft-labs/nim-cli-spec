## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'build' is given longHelp twice

import clispec

const model {.used.} = plainCliModel:
  subcmd "build", longHelp = "Builds everything.":
    longHelp "Builds everything, again."  # clispec-invalid
    flag output is string
