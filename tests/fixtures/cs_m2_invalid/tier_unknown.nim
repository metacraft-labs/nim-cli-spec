## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: command 'graph': tier must be primary or secondary, got: rare

import clispec

const model {.used.} = plainCliModel:
  subcmd "build", tier = secondary:
    discard
  subcmd "graph", tier = rare: discard  # clispec-invalid
