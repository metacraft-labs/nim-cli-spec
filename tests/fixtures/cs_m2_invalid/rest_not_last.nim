## A fixture of test_cs_m2_invalid_declarations_fail_to_compile: the line
## marked ``clispec-invalid`` makes this description invalid; the test
## compiles this file and expects the error below, then compiles it again
## without that line and expects success.
## expect: clispec: parameter 'extra': command 'run' takes the rest of the command line in an earlier positional, so no positional can follow it

import clispec

cliProgram(Tool, "tool"):
  subcmd "run":
    pos program is string
    pos args is seq[string], rest = true, required = false
    pos extra is string, required = false  # clispec-invalid
