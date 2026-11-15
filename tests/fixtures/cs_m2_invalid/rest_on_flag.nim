## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'args': `rest` applies to positionals only, not to a flag

import clispec

const model {.used.} = plainCliModel:
  pos program is string
  flag args is seq[string], rest = true  # clispec-invalid
